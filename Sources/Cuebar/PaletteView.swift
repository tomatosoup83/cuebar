import SwiftUI
import CuebarCore

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var isFieldFocused: Bool
    /// How far the results list is scrolled, so the now-playing glow may only
    /// spill over the search box while the card is at the top.
    @State private var scrollOffset: CGFloat = 0
    /// Where each presentation was last scrolled to, so returning to one puts it
    /// back rather than inheriting the view that replaced it.
    @State private var savedScrollOffsets: [String: CGFloat] = [:]
    /// The context `savedScrollOffsets` was last written from. One geometry
    /// callback still carries the outgoing view's offset right after a change;
    /// filing that under the incoming context would clobber the position we are
    /// about to restore.
    @State private var observedScrollContext = ""
    /// Drives programmatic scrolling for the restore.
    @State private var scrollPosition = ScrollPosition(idType: Never.self)
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
            // The artist page's status gets its own band between two separators,
            // so the field itself stays the same height as every other screen.
            if let artist = model.artistFocus {
                artistStatusBar("Searching for songs from \(artist.title)")
                Divider().opacity(0.6)
            } else if let album = model.albumFocus {
                artistStatusBar(albumStatusText(album))
                Divider().opacity(0.6)
            }
            ZStack(alignment: .bottomTrailing) {
                content
                if let menu = model.actionsMenu {
                    // Catches taps outside the popup so clicking the results
                    // dismisses it, Raycast-style.
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeActionsMenu() }
                        .zIndex(1)
                    ActionsMenuView(model: model, menu: menu)
                        // Only the complete popup transforms; its layout and
                        // rows must not inherit the presentation animation.
                        .transaction { $0.animation = nil }
                        .compositingGroup()
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .scale(scale: 0.85, anchor: .bottomTrailing)
                                    .combined(with: .opacity)
                        )
                        .padding(10)
                        // Keep the outgoing popup above the results while its
                        // removal transition finishes.
                        .zIndex(2)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: model.isActionsMenuOpen)
            Divider().opacity(0.6)
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            // The artist page keeps the plain `Artist ›` scope chip; the status
            // bar below the field says whose page this is. Clicking it leaves the
            // page, like Esc.
            if model.artistFocus != nil {
                SearchScopeChip(scope: .artists, help: "Back to search") {
                    model.exitArtist()
                }
            } else if model.albumFocus != nil {
                SearchScopeChip(scope: .albums, help: "Back to search") {
                    model.exitAlbumView()
                }
            } else if let scope = model.scope {
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
        .allowsHitTesting(!model.isActionsMenuOpen)
    }

    /// The album view's header: cover and facts line, as the first item inside
    /// the scroll view so a long track list isn't squeezed.
    private var albumHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtworkView(
                source: model.albumFocus.map { PaletteItem.music($0).artworkSource } ?? nil,
                size: 58,
                cornerRadius: 9
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(model.albumFocus?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let facts = model.albumFacts, !facts.summary.isEmpty {
                    Text(facts.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The album view's status text: who made it, and in what order it plays.
    private func albumStatusText(_ album: MusicCandidate) -> String {
        let artist = album.artist.isEmpty ? "" : " · \(album.artist)"
        return "Album in track order\(artist)"
    }

    /// The status band under the field: what the list below is showing.
    private func artistStatusBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A translucent tint, deliberately *not* `.quaternary`: that hierarchical
        // style composites against the backdrop and renders as an opaque white
        // strip here, which would read as a bright bar over the glass.
        .background(Color.primary.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var fieldPlaceholder: String {
        if model.artistFocus != nil {
            return "Song name…"
        }
        if model.albumFocus != nil {
            return "Track name…"
        }
        switch model.scope {
        case .albums: return "Album name…"
        case .playlists: return "Playlist name…"
        case .artists: return "Artist name…"
        case .themes: return "Filter themes…"
        default: return "Play a song or type a command…"
        }
    }

    /// Which scroll context the palette is showing.
    ///
    /// The results list is a single scroll container across every presentation,
    /// so it keeps its offset when the content changes underneath it. Each
    /// presentation therefore needs its own remembered offset: without one,
    /// leaving a deeply scrolled view strands the next at the same offset — an
    /// album view opened from a scrolled album list renders blank, because its
    /// much shorter content is entirely above the inherited offset.
    private var scrollContext: String {
        if let artist = model.artistFocus { return "artist:\(artist.id)" }
        if let album = model.albumFocus { return "album:\(album.id)" }
        return "search"
    }

    @ViewBuilder
    private var content: some View {
        // The album view keeps its header even when a filter matches nothing, so
        // it never collapses into a bare "No matches".
        if model.items.isEmpty, model.albumFocus == nil {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if model.albumFocus != nil {
                            albumHeader
                        }
                        if model.items.isEmpty {
                            Text("No tracks match")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 18)
                        }
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
                // Let the now-playing glow draw up over the search box instead of
                // being cut at the list's edge…
                .scrollClipDisabled()
                .mask(alignment: .bottom) {
                    // …but only while the card is at the top. Once scrolled, the
                    // allowance is gone so rows can't bleed over the field.
                    Rectangle().padding(.top, -glowOverflow)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    scrollOffset = offset
                    if observedScrollContext.isEmpty || observedScrollContext == scrollContext {
                        savedScrollOffsets[scrollContext] = offset
                    }
                    observedScrollContext = scrollContext
                }
                .onChange(of: scrollContext) { _, context in
                    scrollPosition.scrollTo(y: savedScrollOffsets[context] ?? 0)
                }
                .onChange(of: model.selectedIndex) { _, newValue in
                    guard model.items.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(rowIdentity(for: model.items[newValue]), anchor: .center)
                    }
                }
            }
        }
    }

    /// The identity a row view is built under.
    ///
    /// The album view renders `.music` rows with a *different view type*, so the
    /// identity has to change with the presentation. Keyed on `PaletteItem.id`
    /// alone it did not, and the lazy list reused whatever row was already on
    /// screen for that track: a cover-art search row left inside the album view,
    /// or a numbered track row left in the search list after leaving it.
    private func rowIdentity(for item: PaletteItem) -> String {
        model.albumFocus == nil ? item.id : "albumTrack:\(item.id)"
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
            .id(rowIdentity(for: item))
        } else if model.albumFocus != nil, case .music(let track) = item {
            AlbumTrackRowView(
                track: track,
                number: model.albumNumber(for: track),
                isSelected: index == model.selectedIndex,
                accent: tintAccent(for: item, at: index),
                onSelect: { model.select(index) },
                onPlay: {
                    model.select(index)
                    model.executeSelection()
                }
            )
            .id(rowIdentity(for: item))
        } else {
            ResultRowView(
                item: item,
                isSelected: index == model.selectedIndex,
                accent: tintAccent(for: item, at: index)
            )
            .id(rowIdentity(for: item))
            .onTapGesture { model.select(index) }
            .onTapGesture(count: 2) {
                model.select(index)
                model.executeSelection()
            }
        }
    }

    /// Room above the list, in points, that the glow may use. Shrinks to nothing
    /// within the first few points of scrolling.
    private var glowOverflow: CGFloat {
        max(0, Self.glowReach - scrollOffset * 6)
    }

    private static let glowReach: CGFloat = 44

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
            } else if model.isSearching {
                // A search that has produced no rows yet (e.g. waiting on the
                // catalog fallback) shouldn't read as “no matches”.
                Text("Searching…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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
        // 11pt, not 14: the ⌘⏎ album hint shares this row with the status text,
        // and a wider gap wrapped that text onto a second line — growing the
        // footer inside a fixed-height panel.
        HStack(spacing: 11) {
            KeyHint(key: "↑↓", label: "navigate")
            if model.isNowPlayingSelected {
                KeyHint(key: "⏎", label: "play/pause")
            } else {
                KeyHint(key: "⏎", label: "run")
            }
            // Teaches the chord only where it does something: a library album
            // row. The wording matches the ⌘K menu's "View Album".
            if model.canOpenAlbumView {
                KeyHint(key: "⌘⏎", label: "album")
            }
            KeyHint(
                key: "esc",
                label: (model.artistFocus == nil && model.albumFocus == nil) ? "close" : "back"
            )
            Spacer()
            if model.isIndexing {
                Text("Indexing library…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let term = searchTerm {
                Text(searchLabel(for: term))
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if model.albumFocus != nil {
                Text(model.albumFooterText)
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if model.artistFocus != nil {
                // The header names the artist; the footer just counts.
                Text("\(model.artistSongCount) songs · type to search")
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if model.isBrowsing, let scope = model.scope {
                Text(browseLabel(for: scope))
                    .lineLimit(1)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                KeyHint(key: "⌘,", label: "settings")
                Divider().frame(height: 12)
            }
            KeyHint(key: "⌘K", label: "actions")
            if ExperimentalBadge.isExperimental {
                ExperimentalBadge()
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
        case .artists: return "Searching for “\(term)” · artists only"
        default: return "Searching for “\(term)”"
        }
    }

    private func browseLabel(for scope: SearchScope) -> String {
        switch scope {
        case .albums: return "Random albums · type to filter"
        case .playlists: return "Random playlists · type to filter"
        case .artists: return "Random artists · type to filter"
        case .themes: return ""
        }
    }
}
