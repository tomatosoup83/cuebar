import Foundation

/// Reads album artwork straight from Music.app through AppleScript.
///
/// Music exposes `raw data of artwork 1 of <track>` for any item it has art
/// for, so this works offline for library tracks and the currently playing
/// track alike.
public final class AppleScriptArtworkProvider: ArtworkDataProviding, @unchecked Sendable {
    private let runner: AppleScriptRunner

    public init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    public func artworkData(for persistentID: String?) async throws -> Data? {
        // Never launch Music just to look up artwork.
        guard AppleScriptMusicController.isMusicRunning else { return nil }

        let script: String
        if let persistentID, !persistentID.isEmpty {
            let escaped = AppleScriptMusicController.escape(persistentID)
            script = """
            tell application "Music"
                try
                    set t to (some track of library playlist 1 whose persistent ID is "\(escaped)")
                on error
                    return ""
                end try
                try
                    return (raw data of artwork 1 of t)
                on error
                    return ""
                end try
            end tell
            """
        } else {
            script = """
            tell application "Music"
                try
                    return (raw data of artwork 1 of current track)
                on error
                    return ""
                end try
            end tell
            """
        }

        let data = try await runner.data(script)
        return data.isEmpty ? nil : data
    }
}
