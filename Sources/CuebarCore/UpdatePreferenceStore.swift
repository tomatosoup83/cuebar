import Foundation

/// Persists whether Cuebar checks for updates on launch.
public struct UpdatePreferenceStore {
    private static let storageKey = "checkForUpdatesAutomatically"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to on.
    public var checksAutomatically: Bool {
        get { defaults.object(forKey: Self.storageKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.storageKey) }
    }
}
