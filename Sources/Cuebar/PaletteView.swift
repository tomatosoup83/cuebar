import SwiftUI
import CuebarCore

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            switch model.screen {
            case .settings:
                SettingsView(model: model)
            case .onboarding:
                OnboardingView(model: model)
            case .search:
                searchScreen
            }
        }
        .frame(width: PaletteMetrics.panelSize.width,
               height: PaletteMetrics.panelSize.height)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        )
        .onChange(of: model.query) { _, _ in model.queryChanged() }
        .onChange(of: model.focusToken) { _, _ in isFieldFocused = true }
        .onAppear { isFieldFocused = true }
    }

    private var searchScreen: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            if let scope = model.scope {
                SearchScopeChip(scope: scope) { model.clearScope() }
            }

            TextField(fieldPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($isFieldFocused)

            if model.isSearching || model.isIndexing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var fieldPlaceholder: String {
        switch model.scope {
        case .albums: return "Album name…"
        case .playlists: return "Playlist name…"
        default: return "Play a song or type a command…"
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            ResultRowView(item: item, isSelected: index == model.selectedIndex)
                                .id(item.id)
                                .onTapGesture { model.select(index) }
                                .onTapGesture(count: 2) {
                                    model.select(index)
                                    model.executeSelection()
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    guard model.items.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(model.items[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            if let message = model.statusMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            } else {
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↑↓", label: "navigate")
            KeyHint(key: "⏎", label: "run")
            KeyHint(key: "esc", label: "close")
            Spacer()
            if model.isIndexing {
                Text("Indexing library…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let term = searchTerm {
                Text(searchLabel(for: term))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                KeyHint(key: "⌘,", label: "settings")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// The song term implied by the current input, if any.
    private var searchTerm: String? {
        guard let term = CommandParser.searchTerm(for: CommandParser.parse(model.query)),
              !term.isEmpty else { return nil }
        return term
    }

    private func searchLabel(for term: String) -> String {
        switch model.scope {
        case .albums: return "Searching for “\(term)” · albums first"
        case .playlists: return "Searching for “\(term)” · playlists first"
        default: return "Searching for “\(term)”"
        }
    }
}
