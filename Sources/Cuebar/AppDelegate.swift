import AppKit
import Combine
import CuebarCore

/// Owns the long-lived app services: hotkey, status item, palette and the
/// library index.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var paletteController: PaletteWindowController?

    private let hotKeyManager = HotKeyManager()
    private let hotKeyStore = HotKeyStore()
    private let onboardingStore = OnboardingStore()
    private let themeStore = ThemeStore()
    private let whatsNewStore = WhatsNewStore()
    private let updateController = UpdateController()
    private var cancellables = Set<AnyCancellable>()
    private let libraryProvider = LibrarySearchProvider()
    private let indexStore = LibraryIndexStore()
    private let libraryFetcher = AppleScriptLibraryProvider()
    private let musicController = AppleScriptMusicController()
    private let playHistory = PlayHistory.standard()
    private var playerObserver: NSObjectProtocol?
    private var searchService: SearchService?

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        // For verifying the theming against a dark appearance.
        if ProcessInfo.processInfo.environment["CUEBAR_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
#endif
        let searchService = SearchService(
            libraryProvider: libraryProvider,
            catalogProvider: ITunesCatalogProvider()
        )
        self.searchService = searchService

        let preference = hotKeyStore.load()

        // Upgraders carry their old theme in UserDefaults; move them onto the new
        // Album Art default once, before the palette reads it.
        themeStore.applyAlbumArtDefaultIfNeeded()

        let controller = PaletteWindowController(
            searchService: searchService,
            musicController: musicController,
            libraryProvider: libraryProvider,
            hotKey: preference,
            theme: themeStore.theme,
            ambientFollowsSelection: themeStore.ambientFollowsSelection
        )
        controller.onHotKeyChange = { [weak self] newPreference in
            self?.applyHotKey(newPreference) ?? false
        }
        controller.onRebuildLibraryIndex = { [weak self] in
            await self?.refreshLibraryIndex()
        }
        controller.onOnboardingComplete = { [weak self] in
            self?.onboardingStore.complete()
        }
        controller.onOpenAutomationSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
        controller.onCheckForUpdates = { [weak self] in
            self?.updateController.check()
        }
        controller.onInstallUpdate = { [weak self] in
            self?.updateController.install()
        }
        controller.onThemeChange = { [weak self] theme in
            self?.themeStore.theme = theme
        }
        controller.onWhatsNewShown = { [weak self] in
            self?.whatsNewStore.lastSeenVersion = AppVersion.current()?.description
        }
        controller.onAmbientFollowsSelectionChange = { [weak self] follows in
            self?.themeStore.ambientFollowsSelection = follows
        }
        updateController.onToast = { [weak self] toast in
            self?.paletteController?.presentToast(toast)
        }
        updateController.$availableUpdate
            .sink { [weak self] update in
                self?.paletteController?.setAvailableUpdate(update)
            }
            .store(in: &cancellables)
        paletteController = controller
        controller.setPlayHistory(playHistory)
        observeMusicPlayer()

        hotKeyManager.onHotKey = { [weak self] in self?.paletteController?.toggle() }
        if !hotKeyManager.register(preference) {
            NSLog("Cuebar: could not register \(preference.displayString) (another app may own it).")
        }

        configureStatusItem()
        loadLibrary()

#if DEBUG
        if ProcessInfo.processInfo.environment["CUEBAR_TOAST_TEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.debugToastTransitionTest()
            }
        }
#endif

        // First run: walk the user through opening Cuebar and granting access.
        if !onboardingStore.hasCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.paletteController?.showOnboarding()
            }
        }

        // An upgrade (not a fresh install — onboarding tells them apart) shows
        // what changed since the version they were running.
        announceWhatsNewIfNeeded()

        // Quiet update check a few seconds in (only when enabled).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.updateController.checkIfEnabled()
        }

