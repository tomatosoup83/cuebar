import Foundation

/// How the `shuffle` command should change shuffle mode.
public enum ShuffleAction: Equatable, Sendable {
    case toggle
    case on
    case off
}

/// Music's playback repeat mode (`song repeat`).
public enum RepeatMode: String, Equatable, Sendable {
    case off
    case all
    case one
}

public extension RepeatMode {
    /// The result of tapping a repeat-all toggle: off ↔ all (repeat-one turns
    /// off, since the button only toggles all).
    var togglingAll: RepeatMode { self == .off ? .all : .off }
}

/// A parsed palette command.
public enum Command: Equatable, Sendable {
    case play(query: String)
    case pause
    case resume
    case next
    case previous
    case shuffle(ShuffleAction)
    case setRepeat(RepeatMode)
}

/// Turns raw palette input into a `Command`.
///
/// Recognized verbs are `play`, `pause`, `resume`, `next`, `previous`,
/// `shuffle` and `repeat`. Anything else is treated as a bare song name, i.e.
/// an implicit `play`.
///
/// A verb only stands alone: once it is followed by other words it is a song
/// search, so "back to you" plays the song, not the previous-track command.
public enum CommandParser {
    public static func parse(_ input: String) -> Command? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .map(String.init)
        let head = parts[0].lowercased()
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch head {
        case "play":
            // Bare "play" behaves like "resume"; "play <song>" searches.
            return rest.isEmpty ? .resume : .play(query: rest)
        case "pause":
            return rest.isEmpty ? .pause : .play(query: trimmed)
        case "resume":
            return rest.isEmpty ? .resume : .play(query: trimmed)
        case "next", "skip", "forward":
            return rest.isEmpty ? .next : .play(query: trimmed)
        case "previous", "prev", "back":
            return rest.isEmpty ? .previous : .play(query: trimmed)
        case "shuffle":
            switch rest.lowercased() {
            case "", "toggle": return .shuffle(.toggle)
            case "on", "yes", "true": return .shuffle(.on)
            case "off", "no", "false": return .shuffle(.off)
            default: return .play(query: trimmed)
            }
        case "repeat":
            switch rest.lowercased() {
            case "queue", "all", "playlist": return .setRepeat(.all)
            case "track", "song", "one": return .setRepeat(.one)
            case "off", "none": return .setRepeat(.off)
            default: return rest.isEmpty ? nil : .play(query: trimmed)
            }
        default:
            return .play(query: trimmed)
        }
    }

    /// The search term for a `play` command, or nil for non-search commands.
    public static func searchTerm(for command: Command?) -> String? {
        guard case .play(let query) = command else { return nil }
        return query
    }
}
