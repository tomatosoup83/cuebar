import Foundation

/// Persists the launch hotkey in `UserDefaults`.
public struct HotKeyStore {
    private static let storageKey = "launchHotKey"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HotKeyPreference {
        guard let data = defaults.data(forKey: Self.storageKey),
              let preference = try? JSONDecoder().decode(HotKeyPreference.self, from: data) else {
            return .default
        }
        return preference
    }

    public func save(_ preference: HotKeyPreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
