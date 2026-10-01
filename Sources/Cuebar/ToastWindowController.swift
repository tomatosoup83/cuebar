import AppKit
import SwiftUI
import Combine
import CuebarCore

/// Owns the toast panel and shows/hides it as `ToastCenter.current` changes.
///
/// The panel is a **fixed-size transparent canvas**; the toast changes size
/// inside it. That way the window never resizes, so a longer or shorter message
/// can never be seen at the previous one's size — the transition is just a
/// content update, and it happens in a single frame.
@MainActor
final class ToastWindowController {
    private let center: ToastCenter
    private let panel: ToastPanel
    private let hostingView: NSHostingView<ToastCanvas>
    private let presentation = ToastPresentation()
    private var cancellables = Set<AnyCancellable>()

    /// Supplies the current theme + ambient palette so toasts match the panel.
    var themeProvider: (@MainActor () -> (theme: ThemeID, palette: AlbumPalette?))?

    /// The palette frame to anchor below, captured when the toast is requested.
    private var anchorFrame: NSRect?
    /// True while a toast is meant to be on screen; the alpha fade runs around
    /// it, so presentation never depends on an in-flight animation.
    private var isPresented = false

    init(center: ToastCenter) {
        self.center = center

        let rect = NSRect(origin: .zero, size: PaletteMetrics.toastCanvasSize)
        panel = ToastPanel(contentRect: rect)
        hostingView = NSHostingView(rootView: ToastCanvas(presentation: presentation))
        hostingView.frame = rect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        center.$current
            .sink { [weak self] toast in
                guard let self else { return }
                if let toast {
                    self.present(toast)
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }

    /// Requests a toast, anchoring it to `frame` (the palette) when available.
    func show(_ toast: Toast, anchoredTo frame: NSRect?) {
        anchorFrame = frame
        center.show(toast)
    }

    // MARK: - Panel

    private func present(_ toast: Toast) {
        let style = themeProvider?() ?? (.tahoe, nil)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let place = placement()

        // Update the (stable) content and reposition the fixed-size panel.
        // Nothing here resizes the window, so the toast can grow or shrink
        // freely, and the transaction forbids an implicit fade between messages.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        presentation.toast = toast
        presentation.theme = style.theme
        presentation.palette = style.palette
        presentation.verticalAlignment = place.below ? .top : .bottom
        presentation.width = huggingWidth(of: toast, style: style)
        panel.setFrameOrigin(origin(for: place))
        CATransaction.commit()
        hostingView.layoutSubtreeIfNeeded()

        if reduceMotion {
            isPresented = true
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            announce(toast)
            return
        }

        if isPresented, panel.isVisible {
            // Already showing: the new toast simply replaces the old one.
            panel.alphaValue = 1
            announce(toast)
            return
        }

        isPresented = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        announce(toast)
    }

    /// The width the toast wants to hug, capped at `toastMaxWidth`.
    private func huggingWidth(of toast: Toast, style: (theme: ThemeID, palette: AlbumPalette?)) -> CGFloat {
        let natural = NSHostingView(
            rootView: ToastView(toast: toast, theme: style.theme, palette: style.palette)
        ).fittingSize.width
        return min(natural, PaletteMetrics.toastMaxWidth)
    }

    private func hide() {
        isPresented = false
        guard panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
            }
        }
    }

    // MARK: - Placement

    /// Where the toast goes relative to the palette.
    private struct Placement {
        let visible: NSRect
        let anchor: NSRect?
        /// Below the palette (top-aligned in the canvas) or above it (bottom).
        let below: Bool
    }

    private func placement() -> Placement {
        let screen = anchorFrame
            .flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero

        // Decide with the tallest a toast can get, so the choice can't depend on
        // the message being shown.
        let below: Bool
        if let anchor = anchorFrame {
            let room = anchor.minY - PaletteMetrics.toastGap
            below = (room - PaletteMetrics.toastMaxHeight)
                >= visible.minY + PaletteMetrics.toastShadowInset
        } else {
            below = true
        }
        return Placement(visible: visible, anchor: anchorFrame, below: below)
    }

    /// Positions the fixed canvas so the edge of the toast nearest the palette
    /// lands the gap away from it. The toast's own height never matters: it hugs
    /// the canvas edge that is being placed.
    private func origin(for place: Placement) -> NSPoint {
        let gap = PaletteMetrics.toastGap
        let inset = PaletteMetrics.toastShadowInset
        let canvas = PaletteMetrics.toastCanvasSize

        var x: CGFloat
        var y: CGFloat

        if let anchor = place.anchor {
            x = anchor.midX - canvas.width / 2
            if place.below {
                // Toast top sits `inset` below the canvas top.
                let toastTop = anchor.minY - gap
                y = toastTop + inset - canvas.height
            } else {
                // Toast bottom sits `inset` above the canvas bottom.
                y = anchor.maxY + gap - inset
            }
        } else {
            // Top-centre of the screen.
            x = place.visible.midX - canvas.width / 2
            let toastTop = place.visible.maxY - gap
            y = toastTop + inset - canvas.height
        }

        x = min(max(x, place.visible.minX - inset), place.visible.maxX - canvas.width + inset)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    private func announce(_ toast: Toast) {
        let text = [toast.message, toast.detail]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
