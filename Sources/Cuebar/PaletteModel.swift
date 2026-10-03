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
        ambientFollowsSelection: Bool = true
    ) {
        self.searchService = searchService
        self.musicController = musicController
        self.libraryProvider = libraryProvider
        self.hotKey = hotKey
        self.theme = theme
        self.ambientFollowsSelection = ambientFollowsSelection
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
                filter: trimmed
            )
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

        guard theme == .albumArt, let source = selectedItem?.artworkSource else {
            rowAccent = nil
            return
        }

        if let cached = PaletteCache.shared.cached(for: source) {
            rowAccent = cached.isUsable ? cached : nil
            return
        }

        rowAccent = nil
        accentTask = Task { [weak self] in
            let palette = await PaletteCache.shared.palette(for: source)
            guard !Task.isCancelled, let self else { return }
            guard self.selectedItem?.artworkSource == source else { return }
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
                followsSelection: ambientFollowsSelection
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
        if screen == .search, scope == nil,
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
            // Browse mode is albums/playlists only — no now-playing row.
            nowPlaying: (browsePreference == nil && scope != .themes) ? nowPlaying : nil,
            commands: commands,
            music: music,
            recent: scope == nil ? recent : []
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
                    self.onToast?(self.successToast(
                        for: command,
                        selected: selected,
                        shuffleBefore: shuffleBefore
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

    private func successToast(
        for command: Command,
        selected: MusicCandidate?,
        shuffleBefore: Bool?
    ) -> Toast {
        switch command {
        case .play(let term):
            if !term.isEmpty, let selected { return PlaybackFeedback.playing(selected) }
            return PlaybackFeedback.resumed()
        case .pause:
            return PlaybackFeedback.paused()
        case .resume:
            return PlaybackFeedback.resumed()
        case .next:
            return PlaybackFeedback.nextTrack()
        case .previous:
            return PlaybackFeedback.previousTrack()
        case .shuffle(let action):
            switch action {
            case .on: return PlaybackFeedback.shuffle(true)
            case .off: return PlaybackFeedback.shuffle(false)
            case .toggle:
                if let shuffleBefore { return PlaybackFeedback.shuffle(!shuffleBefore) }
                return PlaybackFeedback.shuffleToggled()
            }
        case .setRepeat(let mode):
            return PlaybackFeedback.repeatMode(mode)
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
