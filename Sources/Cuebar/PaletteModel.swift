import Foundation
import Combine
import CuebarCore

/// Which screen the palette is showing.
enum PaletteScreen: Equatable {
    case search
    case settings
}

/// Presentation state for the palette.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var query: String = ""
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

    var onClose: (() -> Void)?
    /// Applies a new hotkey; returns false when the shortcut is unavailable.
    var onHotKeyChange: ((HotKeyPreference) -> Bool)?

    private let searchService: SearchService
    private let musicController: MusicController
    private let executor: CommandExecutor
    private var cancellables = Set<AnyCancellable>()

    private var commands: [CommandEntry] = []
    private var music: [MusicCandidate] = []
    private var nowPlaying: NowPlayingTrack?

    init(
        searchService: SearchService,
        musicController: MusicController,
        hotKey: HotKeyPreference = .default
    ) {
        self.searchService = searchService
        self.musicController = musicController
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Commands: typed text that partially matches a command name, or all
        // commands when the box is empty.
        commands = CommandCatalog.matches(for: trimmed)

        // Songs: only for `play <song>` or free text. A recognised non-play
        // command shows just the command.
        if let term = CommandParser.searchTerm(for: CommandParser.parse(query)), !term.isEmpty {
            searchService.updateQuery(term)
        } else {
            searchService.clear()
            music = []
        }

        rebuildItems()
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
            run(.music(.play(query: candidate.title)), selected: candidate)
        }
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
        case .music(let command):
            statusMessage = nil
            Task {
                do {
                    try await self.executor.execute(command, selected: selected)
                    self.onClose?()
                } catch {
                    self.statusMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
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
