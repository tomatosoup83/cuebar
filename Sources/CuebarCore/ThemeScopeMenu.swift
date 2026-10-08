import Foundation

/// Builds the rows shown while the `theme` scope is active.
///
/// A scope filter is a *contains* match rather than the prefix matching the command
/// catalog uses, because the options are being narrowed rather than invoked:
/// `theme art` should find "Theme: Album Art".
public enum ThemeScopeMenu {
    public static func entries(
        currentTheme: ThemeID,
        followsSelection: Bool,
        globalColours: Bool = false,
        filter: String = ""
    ) -> [CommandEntry] {
        var all = themeEntries(currentTheme: currentTheme)
        all.append(followEntry(followsSelection: followsSelection))
        // The global-colours option only means something for Album Art v2.
        if currentTheme == .albumArtV2 {
            all.append(globalColoursEntry(globalColours: globalColours))
        }

        let normalized = TextNormalizer.normalize(filter)
        guard !normalized.isEmpty else { return all }
        return all.filter { matches($0, normalizedInput: normalized) }
    }

    // MARK: - Rows

    private static func themeEntries(currentTheme: ThemeID) -> [CommandEntry] {
        ThemeID.allCases.map { theme in
            let isCurrent = theme == currentTheme
            return CommandEntry(
                id: "theme.\(theme.rawValue)",
                title: "Theme: \(theme.title)",
                subtitle: isCurrent ? "Current theme" : theme.blurb,
                symbolName: isCurrent ? "checkmark.circle.fill" : theme.symbolName,
                action: .setTheme(theme),
                keywords: theme.keywords,
                badge: "Theme"
            )
        }
    }

    private static func followEntry(followsSelection: Bool) -> CommandEntry {
        CommandEntry(
            id: "theme.followSelection",
            title: "Follow the Highlighted Row",
            subtitle: followsSelection
                ? "On · the panel takes the cover you're on"
                : "Off · the panel keeps the playing track's colour",
            symbolName: followsSelection ? "checkmark.circle.fill" : "wand.and.stars",
            action: .setFollowsSelection(!followsSelection),
            keywords: ["follow", "follow highlighted row", "highlighted", "selection",
                       "ambient", "option", "toggle"],
            badge: "Option"
        )
    }

    private static func globalColoursEntry(globalColours: Bool) -> CommandEntry {
        CommandEntry(
            id: "theme.globalColours",
            title: "Global Colours",
            subtitle: globalColours
                ? "On · one colour mixed from the whole cover"
                : "Off · keep the cover's vertical gradient",
            symbolName: globalColours ? "checkmark.circle.fill" : "circle.hexagongrid",
            action: .setGlobalColours(!globalColours),
            keywords: ["global", "global colours", "global colors", "gradient",
                       "no gradient", "flat", "pywal", "cluster", "option", "toggle"],
            badge: "Option"
        )
    }

    // MARK: - Matching

    private static func matches(_ entry: CommandEntry, normalizedInput input: String) -> Bool {
        if TextNormalizer.normalize(entry.title).contains(input) { return true }
        return entry.keywords.contains { TextNormalizer.normalize($0).contains(input) }
    }
}
