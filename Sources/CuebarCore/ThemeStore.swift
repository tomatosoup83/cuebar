import Foundation

/// Persists the theme options, mirroring `OnboardingStore` / `HotKeyStore`.
public struct ThemeStore {
    private static let themeKey = "themeID"
    private static let followSelectionKey = "ambientFollowsSelection"
    /// Marks the one-time switch to Album Art + follow-the-selection as the
    /// default, so it is applied for upgraders but never again after that.
    private static let albumArtDefaultKey = "appliedAlbumArtDefault"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Defaults to `.albumArt` when unset (or unknown).
    public var theme: ThemeID {
        get {
            guard let raw = defaults.string(forKey: Self.themeKey),
                  let theme = ThemeID(rawValue: raw) else {
                return .albumArt
            }
            return theme
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.themeKey)
        }
    }

    /// Whether the ambient colour follows the highlighted row. Defaults to on —
    /// Album Art follows the row you highlight, not just the now-playing track.
    public var ambientFollowsSelection: Bool {
        get {
            // An explicit `false` is a real choice; only an *absent* value takes
            // the new default, since `bool(forKey:)` can't tell them apart.
            guard defaults.object(forKey: Self.followSelectionKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.followSelectionKey)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.followSelectionKey) }
    }

    /// Moves an existing install onto the new default once.
    ///
    /// Album Art with the ambient following the highlighted row replaces Tahoe
    /// as the out-of-the-box look. Anyone upgrading carries their old choice in
    /// `UserDefaults`, so — once — we reset both options for them. The flag is
    /// recorded so a later, deliberate choice (including going back to Tahoe) is
    /// left alone.
    public func applyAlbumArtDefaultIfNeeded() {
        guard !defaults.bool(forKey: Self.albumArtDefaultKey) else { return }
        theme = .albumArt
        ambientFollowsSelection = true
        defaults.set(true, forKey: Self.albumArtDefaultKey)
    }
}
