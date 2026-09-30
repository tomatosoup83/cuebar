import Foundation

/// A row on the Settings screen, in display order.
public enum SettingsRow: String, CaseIterable, Sendable {
    case hotKey
    case theme
    case followSelection
    case update
    case whatsNew
    case onboarding

    /// The rows shown for the given state, in order.
    ///
    /// The ambient option only means something for the Album Art theme, so it is
    /// absent under Tahoe. Keeping the list here — rather than an index the view
    /// has to clamp itself — means the selection can never dangle.
    public static func visibleRows(theme: ThemeID) -> [SettingsRow] {
        var rows: [SettingsRow] = [.hotKey, .theme]
        if theme == .albumArt { rows.append(.followSelection) }
        rows.append(contentsOf: [.update, .whatsNew, .onboarding])
        return rows
    }
}
