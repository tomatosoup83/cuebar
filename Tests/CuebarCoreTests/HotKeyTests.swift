import XCTest
import Carbon.HIToolbox
@testable import CuebarCore

final class HotKeyTests: XCTestCase {
    // MARK: - Formatting

    func testModifierSymbolsOrderAndContent() {
        XCTAssertEqual(HotKeyFormatter.modifierSymbols(UInt32(cmdKey | optionKey)), "⌥⌘")
        XCTAssertEqual(HotKeyFormatter.modifierSymbols(UInt32(controlKey | shiftKey)), "⌃⇧")
        XCTAssertEqual(
            HotKeyFormatter.modifierSymbols(UInt32(cmdKey | optionKey | shiftKey | controlKey)),
            "⌃⌥⇧⌘"
        )
        XCTAssertEqual(HotKeyFormatter.modifierSymbols(0), "")
    }

    func testDefaultPreference() {
        let preference = HotKeyPreference.default
        XCTAssertEqual(preference.displayString, "⌘⌥Space")
        XCTAssertEqual(preference.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(preference.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertTrue(preference.hasRequiredModifier)
    }

    func testRequiredModifierValidation() {
        XCTAssertFalse(
            HotKeyPreference(keyCode: 0, modifiers: UInt32(shiftKey), displayString: "⇧A").hasRequiredModifier
        )
        XCTAssertFalse(
            HotKeyPreference(keyCode: 0, modifiers: 0, displayString: "A").hasRequiredModifier
        )
        XCTAssertTrue(
            HotKeyPreference(keyCode: 0, modifiers: UInt32(optionKey), displayString: "⌥A").hasRequiredModifier
        )
        XCTAssertTrue(
            HotKeyPreference(keyCode: 0, modifiers: UInt32(cmdKey), displayString: "⌘A").hasRequiredModifier
        )
    }

    func testPreferenceCodableRoundTrip() throws {
        let original = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(controlKey | cmdKey),
            displayString: "⌃⌘P"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyPreference.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Persistence

    func testStoreRoundTripAndReset() throws {
        let suiteName = "cuebar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HotKeyStore(defaults: defaults)
        XCTAssertEqual(store.load(), HotKeyPreference.default, "An empty store returns the default")

        let custom = HotKeyPreference(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: UInt32(controlKey | optionKey),
            displayString: "⌃⌥H"
        )
        store.save(custom)
        XCTAssertEqual(store.load(), custom, "Saved preference is loaded back")

        store.reset()
        XCTAssertEqual(store.load(), HotKeyPreference.default, "Reset restores the default")
    }

    // MARK: - Catalog integration

    func testSettingsIsMatchedByItsKeywords() {
        for term in ["settings", "preferences", "hotkey"] {
            let match = CommandCatalog.matches(for: term).first { $0.id == "settings" }
            XCTAssertNotNil(match, "Expected the Settings row to match '\(term)'")
        }
    }

    func testSettingsEntryOpensSettings() {
        let entry = CommandCatalog.all.first { $0.id == "settings" }
        XCTAssertEqual(entry?.action, .openSettings)
    }

    func testMusicEntriesCarryMusicActions() {
        let pause = CommandCatalog.all.first { $0.id == "pause" }
        XCTAssertEqual(pause?.action, .music(.pause))
    }
}
