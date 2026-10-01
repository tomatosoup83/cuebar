import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import CuebarCore

/// Owns the palette panel and translates raw key events into model actions.
@MainActor
final class PaletteWindowController {
    static var panelSize: NSSize { PaletteMetrics.panelSize }

    /// Standard editing selectors, forwarded by the key monitor because an
    /// agent app has no Edit menu to dispatch them.
    private static let editingSelectors: [String: String] = [
        "a": "selectAll:",
        "c": "copy:",
        "v": "paste:",
        "x": "cut:"
    ]

    private let panel: PalettePanel
    private let model: PaletteModel
    private let toastController: ToastWindowController
    private let ambientCoordinator = AmbientPaletteCoordinator(
        resolve: { await PaletteCache.shared.palette(for: $0) }
    )
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private weak var previousApplication: NSRunningApplication?
    private var isHiding = false
    /// Set while an AppKit menu is tracking, so the key monitor stands down and
    /// lets the menu handle its own arrows and Return.
    private var isMenuTracking = false
    private var nowPlayingTask: Task<Void, Never>?
    private let playedDatesFetcher = AppleScriptLibraryProvider()

    /// Applies a new hotkey; returns false when the shortcut is unavailable.
    var onHotKeyChange: ((HotKeyPreference) -> Bool)?
    /// Rebuilds the library index; returns counts, or nil on failure.
    var onRebuildLibraryIndex: (() async -> LibraryIndexSummary?)?
    /// Persists completion of the first-run onboarding.
    var onOnboardingComplete: (() -> Void)?
    /// Opens System Settings › Privacy & Security › Automation.
    var onOpenAutomationSettings: (() -> Void)?
    /// Checks GitHub for a newer release.
    var onCheckForUpdates: (() -> Void)?
    /// Downloads and installs the available update.
    var onInstallUpdate: (() -> Void)?
    /// Persists a newly chosen theme.
    var onThemeChange: ((ThemeID) -> Void)?
    /// Persists the "ambient follows the highlighted row" option.
    var onAmbientFollowsSelectionChange: ((Bool) -> Void)?
    /// Called when the What's New screen is presented.
    var onWhatsNewShown: (() -> Void)?

    init(
        searchService: SearchService,
        musicController: MusicController,
        libraryProvider: LibrarySearchProvider,
        hotKey: HotKeyPreference = .default,
        theme: ThemeID = .tahoe,
        ambientFollowsSelection: Bool = false
    ) {
        model = PaletteModel(
            searchService: searchService,
            musicController: musicController,
            libraryProvider: libraryProvider,
            hotKey: hotKey,
            theme: theme,
            ambientFollowsSelection: ambientFollowsSelection
        )

        let rect = NSRect(origin: .zero, size: PaletteMetrics.panelSize)
        panel = PalettePanel(contentRect: rect)
        toastController = ToastWindowController(center: ToastCenter())

        // A borderless window is square. Round the content container itself so
        // the window silhouette (and its shadow) match the glass shape instead
        // of showing a square edge at every corner.
        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.cornerRadius = PaletteMetrics.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: PaletteView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.contentView = container
        panel.setContentSize(PaletteMetrics.panelSize)

        model.onClose = { [weak self] in self?.hide() }
        model.onToast = { [weak self] toast in
            guard let self else { return }
            self.toastController.show(toast, anchoredTo: self.panel.frame)
        }
        model.onHotKeyChange = { [weak self] preference in
            self?.onHotKeyChange?(preference) ?? false
        }
        model.onRebuildLibraryIndex = { [weak self] in
            await self?.onRebuildLibraryIndex?()
        }
        model.onOnboardingComplete = { [weak self] in
            self?.onOnboardingComplete?()
        }
        model.onOpenAutomationSettings = { [weak self] in
            self?.onOpenAutomationSettings?()
        }
        model.onCheckForUpdates = { [weak self] in
            self?.onCheckForUpdates?()
        }
        model.onInstallUpdate = { [weak self] in
            self?.onInstallUpdate?()
        }
        model.onThemeChange = { [weak self] theme in
            guard let self else { return }
            self.onThemeChange?(theme)
            self.ambientCoordinator.setEnabled(theme == .albumArt)
        }
        model.onAmbientFollowsSelectionChange = { [weak self] follows in
            guard let self else { return }
            self.onAmbientFollowsSelectionChange?(follows)
            self.ambientCoordinator.setFollowsSelection(follows)
        }
        model.onSelectionChange = { [weak self] item in
            self?.ambientCoordinator.update(selection: item)
        }
        model.onFetchPlayedDates = { [playedDatesFetcher] in
            try? await playedDatesFetcher.fetchPlayedDates()
        }
        model.onOpenThemeMenu = { [weak self] in self?.showThemeMenu() }
        model.onWhatsNewShown = { [weak self] in self?.onWhatsNewShown?() }
        ambientCoordinator.setEnabled(theme == .albumArt)
        ambientCoordinator.setFollowsSelection(ambientFollowsSelection)
        ambientCoordinator.$palette
            .sink { [weak self] palette in
                self?.model.setAmbientPalette(palette)
            }
            .store(in: &cancellables)
        toastController.themeProvider = { [weak self] in
            guard let self else { return (.tahoe, nil) }
            return (self.model.theme, self.ambientCoordinator.palette)
        }

        installKeyMonitor()
        observeResignKey()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        positionOnActiveScreen()
        model.reset()
        // Populate the empty state on open (commands + now playing), so it
        // matches what appears after deleting typed text.
        model.queryChanged()

        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        // The glass is drawn asynchronously; recompute the rounded shadow once
        // the content has rendered.
        DispatchQueue.main.async { [weak self] in
            self?.panel.invalidateShadow()
        }
        model.requestFocus()
        startNowPlayingPolling()
    }

