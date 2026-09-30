import Foundation

/// Whether a palette row may carry the album-art colour tint.
public enum RowTintPolicy {
    /// True when `item` is allowed to be tinted with its cover's colour while it
    /// is the selected row.
    ///
    /// The now-playing row always may — it is the hero of the default screen.
    /// When the user opts into "follow the highlighted row" any row may, so the
    /// highlighted row matches the ambient background.
    public static func allowsTint(for item: PaletteItem, followsSelection: Bool) -> Bool {
        if case .nowPlaying = item { return true }
        return followsSelection
    }
}
