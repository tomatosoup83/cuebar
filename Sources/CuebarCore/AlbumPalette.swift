import Foundation

/// A legible, light palette derived from album artwork.
///
/// The colours are already washed toward a light neutral, so views can use them
/// directly as a background without further contrast work.
public struct AlbumPalette: Equatable, Sendable {
    /// Gradient stop for the top of the panel.
    public let top: ThemeColor
    /// Gradient stop for the bottom of the panel.
    public let bottom: ThemeColor
    /// A stronger colour used for the selected row's accent.
    public let accent: ThemeColor
    /// The selected row's fill: the signature colour, darkened and saturated so a
    /// contrasting foreground always reads on it and it stands out from the wash.
    public let selection: ThemeColor
    /// False when the artwork had essentially no colour (grey / black / white),
    /// in which case the panel falls back to its neutral look.
    public let isUsable: Bool

    public init(
        top: ThemeColor,
        bottom: ThemeColor,
        accent: ThemeColor,
        selection: ThemeColor,
        isUsable: Bool = true
    ) {
        self.top = top
        self.bottom = bottom
        self.accent = accent
        self.selection = selection
        self.isUsable = isUsable
    }
}
