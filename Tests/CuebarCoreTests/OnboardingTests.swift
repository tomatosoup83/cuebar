import XCTest
@testable import CuebarCore

final class OnboardingStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "cuebar-onboarding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToNotCompleted() {
        XCTAssertFalse(OnboardingStore(defaults: makeDefaults()).hasCompleted)
    }

    func testCompleteRoundTrips() {
        let defaults = makeDefaults()
        OnboardingStore(defaults: defaults).complete()
        XCTAssertTrue(OnboardingStore(defaults: defaults).hasCompleted)
    }

    func testReset() {
        let defaults = makeDefaults()
        let store = OnboardingStore(defaults: defaults)
        store.complete()
        store.reset()
        XCTAssertFalse(store.hasCompleted)
    }
}

final class AutomationPermissionTests: XCTestCase {
    func testPermissionDeniedIsNotGranted() {
        XCTAssertFalse(
            AppleScriptMusicController.permissionGranted(
                from: AppleScriptError(code: -1743, message: "denied")
            )
        )
    }

    func testOtherErrorsCountAsGranted() {
        XCTAssertTrue(
            AppleScriptMusicController.permissionGranted(
                from: AppleScriptError(code: -1, message: "oops")
            )
        )
        XCTAssertTrue(
            AppleScriptMusicController.permissionGranted(from: URLError(.timedOut))
        )
    }

    func testPermissionErrorFlag() {
        XCTAssertTrue(AppleScriptError(code: -1743, message: "").isPermissionDenied)
        XCTAssertTrue(AppleScriptError(code: -10003, message: "").isPermissionDenied)
        XCTAssertFalse(AppleScriptError(code: -1, message: "").isPermissionDenied)
    }
}
