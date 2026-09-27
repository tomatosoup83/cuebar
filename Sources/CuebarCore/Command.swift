import Foundation

/// How the `shuffle` command should change shuffle mode.
public enum ShuffleAction: Equatable, Sendable {
    case toggle
    case on
    case off
}

/// A parsed palette command.
public enum Command: Equatable, Sendable {
    case play(query: String)
    case pause
    case resume
    case next
    case previous
    case shuffle(ShuffleAction)
}

/// Turns raw palette input into a `Command`.
///
/// Recognized verbs are `play`, `pause`, `resume`, `next`, `previous`, `shuffle`.
/// Anything else is treated as a bare song name, i.e. an implicit `play`.
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
            return .pause
        case "resume":
            return .resume
        case "next", "skip", "forward":
            return .next
        case "previous", "prev", "back":
            return .previous
        case "shuffle":
            switch rest.lowercased() {
            case "", "toggle": return .shuffle(.toggle)
            case "on", "yes", "true": return .shuffle(.on)
            case "off", "no", "false": return .shuffle(.off)
            default: return .shuffle(.toggle)
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
