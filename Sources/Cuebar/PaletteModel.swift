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
        theme: ThemeID = .tahoe,
        ambientFollowsSelection: Bool = false
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
                self.rebuildItems()
            }
            .store(in: &cancellables)

        searchService.$statusMessage
            .sink { [weak self] in self?.statusMessage = $0 }
            .store(in: &cancellables)

        searchService.$isSearching
            .sink { [weak self] in self?.isSearching = $0 }
            .store(in: &cancellables)

        searchService.$isIndexing
            .sink { [weak self] in self?.isIndexing = $0 }
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

        // A music scope is songs-only, so command rows are suppressed.
        commands = scope == nil ? commandEntries(for: trimmed) : []

        // Songs: only for `play <song>` or free text. A recognised non-play
        // command shows just the command. An empty scope browses that kind.
        if let term = CommandParser.searchTerm(for: CommandParser.parse(query)), !term.isEmpty {
            browsePreference = nil
            searchService.updateQuery(SearchQuery(term: term, preference: scope?.rankPreference ?? .songs))
        } else if let browse = scope?.rankPreference {
            if browsePreference != browse {
                browsePreference = browse
                selectedIndex = 0
                searchService.browse(browse)
            }
        } else {
            browsePreference = nil
            searchService.clear()
            music = []
        }

        rebuildItems()
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
        lastPollDate = Date()
        guard track != nowPlaying else { return }
        nowPlaying = track
        rebuildItems()
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
        let newItems = PaletteListComposer.compose(
            query: query,
            // Browse mode is albums/playlists only — no now-playing row.
            nowPlaying: (browsePreference == nil && scope != .themes) ? nowPlaying : nil,
            commands: commands,
            music: music
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
        nowPlaying = track
        rebuildItems()
    }

    /// Development helper: force the accent the now-playing card tints with.
    func debugSetRowAccent(_ palette: AlbumPalette?) {
        rowAccent = palette
    }
#endif
}
