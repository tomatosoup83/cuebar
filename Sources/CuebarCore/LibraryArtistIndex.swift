import Foundation
import CryptoKit

/// Groups a flat library (songs) into artist rows.
///
/// Like `LibraryAlbumIndex`, Music has no artist object to read, so an artist is
/// derived from their tracks. Grouping follows the album index's rule — **album
/// artist**, falling back to the track artist — so a compilation's tracks stay
/// together under "Various Artists" instead of scattering into each performer's
/// page.
///
/// Feature credits are deliberately *not* split: a track tagged
/// `Drake feat. J. Cole` becomes its own artist, because that is what the tag
/// says and guessing at the primary artist would be inconsistent across files.
public struct LibraryArtistIndex: Sendable {
    /// One `MusicCandidate` (kind `.artist`, source `.library`) per artist.
    public let artists: [MusicCandidate]

    private let tracksByArtistID: [String: [MusicCandidate]]

    public init(tracks: [MusicCandidate]) {
        var grouped: [String: [MusicCandidate]] = [:]
        for track in tracks where track.kind == .song {
            let name = Self.artistName(for: track)
            let key = TextNormalizer.normalize(name)
            guard !key.isEmpty else { continue }
            grouped[key, default: []].append(track)
        }

        var artists: [MusicCandidate] = []
        var byID: [String: [MusicCandidate]] = [:]
        artists.reserveCapacity(grouped.count)

        for (key, members) in grouped {
            let ordered = members.sorted(by: Self.trackOrder)
            let id = Self.artistID(for: key)
            byID[id] = ordered
            artists.append(Self.artistCandidate(id: id, tracks: ordered))
        }

        // Deterministic order for equal queries; the ranker re-sorts anyway.
        artists.sort { lhs, rhs in
            if lhs.normalizedTitle != rhs.normalizedTitle {
                return lhs.normalizedTitle < rhs.normalizedTitle
            }
            return lhs.id < rhs.id
        }

        self.artists = artists
        self.tracksByArtistID = byID
    }

    /// The artist's songs, in album/track order, for a given artist id.
    public func tracks(forArtistID id: String) -> [MusicCandidate]? {
        tracksByArtistID[id]
    }

    // MARK: - Internals

    /// Album artist when there is one, else the track artist — the same rule the
    /// album index uses, so an artist page and its albums never disagree.
    private static func artistName(for track: MusicCandidate) -> String {
        track.albumArtist.flatMap { $0.isEmpty ? nil : $0 } ?? track.artist
    }

    private static func artistID(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "library:artist:" + hex.prefix(16)
    }

    /// Album, then disc, then track — an artist page reads like a wall of albums.
    private static func trackOrder(_ lhs: MusicCandidate, _ rhs: MusicCandidate) -> Bool {
        if lhs.normalizedAlbum != rhs.normalizedAlbum {
            return lhs.normalizedAlbum < rhs.normalizedAlbum
        }
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

    private static func artistCandidate(id: String, tracks: [MusicCandidate]) -> MusicCandidate {
        let representative = tracks.first(where: { !($0.persistentID ?? "").isEmpty }) ?? tracks[0]
        let name = artistName(for: representative)

        return MusicCandidate(
            id: id,
            kind: .artist,
            source: .library,
            title: name,
            artist: name,
            album: "",
            trackCount: tracks.count,
            // Representative track, so the row and the artist page paint a real
            // cover through `PaletteItem.artworkSource`.
            artworkTrackID: representative.persistentID
        )
    }
}
