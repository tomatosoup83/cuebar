import AppKit

/// Layout constants shared between the AppKit window and the SwiftUI content so
/// the two can never drift (in particular the corner radius).
enum PaletteMetrics {
    static let cornerRadius: CGFloat = 24
    static let panelSize = NSSize(width: 660, height: 420)
}
