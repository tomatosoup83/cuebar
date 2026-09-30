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

    init(center: ToastCenter) {
        self.center = center

        let rect = NSRect(x: 0, y: 0, width: 360, height: 48)
        panel = ToastPanel(contentRect: rect)
        hostingView = NSHostingView(rootView: ToastView(toast: Toast(kind: .success, message: " ")))
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
        hostingView.rootView = ToastView(toast: toast, theme: style.theme, palette: style.palette)

        let size = hostingView.fittingSize
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }

        announce(toast)
    }

    private func hide() {
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
