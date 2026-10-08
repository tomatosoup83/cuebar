import Foundation

/// An album's tracks in their original running order, each with the number the
/// extended album view shows beside it.
///
/// The numbers exist to make "original order" legible — every other list in
/// Cuebar is ranked or shuffled, so a bare title list wouldn't say what order it
/// is in. Single-disc albums show `1`, `2`, …; multi-disc albums show `1-1`,
/// `2-3`, … so the disc boundary is visible.
public struct AlbumTrackList: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let track: MusicCandidate
        /// `1` or, on a multi-disc album, `1-3`.
        public let number: String

        public var id: String { track.id }
    }

    public let entries: [Entry]

    public init(tracks: [MusicCandidate]) {
        // Multi-disc when the album uses more than one disc number, *or* when any
        // track is tagged beyond disc 1 — a library where only the second disc's
        // tracks carry the tag should still show the boundary.
        let discs = Set(tracks.compactMap(\.discNumber))
        let isMultiDisc = discs.count > 1 || discs.contains { $0 > 1 }

        self.entries = tracks.enumerated().map { offset, track in
            Entry(
                track: track,
                number: Self.number(for: track, at: offset, isMultiDisc: isMultiDisc)
            )
        }
    }

    /// A track's position, preferring its own tag but falling back to its place
    /// in the list so an untagged track never shows a blank column.
    private static func number(
        for track: MusicCandidate,
        at offset: Int,
        isMultiDisc: Bool
    ) -> String {
        let trackNumber = track.trackNumber.flatMap { $0 > 0 ? $0 : nil } ?? (offset + 1)
        guard isMultiDisc else { return String(trackNumber) }

        let disc = track.discNumber.flatMap { $0 > 0 ? $0 : nil } ?? 1
        return "\(disc)-\(trackNumber)"
    }
}
