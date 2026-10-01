import SwiftUI
import CuebarCore

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.screen {
            case .settings:
                SettingsView(model: model)
            case .onboarding:
                OnboardingView(model: model)
            case .search:
                searchScreen
            case .whatsNew:
                WhatsNewView(model: model)
            }
        }
        .frame(width: PaletteMetrics.panelSize.width,
               height: PaletteMetrics.panelSize.height)
        .glassEffect(
            ThemeGlass.style(
                theme: model.theme,
                palette: model.ambientPalette,
                followsSelection: model.ambientFollowsSelection
            ),
            in: RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        )
        // The wash sits *behind* the glass so the glass samples the album colour
        // instead of the desktop.
        .background {
            ThemeBackground(
                theme: model.theme,
                palette: model.ambientPalette,
                followsSelection: model.ambientFollowsSelection,
                isDrifting: model.currentTrack?.isPlaying ?? false
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius, style: .continuous)
        )
        // A deliberate fade, so a whole-panel hue change reads as a transition
        // rather than a jump. Reduce Motion swaps instantly.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: model.ambientPalette)
        .animation(.easeInOut(duration: 0.3), value: model.theme)
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
        case .themes: return "Filter themes…"
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
                            if startsRecentSection(at: index) {
                                sectionHeader("Recently Played")
                            }
                            row(index: index, item: item)
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

    @ViewBuilder
    private func row(index: Int, item: PaletteItem) -> some View {
        if case .nowPlaying(let track) = item {
            NowPlayingCardView(
                track: track,
                isSelected: index == model.selectedIndex,
                lastPollDate: model.lastPollDate,
                accent: tintAccent(for: item, at: index),
                onSelect: { model.select(index) },
                onTogglePlay: {
                    model.select(index)
                    model.togglePlayPause()
                },
                onToggleShuffle: { model.toggleShuffle() },
                onToggleRepeat: { model.toggleRepeat() }
            )
            .id(item.id)
        } else {
            ResultRowView(
                item: item,
                isSelected: index == model.selectedIndex,
                accent: tintAccent(for: item, at: index)
            )
            .id(item.id)
            .onTapGesture { model.select(index) }
            .onTapGesture(count: 2) {
                model.select(index)
                model.executeSelection()
            }
        }
    }

    /// True for the first row of the recent shelf, which gets a header.
    private func startsRecentSection(at index: Int) -> Bool {
        guard case .recent = model.items[index] else { return false }
        guard index > 0 else { return true }
        if case .recent = model.items[index - 1] { return false }
        return true
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// The album tint for a row.
    ///
    /// `RowTintPolicy` allows it for the now-playing row always, and for any row
    /// once the user opts into following the highlighted row — so the row and the
    /// ambient background agree.
    private func tintAccent(for item: PaletteItem, at index: Int) -> AlbumPalette? {
        guard RowTintPolicy.allowsTint(
            for: item,
            followsSelection: model.ambientFollowsSelection
        ), index == model.selectedIndex else {
            return nil
        }
        return model.rowAccent
    }

    private var emptyState: some View {        VStack(spacing: 8) {
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
            if model.isNowPlayingSelected {
                KeyHint(key: "⏎", label: "play/pause")
            } else {
                KeyHint(key: "⏎", label: "run")
            }
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
            } else if model.isBrowsing, let scope = model.scope {
                Text(browseLabel(for: scope))
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

    private func browseLabel(for scope: SearchScope) -> String {
        switch scope {
        case .albums: return "Random albums · type to filter"
        case .playlists: return "Random playlists · type to filter"
        case .themes: return ""
        }
    }
}
