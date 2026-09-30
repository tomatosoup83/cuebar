import SwiftUI
import CuebarCore

/// The active search scope shown inside the search field, e.g. `[ Playlist › ]`.
///
/// Mirrors the capsules used for result badges so the scope reads as a filter.
/// Clicking it clears the scope.
struct SearchScopeChip: View {
    let scope: SearchScope
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.18), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onClear)
        .help("Clear the \(title) filter")
        .accessibilityLabel("\(title) filter")
        .accessibilityHint("Activate to clear")
    }

    private var title: String { scope.title }
    private var symbolName: String { scope.symbolName }
}
