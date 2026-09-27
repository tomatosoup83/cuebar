import Foundation

/// The track the Music app currently has loaded, and its playback state.
public struct NowPlayingTrack: Equatable, Sendable {
    public enum State: String, Sendable {
        case playing
        case paused
        case stopped
    }

    public let state: State
    public let title: String
    public let artist: String
    public let album: String
    public let persistentID: String?
    public let position: Double?
    public let duration: Double?

    public init(
        state: State,
        title: String,
        artist: String,
        album: String,
        persistentID: String? = nil,
        position: Double? = nil,
        duration: Double? = nil
    ) {
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.persistentID = persistentID
        self.position = position
        self.duration = duration
    }

    public var isPlaying: Bool { state == .playing }

    public var subtitle: String {
        var parts: [String] = []
        if !artist.isEmpty { parts.append(artist) }
        if !album.isEmpty, album != title { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    /// Unit separator used by the now-playing AppleScript.
    public static let fieldSeparator = "\u{1f}"

    /// Decodes the script output. Returns nil when nothing is loaded.
    ///
    /// Expected: `state <FS> title <FS> artist <FS> album <FS> id <FS> position <FS> duration`
    public static func parse(_ raw: String) -> NowPlayingTrack? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = raw.components(separatedBy: fieldSeparator)
        // Need at least the state and a title.
        guard fields.count >= 2 else { return nil }

        let state = State(rawValue: value(fields, 0)) ?? .stopped
        let title = value(fields, 1)
        guard !title.isEmpty else { return nil }

        let persistentID = value(fields, 4)

        return NowPlayingTrack(
            state: state,
            title: title,
            artist: value(fields, 2),
            album: value(fields, 3),
            persistentID: persistentID.isEmpty ? nil : persistentID,
            position: Double(value(fields, 5)),
            duration: Double(value(fields, 6))
        )
    }

    private static func value(_ fields: [String], _ index: Int) -> String {
        guard index < fields.count else { return "" }
        let raw = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == "missing value" ? "" : raw
    }
}
