import Foundation
import Combine
import CuebarCore

/// Which screen the palette is showing.
enum PaletteScreen: Equatable {
    case search
    case settings
    case onboarding
    case whatsNew
}

/// Steps of the first-run onboarding wizard.
enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case permission
    case ready
}

/// Which list the ⌘K actions menu is showing.
enum ActionsMenuMode: Equatable {
    case main
    case playlists
}

/// Presentation state for the ⌘K actions menu.
struct ActionsMenuState: Equatable {
    var mode: ActionsMenuMode = .main
    var selection: Int = 0
    var query: String = ""
}

/// Presentation state for the palette.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var query: String = ""
    /// Active in-field scope (nil = plain search).
    @Published private(set) var scope: SearchScope?
    @Published private(set) var items: [PaletteItem] = []
    @Published private(set) var selectedIndex: Int = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSearching = false
    @Published private(set) var isIndexing = false
    /// Changes whenever the panel is shown so the view can refocus the field.
    @Published private(set) var focusToken = UUID()

    // Settings
    @Published private(set) var screen: PaletteScreen = .search
    /// Highlighted Settings row; navigated with ↑/↓.
    @Published private(set) var settingsSelection: Int = 0
    @Published private(set) var hotKey: HotKeyPreference
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var settingsMessage: String?

    // Onboarding
    @Published private(set) var onboardingStep: OnboardingStep = .welcome
    @Published private(set) var automationGranted: Bool?

    // Updates
    @Published private(set) var availableUpdate: UpdateInfo?

    // Theming
    @Published private(set) var theme: ThemeID
    /// Whether the ambient colour follows the highlighted row.
    @Published private(set) var ambientFollowsSelection: Bool
    /// Whether Album Art v2 mixes every cluster into one global colour (no
    /// gradient). Only meaningful for that theme.
    @Published private(set) var usesGlobalColours: Bool
    /// The ambient wash colour, pushed in by the window controller.
    @Published private(set) var ambientPalette: AlbumPalette?
    /// The selected row's own album palette, when the Album Art theme is on.
    @Published private(set) var rowAccent: AlbumPalette?

    // Home screen
    /// The "Recently Played" shelf. Kept across openings so the shelf paints on
    /// the first frame, then refreshed in the background.
    @Published private(set) var recent: [RecentTrack] = []

    var onClose: (() -> Void)?
    /// Reports playback outcomes as toasts.
    var onToast: ((Toast) -> Void)?
    /// Rebuilds the library index; returns counts, or nil on failure.
    var onRebuildLibraryIndex: (() async -> LibraryIndexSummary?)?
    /// Persists completion of the first-run onboarding.
    var onOnboardingComplete: (() -> Void)?
    /// Opens the Automation section of System Settings.
    var onOpenAutomationSettings: (() -> Void)?
    /// Checks GitHub for a newer release.
    var onCheckForUpdates: (() -> Void)?
    /// Downloads and installs the available update.
    var onInstallUpdate: (() -> Void)?
    /// Persists a newly chosen theme.
    var onThemeChange: ((ThemeID) -> Void)?
    /// Persists the "ambient follows the highlighted row" option.
    var onAmbientFollowsSelectionChange: ((Bool) -> Void)?
    /// Persists the Album Art v2 "global colours" option.
    var onGlobalColoursChange: ((Bool) -> Void)?
    /// Opens the Theme dropdown at the Settings row (AppKit owns the menu, so it
    /// gets real arrow-key and Return handling for free).
    var onOpenThemeMenu: (() -> Void)?
    /// Called when the What's New screen is presented, so it is marked as seen.
    var onWhatsNewShown: (() -> Void)?
    /// Notifies whoever is interested which row is highlighted.
    ///
    /// Deliberately **not** driven by a `@Published` sink: `@Published` fires in
    /// `willSet`, so such a sink would read the *previous* selection and the
    /// ambient colour would lag a row behind.
    var onSelectionChange: ((PaletteItem?) -> Void)?
    /// Applies a new hotkey; returns false when the shortcut is unavailable.
    var onHotKeyChange: ((HotKeyPreference) -> Bool)?
    /// Reads every track's last-played age from Music; nil on failure.
    var onFetchPlayedDates: (() async -> [PlayedEntry]?)?
    /// Tracks seen playing while Cuebar ran; merged into the recent shelf.
    var playHistory: PlayHistory?

    private let searchService: SearchService
    private let musicController: MusicController
    private let libraryProvider: LibrarySearchProvider
    private let executor: CommandExecutor
    private var cancellables = Set<AnyCancellable>()

    private var commands: [CommandEntry] = []
    private var music: [MusicCandidate] = []
    private var nowPlaying: NowPlayingTrack?
    /// Resolves the selected row's album palette (Album Art theme only).
    private var accentTask: Task<Void, Never>?
    /// When now-playing was last polled, for progress interpolation.
    private(set) var lastPollDate: Date?
    /// The scope currently being browsed (nil = not browsing).
    private var browsePreference: RankPreference?

    // Artist page
    /// The artist whose page is showing, or nil. The page keeps the search
    /// field: typing there filters *that artist's* songs, never the library.
    @Published private(set) var artistFocus: MusicCandidate?
    /// The artist page's whole catalogue, snapshotted when the page opens.
    private var artistTracks: [MusicCandidate] = []
    /// True while the page is showing its shuffled sample (empty field) rather
    /// than matches for what was typed.
    private var artistIsBrowsing = false
    /// Everything needed to put the palette back exactly as it was before a
    /// detail view was opened. One slot serves both views: only one can be open.
    ///
    /// The list is **restored**, not recomputed. Recomputing re-shuffles a browse
    /// list — leaving an album view handed back a different random order — and
    /// arrives asynchronously, so the scroll restore would clamp against the
    /// outgoing (much shorter) content before the real one landed.
    private struct ReturnState {
        let query: String
        let scope: SearchScope?
        let music: [MusicCandidate]
        let commands: [CommandEntry]
        let browsePreference: RankPreference?
        let resultsQuery: SearchQuery?
        let selectedIndex: Int
    }

    private var returnState: ReturnState?

    // Extended album view
    /// The album whose extended view is showing, or nil.
    @Published private(set) var albumFocus: MusicCandidate?
    /// The album's tracks in original running order, with display numbers.
    private var albumTracks = AlbumTrackList(tracks: [])
    /// The facts line at the top of the view.
    @Published private(set) var albumFacts: AlbumFacts?
    /// True while the view shows its full track list (empty field) rather than
    /// matches for what was typed.
    private var albumIsShowingAll = false

    /// Rows the palette shows for a search or a browse list.
    private static let rowLimit = 40
    /// Last-played ages from the most recent fetch.
    private var playedEntries: [PlayedEntry] = []
    /// When `playedEntries` was read, so ages stay correct between fetches.
    private var playedEntriesDate = Date()
    private var recentTask: Task<Void, Never>?
    /// The track Music has loaded, from its change notifications. Lets the shelf
    /// leave it out even before the first poll has filled the card.
    private var loadedTrackID: String?
    /// The query whose results the list currently shows (or is waiting on). A
    /// newer query leaves the previous list up until its own results land, so
    /// fast typing never flashes an empty state or mixes two queries' rows.
    private var resultsQuery: SearchQuery?
    /// True while a song search is in flight and the list is frozen on the
    /// previous query's rows.
    private var isSearchPending = false

    // ⌘K actions menu
    /// The menu's state, or nil when it is closed.
    @Published private(set) var actionsMenu: ActionsMenuState?
    /// The row the open menu belongs to, snapshotted so background refreshes
    /// can't move it out from under the user.
    private var actionsTarget: PaletteItem?
    /// The library track ID for the target, when it has one (enables Like /
    /// Add to Playlist).
    private var actionsLibraryTrackID: String?
    /// The target track's Loved state, fetched when the menu opens.
    @Published private(set) var actionsLoved: Bool?
    private var actionsLovedTask: Task<Void, Never>?
    /// Changes when the actions search field should take focus.
    @Published private(set) var actionsFocusToken = UUID()

    /// Whether the empty-scope browse list is showing.
    var isBrowsing: Bool { browsePreference != nil }

    /// Whether the selected row is the now-playing card.
    var isNowPlayingSelected: Bool {
        if case .nowPlaying = selectedItem { return true }
        return false
    }

    init(
        searchService: SearchService,
        musicController: MusicController,
        libraryProvider: LibrarySearchProvider,
        hotKey: HotKeyPreference = .default,
        theme: ThemeID = .albumArt,
        ambientFollowsSelection: Bool = true,
        usesGlobalColours: Bool = false
    ) {
        self.searchService = searchService
        self.musicController = musicController
        self.libraryProvider = libraryProvider
        self.hotKey = hotKey
        self.theme = theme
        self.ambientFollowsSelection = ambientFollowsSelection
        self.usesGlobalColours = usesGlobalColours
        self.executor = CommandExecutor(controller: musicController)

        searchService.$results
            .sink { [weak self] newResults in
                guard let self else { return }
                self.music = newResults
                self.isSearchPending = false
                self.rebuildItems()
            }
            .store(in: &cancellables)

        searchService.$statusMessage
            .sink { [weak self] in self?.statusMessage = $0 }
            .store(in: &cancellables)

        searchService.$isSearching
            .sink { [weak self] searching in
                guard let self else { return }
                self.isSearching = searching
                // Safety net: if a search ends without ever publishing results
                // (both providers failed), don't leave the list frozen forever.
                if !searching, self.isSearchPending {
                    self.isSearchPending = false
                    self.rebuildItems()
                }
            }
            .store(in: &cancellables)

        searchService.$isIndexing
            .sink { [weak self] indexing in
                guard let self else { return }
                let finished = self.isIndexing && !indexing
                self.isIndexing = indexing
                // Played dates can land before the index does (first launch, or a
                // rebuild); resolve them again against the fresh library.
                if finished { self.recomputeRecent() }
            }
            .store(in: &cancellables)
    }

    var selectedItem: PaletteItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func reset() {
        query = ""
        scope = nil
        browsePreference = nil
        artistFocus = nil
        artistTracks = []
        artistIsBrowsing = false
        returnState = nil
        albumFocus = nil
        albumTracks = AlbumTrackList(tracks: [])
        albumFacts = nil
        albumIsShowingAll = false
        searchService.clear()
        commands = []
        music = []
        nowPlaying = nil
        items = []
        selectedIndex = 0
        statusMessage = nil
        isSearching = false
        resultsQuery = nil
        isSearchPending = false
        actionsMenu = nil
        actionsTarget = nil
        actionsLibraryTrackID = nil
        actionsLoved = nil
        actionsLovedTask?.cancel()
        actionsLovedTask = nil
        screen = .search
        isRecordingHotKey = false
        settingsMessage = nil
        accentTask?.cancel()
        accentTask = nil
        rowAccent = nil
        focusToken = UUID()
    }

    func requestFocus() {
        focusToken = UUID()
    }

    /// Recompute the command rows and the song search for the current input.
    func queryChanged() {
        // The artist page owns the field: it filters that one artist's songs and
        // never promotes a keyword into a scope.
        if artistFocus != nil {
            artistQueryChanged()
            return
        }
        // The extended album view owns the field in the same way.
        if albumFocus != nil {
            albumQueryChanged()
            return
        }

        // A leading/trailing keyword followed by whitespace becomes a scope:
        // move it out of the field text so it isn't duplicated by the chip.
        let parsed = SearchQuery.parse(query)
        if let parsedScope = parsed.scope {
            scope = parsedScope
            query = parsed.term
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // The theme scope is an options list, not a music search: whatever is typed
        // after it narrows the options.
        if scope == .themes {
            browsePreference = nil
            resultsQuery = nil
            isSearchPending = false
            searchService.clear()
            music = []
            commands = ThemeScopeMenu.entries(
                currentTheme: theme,
                followsSelection: ambientFollowsSelection,
                globalColours: usesGlobalColours,
                filter: trimmed
            )
            rebuildItems()
            return
        }

        // `artist ` is a filter, not a ranking: only artist rows, and they come
        // straight from the library index (there is no catalog artist index, and
        // ranking the whole pool first would let song matches crowd them out).
        if scope == .artists {
            commands = []
            resultsQuery = nil
            isSearchPending = false
            searchService.clear()
            if trimmed.isEmpty {
                // `clear()` above emptied `music` through the results sink, so
                // the sample is rebuilt whenever one isn't already up *or* the
                // list is empty. The bare "already browsing" guard would leave
                // the palette blank on the second pass: promoting the keyword
                // clears the field programmatically, and the view's own
                // `onChange` for that runs this whole branch again.
                if browsePreference != .artists || music.isEmpty {
                    browsePreference = .artists
                    selectedIndex = 0
                    music = LibraryBrowse.shuffled(
                        libraryProvider.artists(),
                        limit: Self.rowLimit
                    )
                }
            } else {
                browsePreference = nil
                music = libraryProvider.searchArtists(trimmed, limit: Self.rowLimit)
            }
            rebuildItems()
            return
        }

        // A music scope is songs-only, so command rows are suppressed. The home
        // screen trades the transport commands for the recent shelf.
        if scope != nil {
            commands = []
        } else if trimmed.isEmpty {
            commands = PaletteListComposer.homeCommands(
                commandEntries(for: trimmed),
                hasRecent: !recent.isEmpty
            )
        } else {
            commands = commandEntries(for: trimmed)
        }

        // Songs: only for `play <song>` or free text. A recognised non-play
        // command shows just the command. An empty scope browses that kind.
        if let term = CommandParser.searchTerm(for: CommandParser.parse(query)), !term.isEmpty {
            browsePreference = nil
            let searchQuery = SearchQuery(term: term, preference: scope?.rankPreference ?? .songs)
            if searchQuery != resultsQuery {
                resultsQuery = searchQuery
                // Keep the current rows until these land, so typing can't flash an
                // empty state or compose two queries' results together.
                isSearchPending = true
                searchService.updateQuery(searchQuery)
            }
        } else if let browse = scope?.rankPreference {
            resultsQuery = nil
            isSearchPending = false
            if browsePreference != browse {
                browsePreference = browse
                selectedIndex = 0
                searchService.browse(browse)
            }
        } else {
            browsePreference = nil
            resultsQuery = nil
            isSearchPending = false
            searchService.clear()
            music = []
        }

        // A newer song search owns the next rebuild; keep the old rows until it
        // publishes its results.
        if !isSearchPending {
            rebuildItems()
        }
    }

    /// Drops the active scope, returning to a plain search.
    func clearScope() {
        guard scope != nil else { return }
        scope = nil
        queryChanged()
    }

    // MARK: - Artist page

    /// How many songs the open artist page has, for the footer.
    var artistSongCount: Int { artistTracks.count }

    /// Opens the artist page: the artist's songs, shuffled until the user types.
    ///
    /// The search the page was opened from is remembered so Esc (or Backspace on
    /// an empty field) returns to it, like a push/pop.
    func openArtist(_ artist: MusicCandidate) {
        guard artist.kind == .artist else { return }
        guard let tracks = libraryProvider.tracks(forArtistID: artist.id), !tracks.isEmpty else {
            statusMessage = "“\(artist.title)” has no songs in your library."
            return
        }

        returnState = captureReturnState()
        artistTracks = tracks
        artistFocus = artist
        // The artist's own page is not inside the `artist ` scope any more; the
        // chip stays an `Artist` scope chip and the header names the artist.
        scope = nil
        browsePreference = nil
        statusMessage = nil
        query = ""
        // Fill the page *here* rather than routing through `queryChanged()`: the
        // songs have to be on screen the instant the page opens, not one
        // round trip later. The view's own `onChange` for the cleared field runs
        // afterwards and finds the sample already up.
        artistShowSample()
    }

    /// Leaves the artist page, restoring the search it was opened from.
    func exitArtist() {
        guard artistFocus != nil else { return }
        artistFocus = nil
        artistTracks = []
        artistIsBrowsing = false

        restoreReturnState()
    }

    // MARK: - Extended album view

    /// How many tracks the open album view has, for the footer.
    var albumTrackCount: Int { albumTracks.entries.count }

    /// The album view's footer text.
    var albumFooterText: String {
        let count = albumTrackCount
        return "\(count) track\(count == 1 ? "" : "s") \u{00b7} type to filter"
    }

    /// The number shown beside a track row (`1`, or `1-3` on a multi-disc album).
    func albumNumber(for track: MusicCandidate) -> String {
        albumTracks.entries.first { $0.id == track.id }?.number ?? ""
    }

    /// Development helper: highlight the nearest library album row at or after
    /// the current selection, so the album view can be opened from a scrolled
    /// list without jumping back to the top.
    func debugSelectNearestAlbumRow() {
        let isAlbum: (PaletteItem) -> Bool = { item in
            guard case .music(let candidate) = item else { return false }
            return candidate.kind == .album && candidate.source == .library
        }
        if let index = items.indices.dropFirst(selectedIndex).first(where: { isAlbum(items[$0]) }) {
            select(index)
        } else if let index = items.indices.prefix(selectedIndex).last(where: { isAlbum(items[$0]) }) {
            select(index)
        }
    }

    /// Whether the highlighted row can open the extended album view.
    var canOpenAlbumView: Bool {
        guard case .music(let candidate)? = selectedItem else { return false }
        return candidate.kind == .album && candidate.source == .library
    }

    /// Opens the extended album view: the album's tracks in their original
    /// running order, with the facts line above them.
    func openAlbumView(_ album: MusicCandidate) {
        guard album.kind == .album, album.source == .library else { return }
        guard let tracks = libraryProvider.tracks(forAlbumID: album.id), !tracks.isEmpty else {
            statusMessage = "“\(album.title)” has no tracks to show."
            return
        }

        returnState = captureReturnState()
        albumTracks = AlbumTrackList(tracks: tracks)
        albumFacts = AlbumFacts(album: album, tracks: tracks)
        albumFocus = album
        scope = nil
        browsePreference = nil
        statusMessage = nil
        query = ""
        // Fill the list here rather than via `queryChanged()`, so the tracks are
        // on screen the instant the view opens — the same reason the artist page
        // populates directly.
        albumShowAll()
    }

    /// Leaves the album view, restoring the search it was opened from.
    func exitAlbumView() {
        guard albumFocus != nil else { return }
        albumFocus = nil
        albumTracks = AlbumTrackList(tracks: [])
        albumFacts = nil
        albumIsShowingAll = false

        restoreReturnState()
    }

    /// ⌘⏎ on the highlighted row: the extended album view for a library album,
    /// otherwise the ordinary action, so the shortcut is never a dead key.
    func executeExtendedSelection() {
        if case .music(let candidate)? = selectedItem,
           candidate.kind == .album, candidate.source == .library {
            openAlbumView(candidate)
            return
        }
        executeSelection()
    }

    /// The album view's list: every track in order while the field is empty,
    /// otherwise the tracks whose titles match what was typed.
    private func albumQueryChanged() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if !albumIsShowingAll || music.isEmpty {
                albumShowAll()
            } else {
                rebuildItems()
            }
        } else {
            albumIsShowingAll = false
            beginLocalResults()
            music = Ranking.rankWithin(
                albumTracks.entries.map(\.track),
                query: trimmed,
                limit: Self.rowLimit
            )
            rebuildItems()
        }
    }

    /// Shows the album's full track list in its original order.
    private func albumShowAll() {
        albumIsShowingAll = true
        selectedIndex = 0
        beginLocalResults()
        music = albumTracks.entries.map(\.track)
        rebuildItems()
    }

    /// The artist page's list: a shuffled sample while the field is empty,
    /// otherwise the songs whose titles match what was typed.
    private func artistQueryChanged() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            // The sample is (re)built whenever it isn't already up. `music.isEmpty`
            // is the safety net: an empty field must never leave the page blank
            // while the artist has songs.
            if !artistIsBrowsing || music.isEmpty {
                artistShowSample()
            } else {
                rebuildItems()
            }
        } else {
            artistIsBrowsing = false
            beginLocalResults()
            music = Ranking.rankWithin(artistTracks, query: trimmed, limit: Self.rowLimit)
            rebuildItems()
        }
    }

    /// Shows a fresh shuffled sample of the open artist's songs.
    private func artistShowSample() {
        artistIsBrowsing = true
        selectedIndex = 0
        beginLocalResults()
        music = LibraryBrowse.shuffled(artistTracks, limit: Self.rowLimit)
        rebuildItems()
    }

    /// Snapshots the list a detail view is about to cover up.
    private func captureReturnState() -> ReturnState {
        ReturnState(
            query: query,
            scope: scope,
            music: music,
            commands: commands,
            browsePreference: browsePreference,
            resultsQuery: resultsQuery,
            selectedIndex: selectedIndex
        )
    }

    /// Puts the palette back the way `captureReturnState()` found it.
    ///
    /// Restoring `browsePreference` and `resultsQuery` also makes the view's own
    /// `onChange` for the restored field harmless: `queryChanged()` then sees the
    /// browse kind or the query it already holds and neither re-shuffles nor
    /// re-searches over the top of what was just put back. (When the field was
    /// empty before *and* after — the browse case — assigning it is not even a
    /// change, so `queryChanged()` never runs at all.)
    private func restoreReturnState() {
        guard let state = returnState else {
            queryChanged()
            return
        }
        returnState = nil

        query = state.query
        scope = state.scope
        music = state.music
        commands = state.commands
        browsePreference = state.browsePreference
        resultsQuery = state.resultsQuery
        isSearchPending = false
        rebuildItems()
        if items.indices.contains(state.selectedIndex), selectedIndex != state.selectedIndex {
            select(state.selectedIndex)
        }
    }

    /// Shared setup for rows computed locally, by the artist page or the album
    /// view.
    ///
    /// Neither goes through `SearchService`, so anything it might still publish
    /// has to be dropped first, or a stale library search would land on top of
    /// the list.
    private func beginLocalResults() {
        commands = []
        resultsQuery = nil
        isSearchPending = false
        searchService.clear()
    }

    // MARK: - Updates

    /// The running version, for Settings.
    var currentVersionText: String {
        AppVersion.current()?.description ?? "—"
    }

    func setAvailableUpdate(_ update: UpdateInfo?) {
        guard update != availableUpdate else { return }
        availableUpdate = update
        queryChanged()
    }

    func checkForUpdates() {
        onCheckForUpdates?()
    }

    func installUpdate() {
        onInstallUpdate?()
    }

    // MARK: - Theming

    /// The track the poll currently has, so the window can resolve its palette.
    var currentTrack: NowPlayingTrack? { nowPlaying }

    func setAmbientPalette(_ palette: AlbumPalette?) {
        guard palette != ambientPalette else { return }
        ambientPalette = palette
    }

    func setTheme(_ theme: ThemeID) {
        guard theme != self.theme else { return }
        self.theme = theme
        onThemeChange?(theme)
        clampSettingsSelection()
        // Rebuild so the "Theme:" rows move their checkmark (which also
        // re-resolves the selected row's accent for the new theme).
        queryChanged()
    }

    /// Turns the "ambient follows the highlighted row" option on or off.
    func setFollowsSelection(_ follows: Bool) {
        guard follows != ambientFollowsSelection else { return }
        ambientFollowsSelection = follows
        onAmbientFollowsSelectionChange?(follows)
    }

    /// Turns the Album Art v2 "global colours" (no gradient) option on or off.
    func setUsesGlobalColours(_ global: Bool) {
        guard global != usesGlobalColours else { return }
        usesGlobalColours = global
        onGlobalColoursChange?(global)
        // The extraction style changed: rebuild so the option rows move their
        // checkmark and the selected row's accent re-resolves.
        queryChanged()
    }

    /// The extraction recipe for the current theme and options, or nil when the
    /// theme does not use album art.
    var paletteStyle: PaletteStyle? {
        theme.paletteStyle(globalClusteredColours: usesGlobalColours)
    }

    // MARK: - Settings navigation

    /// The rows Settings currently shows, in order.
    var visibleSettingsRows: [SettingsRow] { SettingsRow.visibleRows(theme: theme) }

    /// The highlighted Settings row, if any.
    var selectedSettingsRow: SettingsRow? {
        let rows = visibleSettingsRows
        guard rows.indices.contains(settingsSelection) else { return nil }
        return rows[settingsSelection]
    }

    /// Highlights a specific row, if it is currently visible.
    func selectSettingsRow(_ row: SettingsRow) {
        guard let index = visibleSettingsRows.firstIndex(of: row) else { return }
        settingsSelection = index
    }

    /// The Theme row's rect in the Settings view's coordinate space, so the
    /// dropdown can be positioned at it.
    private(set) var themeRowFrame: CGRect = .zero

    func setThemeRowFrame(_ frame: CGRect) {
        themeRowFrame = frame
    }

    func openThemeMenu() {
        onOpenThemeMenu?()
    }

    func moveSettingsSelection(by delta: Int) {
        let count = visibleSettingsRows.count
        guard count > 0 else { return }
        settingsSelection = min(max(settingsSelection + delta, 0), count - 1)
    }

    /// Runs the highlighted row's primary action.
    func activateSettingsRow() {
        switch selectedSettingsRow {
        case .hotKey:
            beginHotKeyRecording()
        case .theme:
            onOpenThemeMenu?()
        case .followSelection:
            setFollowsSelection(!ambientFollowsSelection)
        case .globalColours:
            setUsesGlobalColours(!usesGlobalColours)
        case .update:
            // Install is the primary action when there is something to install.
            if availableUpdate != nil { installUpdate() } else { checkForUpdates() }
        case .whatsNew:
            startWhatsNew()
        case .onboarding:
            startOnboarding()
        case .none:
            break
        }
    }

    /// Switching away from Album Art hides a row, so the highlight must not dangle.
    private func clampSettingsSelection() {
        let count = visibleSettingsRows.count
        if settingsSelection >= count { settingsSelection = max(0, count - 1) }
    }

    // MARK: - What's New

    private var whatsNewReturnScreen: PaletteScreen = .search

    /// The highlights the running version announces.
    var whatsNewHighlights: [WhatsNewEntry] {
        guard let version = AppVersion.current()?.description else { return [] }
        return WhatsNew.highlights(for: version)
    }

    func startWhatsNew() {
        whatsNewReturnScreen = (screen == .settings) ? .settings : .search
        screen = .whatsNew
        isRecordingHotKey = false
        settingsMessage = nil
        onWhatsNewShown?()
    }

    func closeWhatsNew() {
        screen = whatsNewReturnScreen
        requestFocus()
    }

    /// The highlighted row changed (or the rows were rebuilt): refresh everything
    /// derived from it, and tell the ambient theme.
    private func selectionChanged() {
        refreshRowAccent()
        onSelectionChange?(selectedItem)
    }

    /// Resolves the accent for whatever row is selected.
    ///
    /// Not cache-only on purpose: the row icons already fetch their artwork, so
    /// this piggybacks on that same cache — no extra AppleScript lookups. It just
    /// may arrive a beat after the row appears.
    private func refreshRowAccent() {
        accentTask?.cancel()
        accentTask = nil

        guard let style = paletteStyle,
              let source = selectedItem?.artworkSource else {
            rowAccent = nil
            return
        }

        if let cached = PaletteCache.shared.cached(for: source, style: style) {
            rowAccent = cached.isUsable ? cached : nil
            return
        }

        rowAccent = nil
        accentTask = Task { [weak self] in
            let palette = await PaletteCache.shared.palette(for: source, style: style)
            guard !Task.isCancelled, let self else { return }
            guard self.selectedItem?.artworkSource == source,
                  self.paletteStyle == style else { return }
            self.rowAccent = (palette?.isUsable == true) ? palette : nil
        }
    }

    /// Catalog commands, with the update and theme rows injected where they match.
    private func commandEntries(for trimmed: String) -> [CommandEntry] {
        var entries = CommandCatalog.matches(for: trimmed)
        let normalized = TextNormalizer.normalize(trimmed)

        if let update = availableUpdate {
            let entry = Self.installEntry(update)
            if normalized.isEmpty || CommandCatalog.score(entry, normalizedInput: normalized) != nil {
                entries.insert(entry, at: 0)
            }
        }

        // Theme rows surface once the user types something matching, so the
        // empty-box command list stays as short as it is today. Typing `theme `
        // (with a space) promotes them to a scope instead.
        if !normalized.isEmpty {
            let matched = ThemeScopeMenu.entries(
                currentTheme: theme,
                followsSelection: ambientFollowsSelection,
                globalColours: usesGlobalColours
            ).filter { CommandCatalog.score($0, normalizedInput: normalized) != nil }
            entries.insert(contentsOf: matched, at: 0)
        }

        return entries
    }

    private static func installEntry(_ update: UpdateInfo) -> CommandEntry {
        CommandEntry(
            id: "installUpdate",
            title: "Install Update (\(update.version))",
            subtitle: "Download and relaunch Cuebar",
            symbolName: "arrow.down.circle",
            action: .installUpdate,
            keywords: ["update", "install update", "upgrade"]
        )
    }

    /// Refresh the current track from Music.app.
    func refreshNowPlaying() async {
        let track = try? await musicController.nowPlaying()
#if DEBUG
        if debugHoldsNowPlaying { return }
#endif
        lastPollDate = Date()
        guard track != nowPlaying else { return }
        let previousID = nowPlaying?.persistentID
        nowPlaying = track
        // Covers a track that was already playing when Cuebar launched, or a
        // notification that never arrived.
        if let track, track.isPlaying, let id = track.persistentID,
           playHistory?.all.first?.persistentID != id {
            playHistory?.record(id)
        }
        if previousID != track?.persistentID {
            // A new track: the one that just ended is now "recent", and the new
            // one leaves the shelf (it has the card).
            if previousID != nil { refreshRecentlyPlayed() }
            recomputeRecent()
        }
        rebuildItems()
    }

    // MARK: - Recently played

    /// Re-reads last-played dates from Music in the background.
    func refreshRecentlyPlayed() {
        guard let fetch = onFetchPlayedDates, recentTask == nil else { return }
        recentTask = Task { [weak self] in
            let entries = await fetch()
            guard let self else { return }
            self.recentTask = nil
            guard let entries else { return }
            self.playedEntries = entries
            self.playedEntriesDate = Date()
            self.recomputeRecent()
        }
    }

    /// Music announced a player change (a track started, paused or stopped).
    func playerChanged(_ event: PlayerInfoEvent) {
        loadedTrackID = event.loadedTrackID
        recomputeRecent()
    }

    private func recomputeRecent() {
        let now = Date()
        // Music's dates were read at `playedEntriesDate`; age them to now so
        // they sort correctly against the live log.
        let drift = now.timeIntervalSince(playedEntriesDate)
        let fromMusic = playedEntries.map {
            PlayedEntry(persistentID: $0.persistentID, secondsAgo: $0.secondsAgo + drift)
        }
        let updated = RecentlyPlayed.tracks(
            from: fromMusic + (playHistory?.entries(now: now) ?? []),
            library: libraryProvider.snapshot(),
            excluding: nowPlaying?.persistentID ?? loadedTrackID,
            now: now
        )
        guard updated != recent else { return }
        let hadShelf = !recent.isEmpty
        recent = updated
        // The shelf appearing (or vanishing) changes which commands the home
        // screen shows; only rebuild the commands while the home is on screen.
        if screen == .search, scope == nil, artistFocus == nil, albumFocus == nil,
           query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           hadShelf != !updated.isEmpty {
            queryChanged()
        } else {
            rebuildItems()
        }
    }

    /// Toggles play/pause from the now-playing card (stays open).
    func togglePlayPause() {
        guard let track = nowPlaying else { return }
        nowPlaying = track.copy(state: track.isPlaying ? .paused : .playing)
        rebuildItems()
        run(.music(track.isPlaying ? .pause : .resume), selected: nil, closeOnSuccess: false)
    }

    /// Toggles shuffle from the now-playing card.
    func toggleShuffle() {
        guard let track = nowPlaying else { return }
        nowPlaying = track.copy(shuffleEnabled: !track.shuffleEnabled)
        rebuildItems()
        run(.music(.shuffle(.toggle)), selected: nil, closeOnSuccess: false)
    }

    /// Toggles repeat-all (off ↔ all) from the now-playing card.
    func toggleRepeat() {
        guard let track = nowPlaying else { return }
        let next = track.repeatMode.togglingAll
        nowPlaying = track.copy(repeatMode: next)
        rebuildItems()
        run(.music(.setRepeat(next)), selected: nil, closeOnSuccess: false)
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
        selectionChanged()
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        selectionChanged()
    }

    func executeSelection() {
        guard let item = selectedItem else {
            // No rows: fall back to interpreting the raw input.
            if let command = CommandParser.parse(query) {
                run(.music(command), selected: nil)
            }
            return
        }

        switch item {
        case .nowPlaying:
            togglePlayPause()
        case .command(let entry):
            run(entry.action, selected: nil)
        case .recent(let track):
            run(.music(.play(query: track.candidate.title)), selected: track.candidate)
        case .music(let candidate):
            // An artist opens their own page; the other kinds play.
            if candidate.kind == .artist {
                openArtist(candidate)
                return
            }
            // A library album plays start to finish; a library playlist plays
            // directly; catalog rows still can't be started.
            if candidate.kind == .album, candidate.source == .library {
                playAlbum(candidate)
                return
            }
            if candidate.kind == .playlist, candidate.source == .library {
                playPlaylist(candidate)
                return
            }
            guard let playable = playableTrack(for: candidate) else {
                statusMessage = "“\(candidate.title)” isn’t in your Music library, so Cuebar can’t play it. Add it in Music first."
                onToast?(PlaybackFeedback.notInLibrary(candidate.title))
                return
            }
            run(.music(.play(query: playable.title)), selected: playable)
        }
    }

    /// Loads a library album's tracks into Music and plays them in order.
    private func playAlbum(_ album: MusicCandidate) {
        guard let tracks = libraryProvider.tracks(forAlbumID: album.id), !tracks.isEmpty else {
            statusMessage = "“\(album.title)” has no playable tracks."
            onToast?(PlaybackFeedback.emptyAlbum(album.title))
            return
        }
        statusMessage = nil
        Task {
            do {
                try await self.executor.executeAlbum(tracks)
                self.onToast?(PlaybackFeedback.playingAlbum(album, trackCount: tracks.count))
                self.onClose?()
            } catch {
                let toast = PlaybackFeedback.failure(error)
                self.statusMessage = toast.message
                self.onToast?(toast)
            }
        }
    }

    /// Plays a library playlist directly.
    private func playPlaylist(_ playlist: MusicCandidate) {
        statusMessage = nil
        let trackCount = playlist.trackCount ?? 0
        Task {
            do {
                try await self.executor.executePlaylist(playlist)
                self.onToast?(PlaybackFeedback.playingPlaylist(playlist, trackCount: trackCount))
                self.onClose?()
            } catch {
                let toast = PlaybackFeedback.failure(error)
                self.statusMessage = toast.message
                self.onToast?(toast)
            }
        }
    }

    /// Re-scans the Music library and reports the result as a toast.
    private func rebuildLibraryIndex() {
        guard let rebuild = onRebuildLibraryIndex else {
            onToast?(PlaybackFeedback.indexRebuildFailed())
            return
        }
        statusMessage = nil
        onToast?(PlaybackFeedback.rebuildingIndex())
        Task {
            if let summary = await rebuild() {
                self.onToast?(PlaybackFeedback.indexRebuilt(summary))
            } else {
                self.onToast?(PlaybackFeedback.indexRebuildFailed())
            }
        }
    }

    /// Catalog results are played through the user's library when the same
    /// track exists there; only library tracks can be started reliably.
    private func playableTrack(for candidate: MusicCandidate) -> MusicCandidate? {
        if candidate.source == .library { return candidate }
        return LibraryResolver.resolve(candidate, in: libraryProvider.snapshot())
    }

    // MARK: - ⌘K actions menu

    var isActionsMenuOpen: Bool { actionsMenu != nil }

    /// The target row's title, for the menu header and toast copy.
    var actionsTitle: String { Self.title(for: actionsTarget) }

    /// The target row's artist/album line, for the menu header.
    var actionsSubtitle: String { Self.subtitle(for: actionsTarget) }

    /// The rows the open menu shows, after filtering.
    var visibleActionsItems: [QuickActionItem] {
        guard let menu = actionsMenu else { return [] }
        switch menu.mode {
        case .main:
            guard let target = actionsTarget else { return [] }
            let all = QuickActions.items(
                for: target,
                loved: actionsLoved,
                canLike: actionsLibraryTrackID != nil
            )
            return QuickActions.filter(all, query: menu.query)
        case .playlists:
            return QuickActions.filter(QuickActions.playlistItems(actionsPlaylists), query: menu.query)
        }
    }

    /// Opens the actions menu for the highlighted row.
    func openActionsMenu() {
        guard let target = selectedItem else { return }
        actionsTarget = target
        actionsLibraryTrackID = libraryTrackID(for: target)
        actionsLoved = nil
        actionsMenu = ActionsMenuState(mode: .main, selection: 0, query: "")
        actionsFocusToken = UUID()
        refreshActionsLoved()
    }

    func closeActionsMenu() {
        guard actionsMenu != nil else { return }
        actionsMenu = nil
        actionsTarget = nil
        actionsLibraryTrackID = nil
        actionsLoved = nil
        actionsLovedTask?.cancel()
        actionsLovedTask = nil
        requestFocus()
    }

    /// Esc inside the menu: back from the playlist list, else close.
    func backActionsMenu() {
        guard var menu = actionsMenu else { return }
        if menu.mode == .playlists {
            menu.mode = .main
            menu.query = ""
            menu.selection = 0
            actionsMenu = menu
            actionsFocusToken = UUID()
        } else {
            closeActionsMenu()
        }
    }

    func setActionsQuery(_ query: String) {
        guard var menu = actionsMenu else { return }
        menu.query = query
        menu.selection = 0
        actionsMenu = menu
    }

    func moveActionsSelection(by delta: Int) {
        guard var menu = actionsMenu else { return }
        let count = visibleActionsItems.count
        guard count > 0 else { return }
        menu.selection = min(max(menu.selection + delta, 0), count - 1)
        actionsMenu = menu
    }

    func activateActionsSelection() {
        let items = visibleActionsItems
        guard let menu = actionsMenu, items.indices.contains(menu.selection) else { return }
        runQuickAction(items[menu.selection].action)
    }

    func runQuickAction(_ action: QuickAction) {
        switch action {
        case .primary:
            closeActionsMenu()
            executeSelection()
        case .like:
            setLoved(true)
        case .unlike:
            setLoved(false)
        case .openAddToPlaylist:
            guard actionsLibraryTrackID != nil else { return }
            actionsMenu = ActionsMenuState(mode: .playlists, selection: 0, query: "")
            actionsFocusToken = UUID()
        case .addToPlaylist(let playlistID, let name):
            addToPlaylist(playlistID: playlistID, name: name)
        case .openAlbum:
            // Read the target before closing, which clears it.
            let target = actionsTarget
            closeActionsMenu()
            if case .music(let candidate)? = target {
                openAlbumView(candidate)
            }
        case .openInMusic:
            openInMusic()
        case .dismiss:
            closeActionsMenu()
        }
    }

    private var actionsPlaylists: [MusicCandidate] {
        libraryProvider.playlistSnapshot().filter {
            $0.title != AppleScriptMusicController.albumQueuePlaylistName
        }
    }

    private func refreshActionsLoved() {
        actionsLovedTask?.cancel()
        actionsLovedTask = nil
        guard let id = actionsLibraryTrackID else {
            actionsLoved = nil
            return
        }
        actionsLoved = nil
        actionsLovedTask = Task { [weak self] in
            guard let self else { return }
            let value = try? await self.musicController.isLoved(persistentID: id)
            guard !Task.isCancelled,
                  self.actionsMenu != nil,
                  self.actionsLibraryTrackID == id else { return }
            self.actionsLoved = value
        }
    }

    private func setLoved(_ loved: Bool) {
        guard let id = actionsLibraryTrackID else { return }
        let title = actionsTitle
        let toast = loved ? PlaybackFeedback.liked(title) : PlaybackFeedback.unliked(title)
        closeActionsMenu()
        statusMessage = nil
        Task {
            do {
                try await self.musicController.setLoved(loved, persistentID: id)
                self.onToast?(toast)
            } catch {
                let failure = PlaybackFeedback.failure(error)
                self.statusMessage = failure.message
                self.onToast?(failure)
            }
        }
    }

    private func addToPlaylist(playlistID: String, name: String) {
        guard let trackID = actionsLibraryTrackID else { return }
        let title = actionsTitle
        closeActionsMenu()
        statusMessage = nil
        Task {
            do {
                try await self.musicController.addToPlaylist(
                    trackPersistentID: trackID,
                    playlistPersistentID: playlistID
                )
                self.onToast?(PlaybackFeedback.addedToPlaylist(title, playlist: name))
            } catch {
                let failure = PlaybackFeedback.failure(error)
                self.statusMessage = failure.message
                self.onToast?(failure)
            }
        }
    }

    private func openInMusic() {
        guard let item = actionsTarget else { return }
        let libraryID = actionsLibraryTrackID
        let catalogURL: URL? = {
            guard case .music(let candidate) = item else { return nil }
            return candidate.playbackURL
        }()
        let title = actionsTitle
        closeActionsMenu()
        statusMessage = nil
        Task {
            do {
                if let libraryID {
                    try await self.musicController.revealInMusic(persistentID: libraryID)
                } else if let catalogURL {
                    try await self.musicController.openInMusic(url: catalogURL)
                } else {
                    return
                }
                self.onToast?(PlaybackFeedback.openedInMusic(title))
            } catch {
                let failure = PlaybackFeedback.failure(error)
                self.statusMessage = failure.message
                self.onToast?(failure)
            }
        }
    }

    /// The library track a row maps to, for Like / Add to Playlist.
    private func libraryTrackID(for item: PaletteItem) -> String? {
        switch item {
        case .nowPlaying(let track):
            return track.persistentID
        case .recent(let track):
            return track.candidate.persistentID
        case .music(let candidate):
            if candidate.source == .library, candidate.kind == .song {
                return candidate.persistentID
            }
            if candidate.source == .catalog {
                return LibraryResolver.resolve(candidate, in: libraryProvider.snapshot())?.persistentID
            }
            return nil
        case .command:
            return nil
        }
    }

    static func title(for item: PaletteItem?) -> String {
        guard let item else { return "" }
        switch item {
        case .nowPlaying(let track): return track.title
        case .command(let entry): return entry.title
        case .music(let candidate): return candidate.title
        case .recent(let track): return track.candidate.title
        }
    }

    static func subtitle(for item: PaletteItem?) -> String {
        guard let item else { return "" }
        switch item {
        case .nowPlaying(let track): return track.subtitle
        case .command(let entry): return entry.subtitle
        case .music(let candidate): return candidate.subtitle
        case .recent(let track): return track.candidate.subtitle
        }
    }

    // MARK: - Settings

    func openSettings() {
        screen = .settings
        settingsSelection = 0
        isRecordingHotKey = false
        settingsMessage = nil
    }

    func closeSettings() {
        screen = .search
        isRecordingHotKey = false
        settingsMessage = nil
        focusToken = UUID()
    }

    func beginHotKeyRecording() {
        isRecordingHotKey = true
        settingsMessage = nil
    }

    func cancelHotKeyRecording() {
        isRecordingHotKey = false
        settingsMessage = nil
    }

    func captureHotKey(_ preference: HotKeyPreference) {
        guard preference.hasRequiredModifier else {
            settingsMessage = "Include at least one of ⌘, ⌥ or ⌃."
            return
        }
        guard onHotKeyChange?(preference) ?? false else {
            settingsMessage = "That shortcut is already in use."
            return
        }
        hotKey = preference
        isRecordingHotKey = false
        settingsMessage = nil
    }

    func resetHotKey() {
        let preference = HotKeyPreference.default
        guard onHotKeyChange?(preference) ?? false else {
            settingsMessage = "Couldn't restore the default shortcut."
            return
        }
        hotKey = preference
        isRecordingHotKey = false
        settingsMessage = nil
    }

    // MARK: - Onboarding

    /// Number of indexed library tracks (for the onboarding summary).
    var libraryTrackCount: Int { libraryProvider.count }
    /// Number of indexed library playlists.
    var libraryPlaylistCount: Int { libraryProvider.playlistCount }

    func startOnboarding() {
        screen = .onboarding
        onboardingStep = .welcome
        automationGranted = nil
        isRecordingHotKey = false
        settingsMessage = nil
        requestFocus()
    }

    func advanceOnboarding() {
        switch onboardingStep {
        case .welcome:
            onboardingStep = .permission
            Task { await self.refreshAutomationPermission() }
        case .permission:
            onboardingStep = .ready
        case .ready:
            completeOnboarding()
        }
    }

    func goBackOnboarding() {
        switch onboardingStep {
        case .welcome:
            break
        case .permission:
            onboardingStep = .welcome
        case .ready:
            onboardingStep = .permission
        }
    }

    /// Finishes onboarding and drops into the normal empty search state.
    func completeOnboarding() {
        onOnboardingComplete?()
        screen = .search
        query = ""
        scope = nil
        queryChanged()
        requestFocus()
    }

    /// Runs the permission probe (raises the system prompt on first use).
    func grantAutomationPermission() {
        Task { await self.refreshAutomationPermission() }
    }

    func openAutomationSettings() {
        onOpenAutomationSettings?()
    }

    private func refreshAutomationPermission() async {
        automationGranted = await musicController.checkAutomationPermission()
    }

    // MARK: - Internals

    private func rebuildItems() {
        // While a search is in flight the previous rows stay frozen; the results
        // sink rebuilds once the new query's rows land.
        guard !isSearchPending else { return }
        let newItems = PaletteListComposer.compose(
            query: query,
            // Browse mode is albums/playlists/artists only — no now-playing row.
            nowPlaying: (browsePreference == nil && scope != .themes && artistFocus == nil
                && albumFocus == nil) ? nowPlaying : nil,
            commands: commands,
            music: music,
            recent: (scope == nil && artistFocus == nil && albumFocus == nil) ? recent : []
        )
        items = newItems
        if newItems.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= newItems.count {
            selectedIndex = newItems.count - 1
        }
        selectionChanged()
    }

    private func run(_ action: PaletteAction, selected: MusicCandidate?, closeOnSuccess: Bool = true) {
        switch action {
        case .openSettings:
            openSettings()
        case .rebuildLibraryIndex:
            rebuildLibraryIndex()
        case .installUpdate:
            installUpdate()
        case .setTheme(let theme):
            setTheme(theme)
        case .setFollowsSelection(let follows):
            setFollowsSelection(follows)
        case .setGlobalColours(let global):
            setUsesGlobalColours(global)
        case .music(let command):
            statusMessage = nil
            Task {
                // Read the current shuffle state so a toggle can report the
                // resulting value (best effort).
                var shuffleBefore: Bool?
                if case .shuffle(.toggle) = command {
                    shuffleBefore = try? await self.musicController.shuffleEnabled()
                }
                do {
                    try await self.executor.execute(command, selected: selected)
                    self.onToast?(PlaybackFeedback.toast(
                        for: command,
                        shuffleBefore: shuffleBefore,
                        selected: selected
                    ))
                    if closeOnSuccess { self.onClose?() }
                } catch {
                    let toast = PlaybackFeedback.failure(error)
                    self.statusMessage = toast.message
                    self.onToast?(toast)
                }
            }
        }
    }

#if DEBUG
    /// Set once a synthetic track is injected, so polls don't replace it.
    private var debugHoldsNowPlaying = false

    /// Development helper: pretend the current track is playing.
    func debugForcePlaying() {
        guard let track = nowPlaying else { return }
        nowPlaying = NowPlayingTrack(
            state: .playing,
            title: track.title,
            artist: track.artist,
            album: track.album,
            persistentID: track.persistentID,
            position: track.position,
            duration: track.duration
        )
        rebuildItems()
    }

    /// Development helper: show a synthetic now-playing card on the default
    /// screen, so it can be captured without Music loaded.
    func debugSetNowPlaying(_ track: NowPlayingTrack) {
        debugHoldsNowPlaying = true
        lastPollDate = Date()
        nowPlaying = track
        rebuildItems()
    }

    /// Development helper: force the accent the now-playing card tints with.
    func debugSetRowAccent(_ palette: AlbumPalette?) {
        rowAccent = palette
    }
#endif
}
