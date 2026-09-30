import Foundation

/// A single row in the palette: the current track, a runnable command, or a
/// music item.
public enum PaletteItem: Identifiable, Equatable, Sendable {
    case nowPlaying(NowPlayingTrack)
    case command(CommandEntry)
    case music(MusicCandidate)

    public var id: String {
        switch self {
        case .nowPlaying:
            return "nowPlaying"
        case .command(let entry):
            return "command:\(entry.id)"
        case .music(let candidate):
            return "music:\(candidate.id)"
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
/// - Empty query: the current track (if any) followed by every command.
/// - Non-empty query: command matches followed by song results, never the
///   now-playing row.
public enum PaletteListComposer {
    public static func compose(
        query: String,
        nowPlaying: NowPlayingTrack?,
        commands: [CommandEntry],
        music: [MusicCandidate]
    ) -> [PaletteItem] {
        var items: [PaletteItem] = []

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let nowPlaying {
            items.append(.nowPlaying(nowPlaying))
        }

        items.append(contentsOf: commands.map(PaletteItem.command))
        items.append(contentsOf: music.map(PaletteItem.music))
        return items
    }
}
