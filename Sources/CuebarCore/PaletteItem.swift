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