#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        // Set before anything renders: the wash strength is a plain static.
        if let raw = environment["CUEBAR_WASH_OPACITY"], let value = Double(raw) {
            ThemeBackground.washOpacity = value
        }
        if let raw = environment["CUEBAR_GLASS_TINT"], let value = Double(raw) {
            ThemeGlass.tintOpacity = value
        }
        if let raw = environment["CUEBAR_ROW_TINT"], let value = Double(raw) {
            ThemeGlass.rowTintOpacity = value
        }
        if let raw = environment["CUEBAR_DARK_COVER"], raw == "1" {
            PaletteExtractor.debugForceDarkPanel = true
        }
        if environment["CUEBAR_ONBOARD"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.paletteController?.showOnboarding()
            }
        }
        if environment["CUEBAR_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.paletteController?.show()
                if let query = environment["CUEBAR_PREVIEW_QUERY"] {
                    self.paletteController?.debugSetQuery(query)
                }
                if let settings = environment["CUEBAR_OPEN_SETTINGS"] {
                    if settings == "onboarding" {
                        self.paletteController?.debugOpenOnboarding()
                    } else {
                        self.paletteController?.debugOpenSettings(recording: settings == "recording")
                    }
                }
                if environment["CUEBAR_FORCE_PLAYING"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.paletteController?.debugForcePlaying()
                    }
                }
                if let theme = environment["CUEBAR_THEME"] {
                    self.paletteController?.debugSetTheme(theme == "albumart" ? .albumArt : .tahoe)
                }
                if let count = environment["CUEBAR_DUMP_PALETTES"], let value = Int(count) {
                    self.paletteController?.debugDumpPalettes(count: value)
                }
                if environment["CUEBAR_FAKE_NOWPLAYING"] == "1" {
                    self.paletteController?.debugShowFakeNowPlaying()
                }
                if let actions = environment["CUEBAR_OPEN_ACTIONS"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        if actions == "playlists" {
                            self?.paletteController?.debugOpenActionsPlaylists()
                        } else {
                            self?.paletteController?.debugOpenActionsMenu()
                        }
                    }
                }
                if let raw = environment["CUEBAR_FOLLOW_SELECTION"] {
                    self.paletteController?.debugSetFollowsSelection(raw == "1")
                }
                if let raw = environment["CUEBAR_CYCLE_TEST"], let stepMs = Int(raw) {
                    self.paletteController?.debugCycleTest(steps: 10, stepMilliseconds: stepMs)
                }
                if let path = environment["CUEBAR_SNAPSHOT"] {
                    let delay = environment["CUEBAR_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 1.2
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.paletteController?.debugSnapshot(to: path)
                        NSLog("Cuebar: wrote snapshot to \(path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing to flush; the index is written after each rebuild.
    }

    // MARK: - Library index

    /// Shows What's New once per version, to people who were already using Cuebar.
    private func announceWhatsNewIfNeeded() {
        guard onboardingStore.hasCompleted,
              let version = AppVersion.current()?.description,
              whatsNewStore.shouldShow(for: version),
              !WhatsNew.highlights(for: version).isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.paletteController?.showWhatsNew()
        }
    }

    /// Logs every track Music starts playing — whether or not Cuebar started it
    /// and whether or not the palette is open — for the Recently Played shelf.
    private func observeMusicPlayer() {
        playerObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(PlayerInfoEvent.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = PlayerInfoEvent.parse(notification.userInfo) else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.playHistory.record(event)
                self.paletteController?.playerChanged(event)
            }
        }
    }

#if DEBUG
    /// Development helper: fire a long then a short toast back-to-back, to check
    /// the swap is never visible. Titles come from `CUEBAR_TOAST_LONG` /
    /// `CUEBAR_TOAST_SHORT` so the real pair can be reproduced.
    func debugToastTransitionTest() {
        let environment = ProcessInfo.processInfo.environment
        let long = environment["CUEBAR_TOAST_LONG"]
            ?? "SWEET / I THOUGHT YOU WANTED TO DANCE (feat. Brent Faiyaz & Fana Hues)"
        let short = environment["CUEBAR_TOAST_SHORT"] ?? "Pier 4"
        let gap = environment["CUEBAR_TOAST_GAP"].flatMap(Double.init) ?? 1.2

        paletteController?.presentToast(
            Toast(kind: .success, message: "Playing “\(long)”", detail: "Tyler, The Creator · CALL ME IF YOU GET LOST")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
            self?.paletteController?.presentToast(
                Toast(kind: .success, message: "Playing “\(short)”", detail: "Clairo · Charm")
            )
        }
    }
#endif

    private func loadLibrary() {
        if let cached = indexStore.loadCached() {
            libraryProvider.setIndex(cached.tracks, playlists: cached.playlists)
            NSLog("Cuebar: loaded \(cached.tracks.count) cached tracks, \(cached.playlists.count) playlists.")
        }
        Task { await refreshLibraryIndex() }
    }

    @discardableResult
    private func refreshLibraryIndex() async -> LibraryIndexSummary? {
        searchService?.isIndexing = true
        defer { searchService?.isIndexing = false }

        do {
            let tracks = try await libraryFetcher.fetchLibrary()
            let playlists = (try? await libraryFetcher.fetchPlaylists()) ?? []
            libraryProvider.setIndex(tracks, playlists: playlists)
            indexStore.save(LibraryIndex(tracks: tracks, playlists: playlists))
            NSLog("Cuebar: indexed \(tracks.count) library tracks, \(playlists.count) playlists.")
            return LibraryIndexSummary(trackCount: tracks.count, playlistCount: playlists.count)
        } catch {
            NSLog("Cuebar: library indexing failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Cuebar"
        )

        let menu = NSMenu()
        menu.addItem(makeItem("Open Cuebar", action: #selector(openPalette)))
        menu.addItem(.separator())
        let quit = makeItem("Quit Cuebar", action: #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openPalette() {
        paletteController?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Registers and persists a new launch hotkey.
    private func applyHotKey(_ preference: HotKeyPreference) -> Bool {
        guard hotKeyManager.register(preference) else { return false }
        hotKeyStore.save(preference)
        return true
    }
}
