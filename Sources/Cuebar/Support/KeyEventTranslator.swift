import AppKit
import CuebarCore
import Carbon.HIToolbox

/// Turns a recorded key event into a `HotKeyPreference`.
enum KeyEventTranslator {
    static func preference(from event: NSEvent) -> HotKeyPreference {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        return HotKeyPreference(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            displayString: HotKeyFormatter.modifierSymbols(modifiers) + keyLabel(for: event)
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            let characters = (event.charactersIgnoringModifiers ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
        }
    }
}
