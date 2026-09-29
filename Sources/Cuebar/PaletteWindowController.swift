import AppKit
import Carbon.HIToolbox
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
    private var keyMonitor: Any?
    private weak var previousApplication: NSRunningApplication?
    private var isHiding = false
    private var nowPlayingTask: Task<Void, Never>?

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

    init(
        searchService: SearchService,
        musicController: MusicController,
        libraryProvider: LibrarySearchProvider,
        hotKey: HotKeyPreference = .default
    ) {
        model = PaletteModel(
            searchService: searchService,
            musicController: musicController,
            libraryProvider: libraryProvider,
            hotKey: hotKey
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
            await self.model.refreshNowPlaying()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { break }
                await self.model.refreshNowPlaying()
            }
        }
    }

    private func stopNowPlayingPolling() {
        nowPlayingTask?.cancel()
        nowPlayingTask = nil
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

            // Recording a new hotkey: capture the next key combination.
            if self.model.isRecordingHotKey {
                if Int(event.keyCode) == kVK_Escape {
                    self.model.cancelHotKeyRecording()
                } else {
                    self.model.captureHotKey(KeyEventTranslator.preference(from: event))
                }
                return nil
            }

            // Settings screen: back and record only.
            if self.model.screen == .settings {
                switch Int(event.keyCode) {
                case kVK_Escape:
                    self.model.closeSettings()
                    return nil
                case kVK_Return, kVK_ANSI_KeypadEnter:
                    self.model.beginHotKeyRecording()
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
