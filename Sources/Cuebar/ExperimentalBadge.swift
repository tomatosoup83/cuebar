import SwiftUI
import CuebarCore

/// A small orange flask that marks a build made off a release branch. It lives
/// in the palette footer, next to the settings/actions hints, so a branch build
/// is never mistaken for a shipped release.
struct ExperimentalBadge: View {
    /// Resolved once — the build channel can't change while the app runs. Views
    /// read this to skip the badge entirely on release builds.
    static let isExperimental = BuildChannel.current().isExperimental

    var body: some View {
        Image(systemName: "flask.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.orange)
            .padding(5)
            .background(.orange.opacity(0.16), in: Circle())
            .overlay {
                Circle().strokeBorder(.orange.opacity(0.35), lineWidth: 0.5)
            }
            .help("Built from the experimental branch — not a release build")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Experimental build")
    }
}
