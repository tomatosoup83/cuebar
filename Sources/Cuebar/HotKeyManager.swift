import AppKit
import Carbon.HIToolbox
import CuebarCore

/// Registers a system-wide hotkey using the Carbon Hot Key API.
///
/// This does not require Accessibility permission, unlike
/// `NSEvent.addGlobalMonitorForEvents`.
final class HotKeyManager {
    /// 'CUBR'
    private static let signature: OSType = 0x4355_4252

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Invoked on the main thread when the hotkey is pressed.
    var onHotKey: (() -> Void)?

    deinit {
        unregisterHotKey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers `preference`, replacing any previously registered hotkey.
    /// Returns false when the combination is already taken by another app.
    @discardableResult
    func register(_ preference: HotKeyPreference) -> Bool {
        installHandlerIfNeeded()
        unregisterHotKey()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preference.keyCode,
            preference.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotKey?() }
                return noErr
            },
            1,
            &eventType,
            context,
            &handlerRef
        )
    }
}
