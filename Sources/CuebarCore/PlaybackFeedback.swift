import Foundation

/// Builds the user-facing toast copy for playback outcomes.
///
/// Kept pure and centralized so the wording is consistent and unit-testable;
/// the shell only has to render whatever `Toast` it is handed.
public enum PlaybackFeedback {
    // MARK: - Success

    public static func playing(_ candidate: MusicCandidate) -> Toast {
        let detail = candidate.artist.isEmpty ? candidate.album : candidate.artist
        return Toast(
            kind: .success,
            message: "Playing “\(candidate.title)”",
            detail: detail.isEmpty ? nil : detail
        )
    }

    public static func playingAlbum(_ album: MusicCandidate, trackCount: Int) -> Toast {
        let count = "\(trackCount) track\(trackCount == 1 ? "" : "s")"
        let detail = album.artist.isEmpty ? count : "\(album.artist) · \(count)"
        return Toast(kind: .success, message: "Playing album “\(album.title)”", detail: detail)
    }

    public static func playingPlaylist(_ playlist: MusicCandidate, trackCount: Int) -> Toast {
        let count = "\(trackCount) track\(trackCount == 1 ? "" : "s")"
        return Toast(kind: .success, message: "Playing playlist “\(playlist.title)”", detail: count)
    }

    // MARK: - Library index

    public static func rebuildingIndex() -> Toast {
        Toast(kind: .info, message: "Rebuilding library index…")
    }

    public static func indexRebuilt(_ summary: LibraryIndexSummary) -> Toast {
        let tracks = "\(summary.trackCount) track\(summary.trackCount == 1 ? "" : "s")"
        let playlists = "\(summary.playlistCount) playlist\(summary.playlistCount == 1 ? "" : "s")"
        return Toast(kind: .success, message: "Library indexed", detail: "\(tracks) · \(playlists)")
    }

    public static func indexRebuildFailed() -> Toast {
        Toast(kind: .error, message: "Couldn’t rebuild the library index")
    }

    public static func paused() -> Toast {
        Toast(kind: .success, message: "Paused")
    }

    public static func resumed() -> Toast {
        Toast(kind: .success, message: "Resumed")
    }

    public static func nextTrack() -> Toast {
        Toast(kind: .success, message: "Next track")
    }

    public static func previousTrack() -> Toast {
        Toast(kind: .success, message: "Previous track")
    }

    public static func shuffle(_ enabled: Bool) -> Toast {
        Toast(kind: .success, message: enabled ? "Shuffle on" : "Shuffle off")
    }

    /// Used when the resulting shuffle state couldn't be read back.
    public static func shuffleToggled() -> Toast {
        Toast(kind: .success, message: "Shuffle toggled")
    }

    public static func repeatMode(_ mode: RepeatMode) -> Toast {
        switch mode {
        case .off: return Toast(kind: .success, message: "Repeat off")
        case .all: return Toast(kind: .success, message: "Repeat queue")
        case .one: return Toast(kind: .success, message: "Repeat track")
        }
    }

    // MARK: - Errors

    public static func notInLibrary(_ title: String) -> Toast {
        Toast(
            kind: .error,
            message: "“\(title)” isn’t in your Music library",
            detail: "Add it in Music to play it."
        )
    }

    public static func emptyAlbum(_ title: String) -> Toast {
        Toast(kind: .error, message: "“\(title)” has no playable tracks")
    }

    public static func failure(_ error: Error) -> Toast {
        // Permission problems need a moment longer to read the guidance.
        let isPermission = (error as? AppleScriptError)?.isPermissionDenied ?? false
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        return Toast(
            kind: .error,
            message: message,
            duration: isPermission ? 6.0 : nil
        )
    }
}
