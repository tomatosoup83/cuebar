import AppKit

/// Layout constants shared between the AppKit window and the SwiftUI content so
/// the two can never drift (in particular the corner radius).
enum PaletteMetrics {
    static let cornerRadius: CGFloat = 24
    static let panelSize = NSSize(width: 660, height: 420)

    // Toast
    static let toastCornerRadius: CGFloat = 16
    /// Room around the toast inside the panel for its soft shadow.
    static let toastShadowInset: CGFloat = 22
    /// The tallest a toast can get (a two-line message plus a two-line detail).
    static let toastMaxHeight: CGFloat = 96
    /// The toast panel is a fixed transparent canvas — the toast changes size
    /// *inside* it, so the window itself never resizes (which is what made the
    /// old message visible for a frame at the new width).
    static let toastCanvasSize = NSSize(
        width: toastMaxWidth + toastShadowInset * 2,
        height: toastMaxHeight + toastShadowInset * 2
    )
    static let toastMaxWidth: CGFloat = 420
    static let toastGap: CGFloat = 12

    // Now-playing card
    static let nowPlayingArtwork: CGFloat = 58
    static let nowPlayingProgressHeight: CGFloat = 4
}