    /// Shows the palette on the first-run onboarding screen.
    func showOnboarding() {
        show()
        model.startOnboarding()
    }

    /// Shows a toast from outside the model (e.g. the update controller).
    func presentToast(_ toast: Toast) {
        toastController.show(toast, anchoredTo: panel.isVisible ? panel.frame : nil)
    }

    /// Reflects update availability in the palette.
    func setAvailableUpdate(_ update: UpdateInfo?) {
        model.setAvailableUpdate(update)
    }

    func hide() {
        guard !isHiding else { return }
        isHiding = true
        defer { isHiding = false }

        stopNowPlayingPolling()
        panel.orderOut(nil)
        model.reset()

        // Return focus to whatever the user was doing.
        previousApplication?.activate()
        previousApplication = nil
    }

    // MARK: - Now playing

    private func startNowPlayingPolling() {
        stopNowPlayingPolling()
        nowPlayingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNowPlaying()
            // After the card, so the hero paints first; the shelf from the last
            // opening shows in the meantime.
            self.model.refreshRecentlyPlayed()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { break }
                await self.refreshNowPlaying()
            }
        }
    }

    /// Refreshes the now-playing card and the ambient album palette together.
    private func refreshNowPlaying() async {
        await model.refreshNowPlaying()
        ambientCoordinator.update(nowPlaying: model.currentTrack)
    }

    private func stopNowPlayingPolling() {
        nowPlayingTask?.cancel()
        nowPlayingTask = nil
    }

    /// Shows What's New (from the launch check or Settings).
    func showWhatsNew() {
        show()
        model.startWhatsNew()
    }

    /// Pops the Theme dropdown at the Theme row.
    ///
    /// An `NSMenu` rather than a SwiftUI control: inside a borderless,
    /// non-activating panel it is the only thing that gives real dropdown
    /// behaviour — arrows to move, Return to choose, Esc to cancel.
    private func showThemeMenu() {
        guard let container = panel.contentView else { return }
        let rect = model.themeRowFrame

        let menu = NSMenu()
        for theme in ThemeID.allCases {
            let item = NSMenuItem(
                title: theme.title,
                action: #selector(selectThemeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            item.state = theme == model.theme ? .on : .off
            menu.addItem(item)
        }

        // SwiftUI's coordinate space shares the hosting view, so only the y axis
        // needs flipping into AppKit's bottom-left origin. Point at the row's
        // bottom edge so the menu drops below it.
        let point = NSPoint(x: rect.minX, y: container.bounds.height - rect.maxY)

        isMenuTracking = true
        menu.popUp(positioning: nil, at: point, in: container)
        isMenuTracking = false
    }

    @objc private func selectThemeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = ThemeID(rawValue: raw) else { return }
        model.setTheme(theme)
    }

