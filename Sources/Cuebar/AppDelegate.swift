import AppKit
import CuebarCore

/// Owns the long-lived app services: hotkey, status item, palette and the
/// library index.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var paletteController: PaletteWindowController?

    private let hotKeyManager = HotKeyManager()
    private let hotKeyStore = HotKeyStore()
    private let libraryProvider = LibrarySearchProvider()
    private let indexStore = LibraryIndexStore()
    private let libraryFetcher = AppleScriptLibraryProvider()
    private let musicController = AppleScriptMusicController()
    private var searchService: SearchService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let searchService = SearchService(
            libraryProvider: libraryProvider,
            catalogProvider: ITunesCatalogProvider()
        )
        self.searchService = searchService

        let preference = hotKeyStore.load()

        let controller = PaletteWindowController(
            searchService: searchService,
            musicController: musicController,
            hotKey: preference
        )
        controller.onHotKeyChange = { [weak self] newPreference in
            self?.applyHotKey(newPreference) ?? false
        }
        paletteController = controller

        hotKeyManager.onHotKey = { [weak self] in self?.paletteController?.toggle() }
        if !hotKeyManager.register(preference) {
            NSLog("Cuebar: could not register \(preference.displayString) (another app may own it).")
        }

        configureStatusItem()
        loadLibrary()

#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CUEBAR_SHOW_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.paletteController?.show()
                if let query = environment["CUEBAR_PREVIEW_QUERY"] {
                    self.paletteController?.debugSetQuery(query)
                }
                if let settings = environment["CUEBAR_OPEN_SETTINGS"] {
                    self.paletteController?.debugOpenSettings(recording: settings == "recording")
                }
                if environment["CUEBAR_FORCE_PLAYING"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.paletteController?.debugForcePlaying()
                    }
                }
                if let path = environment["CUEBAR_SNAPSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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

    private func loadLibrary() {
        if let cached = indexStore.loadCached() {
            libraryProvider.setIndex(cached.tracks)
            NSLog("Cuebar: loaded \(cached.tracks.count) cached tracks.")
        }
        Task { await refreshLibraryIndex() }
    }

    private func refreshLibraryIndex() async {
        searchService?.isIndexing = true
        defer { searchService?.isIndexing = false }

        do {
            let tracks = try await libraryFetcher.fetchLibrary()
            libraryProvider.setIndex(tracks)
            indexStore.save(LibraryIndex(tracks: tracks))
            NSLog("Cuebar: indexed \(tracks.count) library tracks.")
        } catch {
            NSLog("Cuebar: library indexing failed: \(error.localizedDescription)")
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
        menu.addItem(makeItem("Rebuild Library Index", action: #selector(rebuildIndex)))
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

    @objc private func rebuildIndex() {
        Task { await refreshLibraryIndex() }
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
