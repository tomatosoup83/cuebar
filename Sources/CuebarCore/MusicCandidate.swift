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
        persistentID: String? = nil
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
        self.normalizedTitle = TextNormalizer.normalize(title)
        self.normalizedArtist = TextNormalizer.normalize(artist)
        self.normalizedAlbum = TextNormalizer.normalize(album)
    }

    /// Secondary line shown in the palette, e.g. "a-ha · Hunting High and Low".
    public var subtitle: String {
        var parts: [String] = []
        if !artist.isEmpty { parts.append(artist) }
        if !album.isEmpty, album != title { parts.append(album) }
        return parts.joined(separator: " · ")
    }
}