#if DEBUG
    /// Development helper: drive a query into the palette.
    func debugSetQuery(_ query: String) {
        model.query = query
        model.queryChanged()
    }

    /// Development helper: pretend the current track is playing.
    func debugForcePlaying() {
        model.debugForcePlaying()
    }

    /// Development helper: jump straight to the settings screen.
    func debugOpenSettings(recording: Bool = false) {
        model.openSettings()
        if recording {
            model.beginHotKeyRecording()
        }
    }

    /// Development helper: jump straight to the onboarding screen.
    func debugOpenOnboarding() {
        model.startOnboarding()
    }

    /// Development helper: select a theme.
    ///
    /// The ambient palette is no longer forced here — `AmbientPaletteCoordinator`
    /// resolves it from real artwork, so forcing it would mask the real behaviour.
    func debugSetTheme(_ theme: ThemeID) {
        model.setTheme(theme)
    }

    private static func describe(_ color: ThemeColor) -> String {
        String(
            format: "rgb(%.2f,%.2f,%.2f) luma %.2f bright %.2f chroma %.2f",
            color.red, color.green, color.blue, color.luma, color.brightness, color.chroma
        )
    }

    /// Development helper: render the now-playing card on the default screen,
    /// with a real-looking accent, without Music loaded.
    func debugShowFakeNowPlaying() {
        model.debugSetNowPlaying(
            NowPlayingTrack(
                state: .playing,
                title: "IGOR'S THEME",
                artist: "Tyler, The Creator",
                album: "IGOR",
                persistentID: "FAKE",
                position: 42,
                duration: 187
            )
        )
        Task { [weak self] in
            // Wait out the real (empty) accent resolution, then force one.
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.model.debugSetRowAccent(
                AlbumPalette(
                    top: ThemeColor(red: 0.84, green: 0.63, blue: 0.69),
                    bottom: ThemeColor(red: 0.81, green: 0.65, blue: 0.70),
                    accent: ThemeColor(red: 0.96, green: 0.68, blue: 0.77),
                    selection: ThemeColor(red: 0.82, green: 0.32, blue: 0.47)
                )
            )
        }
    }

    /// Development helper: turn the "ambient follows the highlighted row" option
    /// on or off.
    func debugSetFollowsSelection(_ follows: Bool) {
        model.setFollowsSelection(follows)
    }

    /// Development helper: step the selection rapidly then stop, and report whether
    /// the ambient colour ended up on the row that is actually selected. This is
    /// the deterministic reproduction of "cycle fast, stop, and the colour doesn't
    /// catch up / belongs to the wrong album".
    func debugCycleTest(steps: Int, stepMilliseconds: Int) {
        Task { [weak self] in
            guard let self else { return }
            // Let the results settle first.
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            for _ in 0 ..< steps {
                self.model.moveSelection(by: 1)
                try? await Task.sleep(
                    nanoseconds: UInt64(stepMilliseconds) * 1_000_000
                )
            }

            // Stopped moving: give it a generous moment to settle (a cold album's
            // artwork lookup scans the whole library), then check.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let wanted = self.model.selectedItem?.artworkSource?.cacheKey ?? "-"
            let shown = self.ambientCoordinator.debugPublishedKey ?? "-"
            let desired = self.ambientCoordinator.debugDesiredKey ?? "-"
            NSLog("Cuebar: cycle test steps=\(steps) stepMs=\(stepMilliseconds) "
                  + "end=\((self.model.selectedItem?.id) ?? "-") "
                  + "wanted=\(wanted) desired=\(desired) shown=\(shown) "
                  + "match=\(wanted == shown)")
        }
    }

    /// Development helper: log the extracted palettes for the first few album
    /// rows, so the tuning can be judged across a spread of real covers.
    func debugDumpPalettes(count: Int = 10) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            var logged = 0
            for item in self.model.items {
                guard logged < count,
                      case .music(let candidate) = item,
                      candidate.kind == .album,
                      let source = item.artworkSource else { continue }
                guard let palette = await PaletteCache.shared.palette(for: source) else { continue }
                NSLog("Cuebar: dump album=\"\(candidate.title)\" usable=\(palette.isUsable) "
                      + "top=\(Self.describe(palette.top)) accent=\(Self.describe(palette.accent))")
                logged += 1
            }
            NSLog("Cuebar: dumped \(logged) album palettes")
        }
    }

    /// Development helper: render the panel's content view to a PNG.
    ///
    /// Offscreen AppKit rendering, so it does not require Screen Recording
    /// permission. Backdrop-based glass materials may not appear in the
    /// captured image, but layout, text and rows do.
    func debugSnapshot(to path: String) {
        guard
            let view = panel.contentView,
            view.bounds.width > 0,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            NSLog("Cuebar: snapshot failed to set up")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            NSLog("Cuebar: snapshot PNG encoding failed")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("Cuebar: snapshot write failed: \(error)")
        }
    }
