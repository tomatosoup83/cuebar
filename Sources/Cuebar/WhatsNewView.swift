import AppKit
import CuebarCore
import SwiftUI

/// Announces the most important changes since the last version.
///
/// Shown once per version, and replayable from Settings.
struct WhatsNewView: View {
    @ObservedObject var model: PaletteModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .frame(maxWidth: 470)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var content: some View {
        VStack(spacing: 16) {
            badge
            Text("What's New in Cuebar \(model.currentVersionText)")
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.whatsNewHighlights, id: \.title) { entry in
                    row(entry)
                }
            }
            .padding(.top, 4)
        }
    }

    private func row(_ entry: WhatsNewEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    Color.accentColor.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .medium))
                Text(entry.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 74, height: 74)
            .background(
                Color.accentColor.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("See it on GitHub") {
                NSWorkspace.shared.open(UpdateChecker.defaultReleasePageURL)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Spacer()

            Button("Done") { model.closeWhatsNew() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }
}
