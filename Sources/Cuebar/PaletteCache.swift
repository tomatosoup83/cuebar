import AppKit
import CuebarCore

/// Extracts and memoises album palettes, keyed the same way as artwork.
///
/// Mirrors `ArtworkStore`: a synchronous cache lookup for painting on the first
/// frame, plus an async fetch that de-duplicates concurrent requests. Extraction
/// itself is cheap (a 24×24 grid) and runs once per album per algorithm.
///
/// The algorithm is part of the key so the two Album Art themes can be compared
/// without clobbering each other's cached palette.
final class PaletteCache: @unchecked Sendable {
    static let shared = PaletteCache()

    private final class Box {
        let palette: AlbumPalette
        init(_ palette: AlbumPalette) { self.palette = palette }
    }

    private let store: ArtworkStore
    private let memory = NSCache<NSString, Box>()
    private let lock = NSLock()
    private var inFlight: [String: Task<AlbumPalette?, Never>] = [:]

    init(store: ArtworkStore = .shared) {
        self.store = store
        memory.countLimit = 300
    }

    /// Synchronous cache lookup; never triggers a fetch.
    func cached(for source: ArtworkSource, style: PaletteStyle) -> AlbumPalette? {
        memory.object(forKey: key(source, style) as NSString)?.palette
    }

    /// Returns the cached palette, or fetches the art and extracts one.
    func palette(
        for source: ArtworkSource,
        style: PaletteStyle
    ) async -> AlbumPalette? {
        let cacheKey = key(source, style)
        if let cached = memory.object(forKey: cacheKey as NSString)?.palette { return cached }

        let task = inFlightTask(for: cacheKey) { [store] in
            Task<AlbumPalette?, Never> {
                guard let image = await store.image(for: source),
                      let cgImage = image.cgImageRepresentation,
                      let grid = PaletteExtractor.grid(from: cgImage) else {
                    return nil
                }
                return PaletteExtractor.palette(
                    from: grid,
                    algorithm: style.algorithm,
                    layout: style.clusterLayout
                )
            }
        }

        let palette = await task.value
        clearInFlight(for: cacheKey)
        if let palette {
            memory.setObject(Box(palette), forKey: cacheKey as NSString)
        }
        return palette
    }

    // MARK: - Internals

    /// The cache identity: artwork identity plus the full extraction style.
    private func key(_ source: ArtworkSource, _ style: PaletteStyle) -> String {
        "\(style.key)|\(source.cacheKey)"
    }

    /// Returns the in-flight task for `key`, creating one via `make` if needed.
    private func inFlightTask(
        for key: String,
        make: () -> Task<AlbumPalette?, Never>
    ) -> Task<AlbumPalette?, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[key] { return existing }
        let task = make()
        inFlight[key] = task
        return task
    }

    private func clearInFlight(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[key] = nil
    }
}
