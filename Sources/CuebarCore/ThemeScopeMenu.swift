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
        filter: String = ""
    ) -> [CommandEntry] {
        let all = themeEntries(currentTheme: currentTheme)
            + [followEntry(followsSelection: followsSelection)]

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

    // MARK: - Matching

    private static func matches(_ entry: CommandEntry, normalizedInput input: String) -> Bool {
        if TextNormalizer.normalize(entry.title).contains(input) { return true }
        return entry.keywords.contains { TextNormalizer.normalize($0).contains(input) }
    }
}
