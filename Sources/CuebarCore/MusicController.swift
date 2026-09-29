import Foundation
import AppKit

/// Playback control for the system Music app.
///
/// `SystemMusicPlayer` is unavailable on macOS, so the concrete implementation
/// drives Music.app through AppleScript instead.
public protocol MusicController: Sendable {
    func play(_ candidate: MusicCandidate) async throws
    /// Plays `tracks` in order as an album queue (Music's shuffle is disabled).
    func playAlbum(_ tracks: [MusicCandidate]) async throws
    /// Plays a library playlist directly, leaving shuffle as-is.
    func playPlaylist(_ playlist: MusicCandidate) async throws
    /// Whether Cuebar may control Music (raises the system prompt on first use).
    func checkAutomationPermission() async -> Bool
    func pause() async throws
    func resume() async throws
    func next() async throws
    func previous() async throws
    func setShuffle(_ enabled: Bool) async throws
    func toggleShuffle() async throws
    /// Whether Music's shuffle is currently enabled.
    func shuffleEnabled() async throws -> Bool
    /// Sets Music's repeat mode (`song repeat`).
    func setRepeat(_ mode: RepeatMode) async throws
    /// The track Music.app currently has loaded, or nil when unavailable.
    func nowPlaying() async throws -> NowPlayingTrack?
}

/// Errors thrown while starting playback.
public enum PlaybackError: Error, LocalizedError, Sendable {
    case notInLibrary(String)
    case emptyAlbum(String)

    public var errorDescription: String? {
        switch self {
        case .notInLibrary(let title):
            return "“\(title)” isn’t in your Music library."
        case .emptyAlbum(let title):
            return "“\(title)” has no playable tracks."
        }
    }
}

/// Controls Music.app via AppleScript.
public final class AppleScriptMusicController: MusicController, @unchecked Sendable {
    private let runner: AppleScriptRunner

    public init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    public func play(_ candidate: MusicCandidate) async throws {
        // Only the user's library can be played reliably: Music's own
        // `open location` merely opens the Apple Music store page, and macOS
        // gives third-party apps no supported way to start catalog playback
        // without a MusicKit entitlement. Callers resolve catalog items to a
        // library track before getting here.
        guard let persistentID = candidate.persistentID, !persistentID.isEmpty else {
            throw PlaybackError.notInLibrary(candidate.title)
        }
        let escaped = Self.escape(persistentID)
        try await runner.run("""
        tell application "Music"
            play (some track of library playlist 1 whose persistent ID is "\(escaped)")
        end tell
        """)
    }

    public func playAlbum(_ tracks: [MusicCandidate]) async throws {
        let ids = tracks.compactMap { candidate -> String? in
            guard let id = candidate.persistentID, !id.isEmpty else { return nil }
            return id
        }
        guard !ids.isEmpty else {
            throw PlaybackError.emptyAlbum(tracks.first?.title ?? "This album")
        }
        try await runner.run(Self.albumQueueScript(trackIDs: ids))
    }

    public func playPlaylist(_ playlist: MusicCandidate) async throws {
        guard let persistentID = playlist.persistentID, !persistentID.isEmpty else {
            throw PlaybackError.notInLibrary(playlist.title)
        }
        let escaped = Self.escape(persistentID)
        try await runner.run("""
        tell application "Music"
            play (first user playlist whose persistent ID is "\(escaped)")
        end tell
        """)
    }

    public func pause() async throws {
        try await runner.run("tell application \"Music\" to pause")
    }

    public func resume() async throws {
        try await runner.run("tell application \"Music\" to play")
    }

    public func next() async throws {
        try await runner.run("tell application \"Music\" to next track")
    }

    public func previous() async throws {
        try await runner.run("tell application \"Music\" to previous track")
    }

    public func setShuffle(_ enabled: Bool) async throws {
        try await runner.run("tell application \"Music\" to set shuffle enabled to \(enabled ? "true" : "false")")
    }

    public func toggleShuffle() async throws {
        try await runner.run("""
        tell application "Music"
            set shuffle enabled to not (shuffle enabled)
        end tell
        """)
    }

    public func shuffleEnabled() async throws -> Bool {
        let raw = try await runner.string("tell application \"Music\" to get shuffle enabled")
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "true" || value == "1"
    }

    public func setRepeat(_ mode: RepeatMode) async throws {
        try await runner.run("tell application \"Music\" to set song repeat to \(mode.rawValue)")
    }

    public func checkAutomationPermission() async -> Bool {
        do {
            _ = try await runner.string("tell application \"Music\" to get version")
            return true
        } catch {
            return Self.permissionGranted(from: error)
        }
    }

    /// Maps an AppleScript failure onto whether Automation access is available.
    static func permissionGranted(from error: Error) -> Bool {
        guard let scriptError = error as? AppleScriptError else { return true }
        return !scriptError.isPermissionDenied
    }

    public func nowPlaying() async throws -> NowPlayingTrack? {        // Never launch Music just by opening the palette.
        guard Self.isMusicRunning else { return nil }
        let raw = try await runner.string(Self.nowPlayingScript)
        return NowPlayingTrack.parse(raw)
    }

    /// Whether Music.app is currently running.
    static var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

    static let nowPlayingScript = #"""
    tell application "Music"
        set sep to (ASCII character 31)
        set theState to (player state as string)
        try
            set t to current track
        on error
            return ""
        end try
        set theID to ""
        try
            set theID to persistent ID of t
        end try
        set thePos to ""
        try
            set thePos to player position as string
        end try
        set theDur to ""
        try
            set theDur to duration of t as string
        end try
        set theShuffle to ""
        try
            set theShuffle to (shuffle enabled as string)
        end try
        set theRepeat to ""
        try
            set theRepeat to (song repeat as string)
        end try
        return theState & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & theID & sep & thePos & sep & theDur & sep & theShuffle & sep & theRepeat
    end tell
    """#

    /// Name of the reusable user playlist used to play an album start to finish.
    public static let albumQueuePlaylistName = "Cuebar Queue"

    /// Builds the AppleScript that loads `trackIDs` into the queue playlist, in
    /// order, disables shuffle and starts playback.
    ///
    /// Music has no album object and no queue command, so an album is played by
    /// duplicating its tracks into a reusable user playlist and playing that.
    static func albumQueueScript(trackIDs: [String]) -> String {
        let idList = trackIDs
            .map { "\"\(escape($0))\"" }
            .joined(separator: ", ")
        return """
        tell application "Music"
            set queueName to "\(escape(Self.albumQueuePlaylistName))"
            if not (exists user playlist queueName) then
                make new user playlist with properties {name:queueName}
            end if
            set q to user playlist queueName
            delete every track of q
            set shuffle enabled to false
            repeat with pid in {\(idList)}
                duplicate (first track of library playlist 1 whose persistent ID is pid) to q
            end repeat
            play q
        end tell
        """
    }

    /// Escapes a value for embedding in an AppleScript string literal.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
