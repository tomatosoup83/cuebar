import Foundation

/// Remembers whether the first-run onboarding has been completed.
public struct OnboardingStore {
    private static let storageKey = "hasCompletedOnboarding"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasCompleted: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    public func complete() {
        defaults.set(true, forKey: Self.storageKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
