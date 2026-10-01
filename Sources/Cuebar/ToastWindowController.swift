import AppKit
import SwiftUI
import Combine
import CuebarCore

/// Owns the toast panel and shows/hides it as `ToastCenter.current` changes.
@MainActor
final class ToastWindowController {
    private let center: ToastCenter
    private let panel: ToastPanel
    private let hostingView: NSHostingView<ToastView>
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

        let rect = NSRect(x: 0, y: 0, width: 360, height: 48)
        panel = ToastPanel(contentRect: rect)
        hostingView = NSHostingView(rootView: ToastView(toast: Toast(kind: .success, message: " ")))
        hostingView.frame = rect
        hostingView.autoresizingMask = [.width, .height]
        // The panel is square; the content carries the rounded shape. Round the
        // host as well, so a resize can never flash a square corner.
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = PaletteMetrics.toastCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
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
        let view = ToastView(toast: toast, theme: style.theme, palette: style.palette)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Work out how big the new toast wants to be *before* it can be seen,
        // then lay it out at that size. The window is therefore already at its
        // final size when it appears, and never grows where the user can see it.
        hostingView.rootView = view
        let size = measuredSize(of: view)
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        hostingView.layoutSubtreeIfNeeded()

        if reduceMotion {
            isPresented = true
            hostingView.alphaValue = 1
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.invalidateShadow()
            announce(toast)
            return
        }

        if isPresented, panel.isVisible {
            // Already showing: the new toast is laid out at its final size, so the
            // swap is instant and no resize is ever visible. Only the text and
            // width change, in one frame.
            hostingView.alphaValue = 1
            panel.alphaValue = 1
            panel.invalidateShadow()
            debugCheckSizeStable(presented: size)
            announce(toast)
            return
        }

        isPresented = true
        hostingView.alphaValue = 1
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        debugCheckSizeStable(presented: size)
    }

#if DEBUG
    /// Logs whether the panel changed size after the toast was presented, which
    /// is exactly the resize the user shouldn't be able to see.
    private func debugCheckSizeStable(presented: NSSize) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let now = self.panel.frame.size
            NSLog("Cuebar: toast size presented=\(presented.width)x\(presented.height) "
                  + "later=\(now.width)x\(now.height) stable=\(now == presented)")
        }
    }
#endif

    /// The size the toast wants, measured on a detached host so it never depends
    /// on (or disturbs) the panel's current frame.
    private func measuredSize(of view: ToastView) -> NSSize {
        NSHostingView(rootView: view).fittingSize
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

    /// Below the palette when there is room, otherwise above it; top-centre when
    /// there is no palette, always clamped to the screen.
    private func origin(for size: NSSize) -> NSPoint {
        let screen = anchorFrame
            .flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return .zero }

        let gap = PaletteMetrics.toastGap
        var x: CGFloat
        var y: CGFloat

        if let anchor = anchorFrame {
            x = anchor.midX - size.width / 2
            let below = anchor.minY - gap - size.height
            y = below >= visible.minY ? below : anchor.maxY + gap
        } else {
            x = visible.midX - size.width / 2
            y = visible.maxY - gap - size.height
        }

        x = min(max(x, visible.minX + gap), visible.maxX - size.width - gap)
        y = min(max(y, visible.minY + gap), visible.maxY - size.height - gap)
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
