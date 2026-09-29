import SwiftUI
import CuebarCore

/// The embedded settings screen, shown inside the same palette panel.
struct SettingsView: View {
    @ObservedObject var model: PaletteModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(spacing: 2) {
                    hotKeyRow
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            Divider().opacity(0.6)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.closeSettings()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Settings")
                .font(.system(size: 20, weight: .medium))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var hotKeyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(.quaternary)
                Image(systemName: "command")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Launch Hotkey")
                    .font(.system(size: 15, weight: .medium))
                Text(model.settingsMessage ?? "Global shortcut to open Cuebar")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        model.settingsMessage == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(Color.red)
                    )
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !model.isRecordingHotKey {
                Button("Reset") {
                    model.resetHotKey()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Button {
                model.beginHotKeyRecording()
            } label: {
                Text(model.isRecordingHotKey ? "Press keys…" : model.hotKey.displayString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        model.isRecordingHotKey
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.primary)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        model.isRecordingHotKey
                            ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                            : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "⏎", label: "record")
            KeyHint(key: "esc", label: "back")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}