import Foundation
import Combine
import CuebarCore

/// Which screen the palette is showing.
enum PaletteScreen: Equatable {
    case search
    case settings
    case onboarding
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
    /// Active `album`/`playlist` scope (nil = plain search).
    @Published private(set) var scope: RankPreference?
    @Published private(set) var items: [PaletteItem] = []
    @Published private(set) var selectedIndex: Int = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var isSearching = false
    @Published private(set) var isIndexing = false
    /// Changes whenever the panel is shown so the view can refocus the field.
    @Published private(set) var focusToken = UUID()

    // Settings
    @Published private(set) var screen: PaletteScreen = .search
    @Published private(set) var hotKey: HotKeyPreference
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var settingsMessage: String?

    // Onboarding
    @Published private(set) var onboardingStep: OnboardingStep = .welcome
    @Published private(set) var automationGranted: Bool?

    var onClose: (() -> Void)?
    /// Reports playback outcomes as toasts.
    var onToast: ((Toast) -> Void)?
    /// Rebuilds the library index; returns counts, or nil on failure.
    var onRebuildLibraryIndex: (() async -> LibraryIndexSummary?)?
    /// Persists completion of the first-run onboarding.
    var onOnboardingComplete: (() -> Void)?
    /// Opens the Automation section of System Settings.
    var onOpenAutomationSettings: (() -> Void)?
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

    init(
        searchService: SearchService,
        musicController: MusicController,
        libraryProvider: LibrarySearchProvider,
        hotKey: HotKeyPreference = .default
    ) {
        self.searchService = searchService
        self.musicController = musicController
        self.libraryProvider = libraryProvider
        self.hotKey = hotKey
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
        if parsed.preference != .songs {
            scope = parsed.preference
            query = parsed.term
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // A scope is music-only, so command rows are suppressed.
        commands = scope == nil ? CommandCatalog.matches(for: trimmed) : []

        // Songs: only for `play <song>` or free text. A recognised non-play
        // command shows just the command.
        if let term = CommandParser.searchTerm(for: CommandParser.parse(query)), !term.isEmpty {
            searchService.updateQuery(SearchQuery(term: term, preference: scope ?? .songs))
        } else {
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

    /// Refresh the current track from Music.app.
    func refreshNowPlaying() async {
        let track = try? await musicController.nowPlaying()
        guard track != nowPlaying else { return }
        nowPlaying = track
        rebuildItems()
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
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
        case .nowPlaying(let track):
            run(.music(track.isPlaying ? .pause : .resume), selected: nil)
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
            nowPlaying: nowPlaying,
            commands: commands,
            music: music
        )
        items = newItems
        if newItems.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= newItems.count {
            selectedIndex = newItems.count - 1
        }
    }

    private func run(_ action: PaletteAction, selected: MusicCandidate?) {
        switch action {
        case .openSettings:
            openSettings()
        case .rebuildLibraryIndex:
            rebuildLibraryIndex()
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
                    self.onClose?()
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
    /// Development helper: pretend the current track is playing so the waveform
    /// animation can be captured in an offscreen snapshot.
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
#endif
}
