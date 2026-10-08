import Foundation

/// A row on the Settings screen, in display order.
public enum SettingsRow: String, CaseIterable, Sendable {
    case hotKey
    case theme
    case followSelection
    case globalColours
    case update
    case whatsNew
    case onboarding

    /// The rows shown for the given state, in order.
    ///
    /// The ambient option only means something for the Album Art themes, and the
    /// global-colours option only for Album Art v2, so they are absent
    /// otherwise. Keeping the list here — rather than an index the view has to
    /// clamp itself — means the selection can never dangle.
    public static func visibleRows(theme: ThemeID) -> [SettingsRow] {
        var rows: [SettingsRow] = [.hotKey, .theme]
        if theme.isAlbumArt { rows.append(.followSelection) }
        if theme == .albumArtV2 { rows.append(.globalColours) }
        rows.append(contentsOf: [.update, .whatsNew, .onboarding])
        return rows
    }
}