#endif

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.midY - size.height / 2 + visibleFrame.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            // An open dropdown owns the keyboard.
            guard !self.isMenuTracking else { return event }

            // Recording a new hotkey: capture the next key combination.
            if self.model.isRecordingHotKey {
                if Int(event.keyCode) == kVK_Escape {
                    self.model.cancelHotKeyRecording()
                } else {
                    self.model.captureHotKey(KeyEventTranslator.preference(from: event))
                }
                return nil
            }

            // Settings: move between rows like the results list, ⏎ runs the row.
            if self.model.screen == .settings {
                switch Int(event.keyCode) {
                case kVK_Escape:
                    self.model.closeSettings()
                    return nil
                case kVK_UpArrow:
                    self.model.moveSettingsSelection(by: -1)
                    return nil
                case kVK_DownArrow:
                    self.model.moveSettingsSelection(by: 1)
                    return nil
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    self.model.activateSettingsRow()
                    return nil
                default:
                    return event
                }
            }

            // What's New: any dismiss key closes it.
            if self.model.screen == .whatsNew {
                switch Int(event.keyCode) {
                case kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter:
                    self.model.closeWhatsNew()
                    return nil
                case kVK_UpArrow, kVK_DownArrow:
                    return nil
                default:
                    return event
                }
            }

            // Onboarding: advance / back / skip.
            if self.model.screen == .onboarding {
                switch Int(event.keyCode) {
                case kVK_Return, kVK_ANSI_KeypadEnter, kVK_RightArrow:
                    self.model.advanceOnboarding()
                    return nil
                case kVK_LeftArrow:
                    self.model.goBackOnboarding()
                    return nil
                case kVK_Escape:
                    self.model.completeOnboarding()
                    return nil
                default:
                    return event
                }
            }

            // ⌘, opens settings from the search screen.
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "," {
                self.model.openSettings()
                return nil
            }

            // Standard editing shortcuts. An agent app has no Edit menu, so
            // AppKit never dispatches these; forward them to the field editor.
            if event.modifierFlags.contains(.command),
               let key = event.charactersIgnoringModifiers?.lowercased() {
                if let action = Self.editingSelectors[key],
                   NSApp.sendAction(NSSelectorFromString(action), to: nil, from: nil) {
                    return nil
                }
                if key == "z" {
                    if event.modifierFlags.contains(.shift) {
                        self.panel.undoManager?.redo()
                    } else {
                        self.panel.undoManager?.undo()
                    }
                    return nil
                }
            }

            // Backspace on an empty field clears an active scope chip.
            if self.model.scope != nil, self.model.query.isEmpty,
               Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete {
                self.model.clearScope()
                return nil
            }

            switch Int(event.keyCode) {
            case kVK_DownArrow:
                self.model.moveSelection(by: 1)
                return nil
            case kVK_UpArrow:
                self.model.moveSelection(by: -1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.model.executeSelection()
                return nil
            case kVK_Escape:
                if self.model.scope != nil {
                    self.model.clearScope()
                } else {
                    self.hide()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func observeResignKey() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, !self.isHiding else { return }
                self.hide()
            }
        }
    }
}
