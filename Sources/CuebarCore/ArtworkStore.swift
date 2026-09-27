import Foundation
import AppKit
import CryptoKit

/// Where a piece of artwork comes from.
public enum ArtworkSource: Hashable, Sendable {
    /// A track in the user's Music library, fetched from Music.app by ID.
    case library(persistentID: String, artist: String, album: String)
    /// Whatever Music.app currently has loaded.
    case nowPlaying(persistentID: String?, artist: String, album: String, title: String)
    /// A remote image URL (catalog artwork).
    case remote(URL)

    /// Stable cache identity. Album-based when possible so every track on an
    /// album shares one cached image.
    public var cacheKey: String {
        switch self {
        case .library(let persistentID, let artist, let album):
            return Self.albumKey(artist: artist, album: album) ?? "track:\(persistentID)"
        case .nowPlaying(let persistentID, let artist, let album, let title):
            return Self.albumKey(artist: artist, album: album)
                ?? "track:\(persistentID ?? title)"
        case .remote(let url):
            return "remote:\(url.absoluteString)"
        }
    }

    static func albumKey(artist: String, album: String) -> String? {
        let normalizedAlbum = TextNormalizer.normalize(album)
        guard !normalizedAlbum.isEmpty else { return nil }
        let normalizedArtist = TextNormalizer.normalize(artist)
        return "album:\(normalizedArtist)|\(normalizedAlbum)"
    }
}

/// Provides raw artwork bytes for a Music.app track (nil = current track).
public protocol ArtworkDataProviding: Sendable {
    func artworkData(for persistentID: String?) async throws -> Data?
}

/// Disk + memory cache for album artwork.
///
/// Fetches once per album, downscales to a small JPEG and stores it under
/// `Application Support/Cuebar/artwork`, so art appears instantly on every later
/// display (including after relaunch).
public final class ArtworkStore: @unchecked Sendable {
    public static let shared = ArtworkStore()

    private let directory: URL
    private let provider: ArtworkDataProviding
    private let session: URLSession
    private let maxDimension: CGFloat

    private let memory = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    public init(
        provider: ArtworkDataProviding = AppleScriptArtworkProvider(),
        session: URLSession = .shared,
        directory: URL? = nil,
        maxDimension: CGFloat = 256
    ) {
        self.provider = provider
        self.session = session
        self.maxDimension = maxDimension

        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("Cuebar/artwork", isDirectory: true)
        }
        memory.countLimit = 300
    }

    // MARK: - Public

    /// Synchronous cache lookup, used to paint art on the very first frame.
    public func cachedImage(for source: ArtworkSource) -> NSImage? {
        let key = source.cacheKey
        if let image = memory.object(forKey: key as NSString) { return image }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Returns cached artwork, or fetches, downscales and caches it.
    public func image(for source: ArtworkSource) async -> NSImage? {
        if let cached = cachedImage(for: source) { return cached }
        let key = source.cacheKey

        let task = inFlightTask(for: key) { [weak self] in
            Task<NSImage?, Never> {
                guard let self else { return nil }
                let image = await self.loadAndCache(source: source, key: key)
                self.clearInFlight(for: key)
                return image
            }
        }
        return await task.value
    }

    // MARK: - Internals

    /// Returns the in-flight task for `key`, creating one via `make` if needed.
    /// Kept synchronous so it is safe to lock from async callers.
    private func inFlightTask(
        for key: String,
        make: () -> Task<NSImage?, Never>
    ) -> Task<NSImage?, Never> {
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

    private func loadAndCache(source: ArtworkSource, key: String) async -> NSImage? {
        guard let raw = await rawData(for: source), !raw.isEmpty else { return nil }
        guard let processed = Self.downscale(data: raw, maxDimension: maxDimension) else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try processed.data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Caching is best-effort; the image is still returned below.
        }

        memory.setObject(processed.image, forKey: key as NSString)
        return processed.image
    }

    private func rawData(for source: ArtworkSource) async -> Data? {
        switch source {
        case .library(let persistentID, _, _):
            return try? await provider.artworkData(for: persistentID)
        case .nowPlaying:
            return try? await provider.artworkData(for: nil)
        case .remote(let url):
            return try? await download(url)
        }
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("jpg")
    }

    /// Downscales image data to `maxDimension` on the long edge and re-encodes
    /// it as JPEG. Uses ImageIO so it is thread-safe.
    static func downscale(data: Data, maxDimension: CGFloat) -> (image: NSImage, data: Data)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let encoded = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) ?? data
        return (image, encoded)
    }
}
