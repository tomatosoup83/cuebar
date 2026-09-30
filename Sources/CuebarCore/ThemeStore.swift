import Foundation

/// Persists the theme options, mirroring `OnboardingStore` / `HotKeyStore`.
public struct ThemeStore {
    private static let themeKey = "themeID"
    private static let followSelectionKey = "ambientFollowsSelection"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to `.tahoe` when unset (or unknown).
    public var theme: ThemeID {
        get {
            guard let raw = defaults.string(forKey: Self.themeKey),
                  let theme = ThemeID(rawValue: raw) else {
                return .tahoe
            }
            return theme
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.themeKey)
        }
    }

    /// Whether the ambient colour follows the highlighted row. Defaults to off —
    /// the panel follows the now-playing track instead.
    public var ambientFollowsSelection: Bool {
        get { defaults.bool(forKey: Self.followSelectionKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.followSelectionKey) }
    }
}
