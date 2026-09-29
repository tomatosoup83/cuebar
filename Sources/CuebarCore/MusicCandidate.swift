import Foundation

/// Where a result came from.
public enum MusicSource: String, Sendable, Codable, Hashable {
    case library
    case catalog
}

/// The kind of music item a result represents.
public enum MusicKind: String, Sendable, Codable, Hashable {
    case song
    case album
    case playlist
    case artist
}

/// A single searchable/playable music item.
///
/// Normalized copies of the text fields are stored so ranking is fast and
/// deterministic even for large libraries.
public struct MusicCandidate: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let kind: MusicKind
    public let source: MusicSource
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Double?
    public let artworkURL: URL?
    /// Catalog items can be played by opening this URL in Music.app.
    public let playbackURL: URL?
    /// Library items are played by persistent ID.
    public let persistentID: String?

    // Album metadata (library). Optional so catalog rows and older cached
    // indexes decode without them.
    /// Album artist, used to group compilations into a single album.
    public let albumArtist: String?
    public let discNumber: Int?
    public let trackNumber: Int?
    /// Number of tracks in the album (album rows only).
    public let trackCount: Int?
    /// A representative track whose artwork to show for an album row.
    public let artworkTrackID: String?

    public let normalizedTitle: String
    public let normalizedArtist: String
    public let normalizedAlbum: String

    public init(
        id: String,
        kind: MusicKind,
        source: MusicSource,
        title: String,
        artist: String,
        album: String,
        durationSeconds: Double? = nil,
        artworkURL: URL? = nil,
        playbackURL: URL? = nil,
        persistentID: String? = nil,
        albumArtist: String? = nil,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        trackCount: Int? = nil,
        artworkTrackID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.artworkURL = artworkURL
        self.playbackURL = playbackURL
        self.persistentID = persistentID
        self.albumArtist = albumArtist
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.trackCount = trackCount
        self.artworkTrackID = artworkTrackID
        self.normalizedTitle = TextNormalizer.normalize(title)
        self.normalizedArtist = TextNormalizer.normalize(artist)
        self.normalizedAlbum = TextNormalizer.normalize(album)
    }

    /// Secondary line shown in the palette, e.g. "a-ha · Hunting High and Low".
    public var subtitle: String {
        var parts: [String] = []
        if !artist.isEmpty { parts.append(artist) }
        if !album.isEmpty, album != title { parts.append(album) }
        if (kind == .album || kind == .playlist), let trackCount {
            parts.append("\(trackCount) track\(trackCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
