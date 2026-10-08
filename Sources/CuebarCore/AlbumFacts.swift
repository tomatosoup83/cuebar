import Foundation

/// The one-line summary shown at the top of the extended album view.
///
/// Every part is optional except the track count, and empty parts are dropped
/// rather than shown as blanks, so a sparsely tagged album still reads as a
/// sentence: `2007 · Alternative · 10 tracks · 42 min`.
public struct AlbumFacts: Equatable, Sendable {
    public let year: Int?
    public let genre: String?
    public let trackCount: Int
    public let durationSeconds: Double?

    public init(
        year: Int? = nil,
        genre: String? = nil,
        trackCount: Int,
        durationSeconds: Double? = nil
    ) {
        self.year = year
        self.genre = genre
        self.trackCount = trackCount
        self.durationSeconds = durationSeconds
    }

    /// Builds the facts for an album row plus its ordered tracks.
    public init(album: MusicCandidate, tracks: [MusicCandidate]) {
        let total = tracks.compactMap(\.durationSeconds).reduce(0, +)
        self.init(
            year: album.year,
            genre: album.genre,
            trackCount: tracks.isEmpty ? (album.trackCount ?? 0) : tracks.count,
            durationSeconds: total > 0 ? total : album.durationSeconds
        )
    }

    /// `2007 · Alternative · 10 tracks · 42 min`
    public var summary: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let genre, !genre.isEmpty { parts.append(genre) }
        if trackCount > 0 {
            parts.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        }
        if let minutes = Self.minutes(durationSeconds) {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    /// Whole minutes, rounding to nearest, or nil when there's nothing useful
    /// to say (missing duration, or a sub-30-second rounding to zero).
    static func minutes(_ seconds: Double?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return minutes > 0 ? minutes : nil
    }
}
