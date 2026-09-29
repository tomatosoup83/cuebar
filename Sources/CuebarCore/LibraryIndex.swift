import Foundation

/// A snapshot of the user's Music library.
public struct LibraryIndex: Sendable, Codable {
    /// Bumped whenever the persisted shape or normalization changes.
    /// 2: added album artist / disc number / track number (album playback).
    /// 3: added library playlists.
    public static let currentVersion = 3

    public var version: Int
    public var tracks: [MusicCandidate]
    public var playlists: [MusicCandidate]
    public var builtAt: Date

    public init(
        tracks: [MusicCandidate],
        playlists: [MusicCandidate] = [],
        builtAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.tracks = tracks
        self.playlists = playlists
        self.builtAt = builtAt
    }
}

/// Counts from a library (re)index, for user feedback.
public struct LibraryIndexSummary: Equatable, Sendable {
    public let trackCount: Int
    public let playlistCount: Int

    public init(trackCount: Int, playlistCount: Int) {
        self.trackCount = trackCount
        self.playlistCount = playlistCount
    }
}

/// Persists the library index so launches after the first are instant.
public final class LibraryIndexStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager = FileManager.default

    public init(directoryName: String = "Cuebar") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("library-index.json")
    }

    public var url: URL { fileURL }

    public func loadCached() -> LibraryIndex? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let index = try? JSONDecoder().decode(LibraryIndex.self, from: data) else { return nil }
        guard index.version == LibraryIndex.currentVersion else { return nil }
        return index
    }

    public func save(_ index: LibraryIndex) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(index)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Cuebar: failed to persist library index: \(error)")
        }
    }

    public func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
