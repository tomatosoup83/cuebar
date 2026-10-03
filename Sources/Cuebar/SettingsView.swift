import AppKit
import CuebarCore
import SwiftUI

/// The embedded settings screen, shown inside the same palette panel.
///
/// Navigable with ↑/↓ exactly like the results list; ⏎ runs the highlighted row's
/// primary action.
struct SettingsView: View {
    @ObservedObject var model: PaletteModel

    /// The name of the coordinate space the Theme row reports its frame in, so the
    /// dropdown can be positioned at it.
    static let coordinateSpace = "cuebar.settings"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(spacing: 2) {
                    hotKeyRow
                    themeRow
                    followSelectionRow
                    updateRow
                    whatsNewRow
                    onboardingRow
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            Divider().opacity(0.6)
            footer
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(ThemeRowFrameKey.self) { frame in
            model.setThemeRowFrame(frame)
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

    // MARK: - Rows

    private var hotKeyRow: some View {
        HStack(spacing: 12) {
            tile("command")

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
        .settingsRow(isSelected: model.selectedSettingsRow == .hotKey)
        .onTapGesture { model.selectSettingsRow(.hotKey) }
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            tile(model.theme.symbolName)

            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.system(size: 15, weight: .medium))
                Text(model.theme.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // A real menu, so the dropdown keeps its arrow-key and Return handling.
            Button {
                model.selectSettingsRow(.theme)
                model.openThemeMenu()
            } label: {
                HStack(spacing: 6) {
                    Text(model.theme.title)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .settingsRow(isSelected: model.selectedSettingsRow == .theme)
        .onTapGesture { model.selectSettingsRow(.theme) }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ThemeRowFrameKey.self,
                    value: proxy.frame(in: .named(Self.coordinateSpace))
                )
            }
        }
    }

    /// Only meaningful for Album Art, so it is hidden under Tahoe.
    @ViewBuilder
    private var followSelectionRow: some View {
        if model.theme == .albumArt {
            HStack(spacing: 12) {
                tile("wand.and.stars")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow the Highlighted Row")
                        .font(.system(size: 15, weight: .medium))
                    Text("Tint the whole panel with the cover you're on")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("Follow the Highlighted Row", isOn: followSelectionBinding)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            .settingsRow(isSelected: model.selectedSettingsRow == .followSelection)
            .onTapGesture { model.selectSettingsRow(.followSelection) }
        }
    }

    private var followSelectionBinding: Binding<Bool> {
        Binding(
            get: { model.ambientFollowsSelection },
            set: { model.setFollowsSelection($0) }
        )
    }

    private var updateRow: some View {
        HStack(spacing: 12) {
            tile("arrow.down.circle")

            VStack(alignment: .leading, spacing: 2) {
                Text("Software Update")
                    .font(.system(size: 15, weight: .medium))
                if let update = model.availableUpdate {
                    Text("Version \(update.version.description) is available")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Cuebar \(model.currentVersionText)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if model.availableUpdate != nil {
                Button("Install") { model.installUpdate() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.accentColor.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }

            Button("Check") { model.checkForUpdates() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .settingsRow(isSelected: model.selectedSettingsRow == .update)
        .onTapGesture { model.selectSettingsRow(.update) }
    }

    private var whatsNewRow: some View {
        HStack(spacing: 12) {
            tile("sparkles")

            VStack(alignment: .leading, spacing: 2) {
                Text("Show What's New")
                    .font(.system(size: 15, weight: .medium))
                Text("Replay what changed in \(model.currentVersionText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Show") { model.startWhatsNew() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .settingsRow(isSelected: model.selectedSettingsRow == .whatsNew)
        .onTapGesture { model.selectSettingsRow(.whatsNew) }
    }

    private var onboardingRow: some View {
        HStack(spacing: 12) {
            tile("sparkles")

            VStack(alignment: .leading, spacing: 2) {
                Text("Show Onboarding Again")
                    .font(.system(size: 15, weight: .medium))
                Text("Replay the first-run tour")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Show") { model.startOnboarding() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .settingsRow(isSelected: model.selectedSettingsRow == .onboarding)
        .onTapGesture { model.selectSettingsRow(.onboarding) }
    }

    private func tile(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
        .frame(width: 36, height: 36)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↑↓", label: "navigate")
            KeyHint(key: "⏎", label: "select")
            KeyHint(key: "esc", label: "back")
            Spacer()
            if ExperimentalBadge.isExperimental {
                ExperimentalBadge()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// Carries the Theme row's frame up so the dropdown can be placed at it.
private struct ThemeRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    /// The shared selected-row treatment, matching the results list.
    func settingsRow(isSelected: Bool) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
