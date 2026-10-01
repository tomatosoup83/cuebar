import SwiftUI
import CuebarCore

/// The toast content: an icon, a message and optional detail, on Liquid Glass.
struct ToastView: View {
    let toast: Toast
    /// The active theme, so a toast matches the panel behind it.
    var theme: ThemeID = .tahoe
    var palette: AlbumPalette?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // No trailing spacer: the toast should hug a short message and only
        // grow to `toastMaxWidth` for a long one.
        .frame(maxWidth: PaletteMetrics.toastMaxWidth, alignment: .leading)
        .glassEffect(
            ThemeGlass.style(theme: theme, palette: palette, followsSelection: false),
            in: RoundedRectangle(cornerRadius: PaletteMetrics.toastCornerRadius, style: .continuous)
        )
        .background {
            ThemeBackground(theme: theme, palette: palette)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: PaletteMetrics.toastCornerRadius, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.4), value: palette)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "arrow.clockwise"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .success: return .green
        case .error: return .orange
        case .info: return .accentColor
        }
    }

    private var accessibilityText: String {
        if let detail = toast.detail, !detail.isEmpty {
            return "\(toast.message). \(detail)"
        }
        return toast.message
    }
}

/// What the toast panel is showing. The panel's root view observes this rather
/// than being replaced, so a new message updates the existing view in place —
/// replacing the root view makes AppKit cross-dissolve old and new.
@MainActor
final class ToastPresentation: ObservableObject {
    @Published var toast: Toast
    @Published var theme: ThemeID
    @Published var palette: AlbumPalette?
    @Published var verticalAlignment: VerticalAlignment
    /// The width the toast hugs (measured from its text, capped at
    /// `toastMaxWidth`). The canvas is fixed, so the toast is pinned to this
    /// inside it rather than being allowed to fill the canvas.
    @Published var width: CGFloat

    init(
        toast: Toast = Toast(kind: .success, message: " "),
        theme: ThemeID = .tahoe,
        palette: AlbumPalette? = nil,
        verticalAlignment: VerticalAlignment = .top,
        width: CGFloat = PaletteMetrics.toastMaxWidth
    ) {
        self.toast = toast
        self.theme = theme
        self.palette = palette
        self.verticalAlignment = verticalAlignment
        self.width = width
    }
}

/// The toast inside the panel's fixed canvas.
///
/// The panel is always `ToastCanvas`-sized; only the toast within it grows or
/// shrinks. Because the window never resizes, a new message can never be seen at
/// the previous one's size. The toast draws its own shadow here, since a fixed
/// transparent canvas can't use the window's shadow.
///
/// The toast hugs one edge of the canvas (top when it sits below the palette,
/// bottom when it sits above it), so the panel is positioned from the edge next
/// to the palette and the toast's height never enters the maths.
struct ToastCanvas: View {
    @ObservedObject var presentation: ToastPresentation

    var body: some View {
        let inset = PaletteMetrics.toastShadowInset
        let atTop = presentation.verticalAlignment == .top
        ToastView(
            toast: presentation.toast,
            theme: presentation.theme,
            palette: presentation.palette
        )
        .frame(width: presentation.width, alignment: .leading)
        .shadow(color: .black.opacity(0.26), radius: 12, y: atTop ? 4 : -4)
        .padding(.top, atTop ? inset : 0)
        .padding(.bottom, atTop ? 0 : inset)
        .frame(
            width: PaletteMetrics.toastCanvasSize.width,
            height: PaletteMetrics.toastCanvasSize.height,
            alignment: atTop ? .top : .bottom
        )
    }
}
