import AppKit

/// A borderless, click-through floating panel that shows a toast.
///
/// Styled like `PalettePanel` but it never takes key/main and ignores mouse
/// events, so it can never steal focus or intercept clicks.
final class ToastPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // The window is a fixed transparent canvas bigger than the toast, so a
        // window shadow would draw a rectangle. The toast draws its own shadow.
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        // No animated resizes: a toast must appear at its final size instantly,
        // never be seen growing (and never scale the old backing store, which
        // smears the previous message across the new one).
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
