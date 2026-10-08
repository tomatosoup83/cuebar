import Foundation
import CryptoKit

/// Groups a flat library (songs) into playable album rows.
///
/// Music's scripting dictionary has no album object, so an album is derived
/// from its tracks: they are grouped by album title + album artist and ordered
/// by disc then track number. The original tracks are kept so a selected album
/// can be played start to finish.
public struct LibraryAlbumIndex: Sendable {
    /// One `MusicCandidate` (kind `.album`, source `.library`) per album.
    public let albums: [MusicCandidate]

    private let tracksByAlbumID: [String: [MusicCandidate]]

    public init(tracks: [MusicCandidate]) {
        var grouped: [String: [MusicCandidate]] = [:]
        for track in tracks where track.kind == .song {
            guard !track.normalizedAlbum.isEmpty else { continue }
            grouped[Self.groupKey(for: track), default: []].append(track)
        }

        var albums: [MusicCandidate] = []
        var byID: [String: [MusicCandidate]] = [:]
        albums.reserveCapacity(grouped.count)

        for (key, members) in grouped {
            let ordered = members.sorted(by: Self.trackOrder)
            let id = Self.albumID(for: key)
            byID[id] = ordered
            albums.append(Self.albumCandidate(id: id, tracks: ordered))
        }

        // Deterministic order for equal queries; the ranker re-sorts anyway.
        albums.sort { lhs, rhs in
            if lhs.normalizedTitle != rhs.normalizedTitle {
                return lhs.normalizedTitle < rhs.normalizedTitle
            }
            return lhs.id < rhs.id
        }

        self.albums = albums
        self.tracksByAlbumID = byID
    }

    /// The album's tracks, in play order, for a given album id.
    public func tracks(forAlbumID id: String) -> [MusicCandidate]? {
        tracksByAlbumID[id]
    }

    // MARK: - Internals

    private static func groupKey(for track: MusicCandidate) -> String {
        let albumArtist = track.albumArtist.flatMap { $0.isEmpty ? nil : $0 } ?? track.artist
        return track.normalizedAlbum + "|" + TextNormalizer.normalize(albumArtist)
    }

    private static func albumID(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "library:album:" + hex.prefix(16)
    }

    /// Disc, then track number, then title — stable for missing numbers.
    private static func trackOrder(_ lhs: MusicCandidate, _ rhs: MusicCandidate) -> Bool {
        let lhsDisc = lhs.discNumber ?? 1
        let rhsDisc = rhs.discNumber ?? 1
        if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }

        let lhsTrack = lhs.trackNumber ?? 0
        let rhsTrack = rhs.trackNumber ?? 0
        if lhsTrack != rhsTrack { return lhsTrack < rhsTrack }

        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        return (lhs.persistentID ?? lhs.id) < (rhs.persistentID ?? rhs.id)
    }

    private static func albumCandidate(id: String, tracks: [MusicCandidate]) -> MusicCandidate {
        let representative = tracks.first(where: { !($0.persistentID ?? "").isEmpty }) ?? tracks[0]
        let albumArtist = representative.albumArtist.flatMap { $0.isEmpty ? nil : $0 } ?? representative.artist
        let duration = tracks.compactMap(\.durationSeconds).reduce(0, +)

        return MusicCandidate(
            id: id,
            kind: .album,
            source: .library,
            title: representative.album,
            artist: albumArtist,
            album: representative.album,
            durationSeconds: duration > 0 ? duration : nil,
            trackCount: tracks.count,
            artworkTrackID: representative.persistentID,
            // Facts for the extended album view. Both come from the album's own
            // tracks, so a mixed compilation resolves to whichever value is most
            // common rather than to whichever track happened to come first.
            year: mostCommon(tracks.map(\.year)),
            genre: mostCommon(tracks.map(\.genre))
        )
    }

    /// The most frequent non-nil value, with a deterministic tie-break (the
    /// lowest value wins) so album rows stay stable across re-indexes.
    private static func mostCommon<T: Hashable & Comparable>(_ values: [T?]) -> T? {
        var counts: [T: Int] = [:]
        for value in values.compactMap({ $0 }) {
            counts[value, default: 0] += 1
        }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
