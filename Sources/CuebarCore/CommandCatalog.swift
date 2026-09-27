import Foundation

/// What running a palette row actually does.
public enum PaletteAction: Equatable, Sendable {
    /// A music transport command.
    case music(Command)
    /// Open the embedded settings screen.
    case openSettings
}

/// A user-facing row that is not a song: a command or an app action.
public struct CommandEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbolName: String
    public let action: PaletteAction
    /// Words the user can type (or partially type) to surface this entry.
    public let keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        action: PaletteAction,
        keywords: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.action = action
        self.keywords = keywords
    }
}

/// The set of commands the palette can run, and the matching used to surface
/// them as results while the user types.
public enum CommandCatalog {
    public static let all: [CommandEntry] = [
        CommandEntry(
            id: "pause",
            title: "Pause",
            subtitle: "Pause playback",
            symbolName: "pause.fill",
            action: .music(.pause),
            keywords: ["pause"]
        ),
        CommandEntry(
            id: "resume",
            title: "Play / Resume",
            subtitle: "Resume playback",
            symbolName: "play.fill",
            action: .music(.resume),
            keywords: ["resume", "play"]
        ),
        CommandEntry(
            id: "next",
            title: "Next Track",
            subtitle: "Skip to the next track",
            symbolName: "forward.fill",
            action: .music(.next),
            keywords: ["next", "skip", "forward"]
        ),
        CommandEntry(
            id: "previous",
            title: "Previous Track",
            subtitle: "Go back to the previous track",
            symbolName: "backward.fill",
            action: .music(.previous),
            keywords: ["previous", "prev", "back"]
        ),
        CommandEntry(
            id: "shuffle.toggle",
            title: "Toggle Shuffle",
            subtitle: "Turn shuffle on or off",
            symbolName: "shuffle",
            action: .music(.shuffle(.toggle)),
            keywords: ["shuffle"]
        ),
        CommandEntry(
            id: "shuffle.on",
            title: "Shuffle On",
            subtitle: "Enable shuffle",
            symbolName: "shuffle",
            action: .music(.shuffle(.on)),
            keywords: ["shuffle on"]
        ),
        CommandEntry(
            id: "shuffle.off",
            title: "Shuffle Off",
            subtitle: "Disable shuffle",
            symbolName: "shuffle",
            action: .music(.shuffle(.off)),
            keywords: ["shuffle off"]
        ),
        CommandEntry(
            id: "settings",
            title: "Settings",
            subtitle: "Change Cuebar's launch hotkey",
            symbolName: "gearshape",
            action: .openSettings,
            keywords: ["settings", "preferences", "hotkey", "shortcut"]
        )
    ]

    /// Ranked command matches for the typed input.
    ///
    /// Matching is directional: the input must be a prefix *of* a keyword, so
    /// "play take on me" does not match the "play" keyword and stays a song
    /// search. An empty input returns every entry.
    public static func matches(for input: String, limit: Int = 20) -> [CommandEntry] {
        let normalized = TextNormalizer.normalize(input)
        guard !normalized.isEmpty else {
            return Array(all.prefix(limit))
        }

        let scored: [(entry: CommandEntry, score: Double)] = all.compactMap { entry in
            guard let score = score(entry, normalizedInput: normalized) else { return nil }
            return (entry, score)
        }

        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.title < rhs.entry.title
        }
        return sorted.prefix(limit).map(\.entry)
    }

    /// Best keyword score for an entry, or nil when nothing matches.
    public static func score(_ entry: CommandEntry, normalizedInput input: String) -> Double? {
        var best: Double?

        for keyword in entry.keywords {
            let normalizedKeyword = TextNormalizer.normalize(keyword)
            guard !normalizedKeyword.isEmpty else { continue }

            var candidate: Double?
            if normalizedKeyword == input {
                candidate = 1000
            } else if normalizedKeyword.hasPrefix(input) {
                // Prefer keywords closest to what was typed, so "shuf" surfaces
                // "Toggle Shuffle" before "Shuffle Off".
                let extra = normalizedKeyword.count - input.count
                candidate = 850 - Double(extra) * 5
            } else if !input.contains(" ") {
                // Fuzzy only for single-word typing, to avoid noise.
                let ratio = Similarity.ratio(input, normalizedKeyword)
                if ratio >= 0.60 {
                    candidate = (ratio * 500).rounded()
                }
            }

            if let candidate, candidate > (best ?? 0) {
                best = candidate
            }
        }

        return best
    }
}
