import Foundation
import AppKit

/// Playback control for the system Music app.
///
/// `SystemMusicPlayer` is unavailable on macOS, so the concrete implementation
/// drives Music.app through AppleScript instead.
public protocol MusicController: Sendable {
    func play(_ candidate: MusicCandidate) async throws
    func pause() async throws
    func resume() async throws
    func next() async throws
    func previous() async throws
    func setShuffle(_ enabled: Bool) async throws
    func toggleShuffle() async throws
    /// The track Music.app currently has loaded, or nil when unavailable.
    func nowPlaying() async throws -> NowPlayingTrack?
}

/// Controls Music.app via AppleScript.
public final class AppleScriptMusicController: MusicController, @unchecked Sendable {
    private let runner: AppleScriptRunner

    public init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    public func play(_ candidate: MusicCandidate) async throws {
        if candidate.source == .library, let persistentID = candidate.persistentID, !persistentID.isEmpty {
            let escaped = Self.escape(persistentID)
            try await runner.run("""
            tell application "Music"
                play (some track of library playlist 1 whose persistent ID is "\(escaped)")
            end tell
            """)
            return
        }

        if let url = candidate.playbackURL {
            let escaped = Self.escape(url.absoluteString)
            try await runner.run("tell application \"Music\" to open location \"\(escaped)\"")
            return
        }

        throw AppleScriptError(code: -1, message: "This result has nothing to play.")
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

    public func nowPlaying() async throws -> NowPlayingTrack? {
        // Never launch Music just by opening the palette.
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
        return theState & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & theID & sep & thePos & sep & theDur
    end tell
    """#

    /// Escapes a value for embedding in an AppleScript string literal.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
