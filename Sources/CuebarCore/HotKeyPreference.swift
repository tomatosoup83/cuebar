import Foundation
import Carbon.HIToolbox

/// A persisted global-hotkey choice.
public struct HotKeyPreference: Codable, Equatable, Sendable {
    /// Virtual key code (`kVK_*`).
    public var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey` / `optionKey` / `shiftKey` / `controlKey`).
    public var modifiers: UInt32
    /// Pre-rendered label, for example "⌘⌥Space".
    public var displayString: String

    public init(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    public static let `default` = HotKeyPreference(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | optionKey),
        displayString: "⌘⌥Space"
    )

    /// Whether the combination includes a "command-like" modifier. Plain keys
    /// and shift-only combos are rejected so the hotkey can't swallow typing.
    public var hasRequiredModifier: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }
}

public enum HotKeyFormatter {
    /// Ordered ⌃⌥⇧⌘ symbols for a Carbon modifier mask.
    public static func modifierSymbols(_ modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }
}
