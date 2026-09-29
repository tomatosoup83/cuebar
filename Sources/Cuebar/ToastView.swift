import SwiftUI
import CuebarCore

/// The toast content: an icon, a message and optional detail, on Liquid Glass.
struct ToastView: View {
    let toast: Toast

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: PaletteMetrics.toastMaxWidth, alignment: .leading)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: PaletteMetrics.toastCornerRadius, style: .continuous)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: PaletteMetrics.toastCornerRadius, style: .continuous)
        )
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
