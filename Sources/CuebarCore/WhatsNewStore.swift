import Foundation

/// Remembers the last version whose What's New screen has been shown, so it
/// appears once per version.
public struct WhatsNewStore {
    private static let storageKey = "lastSeenVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The version whose highlights have already been shown.
    public var lastSeenVersion: String? {
        get { defaults.string(forKey: Self.storageKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.storageKey) }
    }

    /// Whether `version`'s highlights are still unseen.
    ///
    /// A missing value means we don't know what was installed before — which is the
    /// case for anyone upgrading to the first release that has this screen — so it
    /// announces rather than staying silent.
    public func shouldShow(for version: String) -> Bool {
        lastSeenVersion != version
    }
}
