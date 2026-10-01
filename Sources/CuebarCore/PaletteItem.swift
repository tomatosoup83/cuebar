import Foundation

/// A single row in the palette: the current track, a runnable command, a
/// music item, or a recently played track on the home screen.
public enum PaletteItem: Identifiable, Equatable, Sendable {
    case nowPlaying(NowPlayingTrack)
    case command(CommandEntry)
    case music(MusicCandidate)
    case recent(RecentTrack)

    public var id: String {
        switch self {
        case .nowPlaying:
            return "nowPlaying"
        case .command(let entry):
            return "command:\(entry.id)"
        case .music(let candidate):
            return "music:\(candidate.id)"
        case .recent(let track):
            return "recent:\(track.id)"
        }
    }

    /// The artwork this row shows, if any. Commands have none.
    ///
    /// Single source of truth: both the row icon and the Album Art theme read
    /// this, so they can never disagree about which cover a row belongs to.
    public var artworkSource: ArtworkSource? {
        switch self {
        case .nowPlaying(let track):
            return .nowPlaying(
                persistentID: track.persistentID,
                artist: track.artist,
                album: track.album,
                title: track.title
            )

        case .command:
            return nil

        case .recent(let track):
            return PaletteItem.music(track.candidate).artworkSource

        case .music(let candidate):
            switch candidate.source {
            case .library:
                // A playlist's `persistentID` is the playlist itself, not a
                // track, so use its representative track for artwork.
                let trackID = candidate.kind == .playlist
                    ? candidate.artworkTrackID
                    : (candidate.persistentID ?? candidate.artworkTrackID)
                guard let trackID else { return nil }
                return .library(
                    persistentID: trackID,
                    artist: candidate.artist,
                    album: candidate.album
                )
            case .catalog:
                guard let url = candidate.artworkURL else { return nil }
                return .remote(url)
            }
        }
    }
}

/// Builds the displayed list.
///
/// - Empty query: the current track (if any), then the given commands, then the
///   recently played shelf (the home screen).
/// - Non-empty query: command matches followed by song results, never the
///   now-playing row or the recent shelf.
public enum PaletteListComposer {
    public static func compose(
        query: String,
        nowPlaying: NowPlayingTrack?,
        commands: [CommandEntry],
        music: [MusicCandidate],
        recent: [RecentTrack] = []
    ) -> [PaletteItem] {
        var items: [PaletteItem] = []
        let isEmptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isEmptyQuery, let nowPlaying {
            items.append(.nowPlaying(nowPlaying))
        }

        items.append(contentsOf: commands.map(PaletteItem.command))
        items.append(contentsOf: music.map(PaletteItem.music))

        if isEmptyQuery {
            items.append(contentsOf: recent.map(PaletteItem.recent))
        }
        return items
    }

    /// The commands the home screen keeps once it has a recent shelf.
    ///
    /// The transport commands duplicate the now-playing card's controls, so
    /// they give way to the shelf; anything time-sensitive (an available update)
    /// stays. With no shelf, every command shows, as before.
    public static func homeCommands(
        _ commands: [CommandEntry],
        hasRecent: Bool
    ) -> [CommandEntry] {
        guard hasRecent else { return commands }
        return commands.filter { $0.action == .installUpdate }
    }
}
