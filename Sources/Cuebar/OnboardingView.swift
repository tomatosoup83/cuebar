import SwiftUI
import CuebarCore

/// The first-run onboarding wizard, shown inside the palette panel.
struct OnboardingView: View {
    @ObservedObject var model: PaletteModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            step
                .frame(maxWidth: 460)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    // MARK: - Steps

    @ViewBuilder
    private var step: some View {
        switch model.onboardingStep {
        case .welcome: welcome
        case .permission: permission
        case .ready: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            badge("music.note")
            title("Welcome to Cuebar")
            subtitle("A command palette for Apple Music. Search your library and control playback without leaving what you're doing.")
            hotKeyChip
        }
    }

    private var permission: some View {
        VStack(spacing: 16) {
            badge("lock.shield")
            title("Control the Music app")
            subtitle("Cuebar uses AppleScript to play and control Music. macOS asks once for permission.")
            permissionStatus
        }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            badge("sparkles")
            title("You're all set")
            indexStatus
            subtitle("Type a song, album or playlist name — or a command like “pause”.")
        }
    }

    // MARK: - Pieces

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 74, height: 74)
            .background(
                Color.accentColor.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var hotKeyChip: some View {
        VStack(spacing: 6) {
            Text(model.hotKey.displayString)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("Press anywhere to open Cuebar")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var permissionStatus: some View {
        switch model.automationGranted {
        case .some(true):
            Label("Automation access granted", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .padding(.vertical, 6)
        case .some(false):
            VStack(spacing: 10) {
                Label("Permission not granted yet", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button("Grant Access") { model.grantAutomationPermission() }
                    Button("Open System Settings") { model.openAutomationSettings() }
                }
            }
        case .none:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var indexStatus: some View {
        if model.isIndexing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Indexing your library…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("\(model.libraryTrackCount) tracks · \(model.libraryPlaylistCount) playlists")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.onboardingStep != .welcome {
                Button("Back") { model.goBackOnboarding() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            stepDots

            Spacer()

            Button(primaryTitle) {
                switch model.onboardingStep {
                case .welcome, .permission: model.advanceOnboarding()
                case .ready: model.completeOnboarding()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step == model.onboardingStep
                          ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var primaryTitle: String {
        switch model.onboardingStep {
        case .welcome: return "Continue"
        case .permission: return "Continue"
        case .ready: return "Start Searching"
        }
    }
}
