import Foundation

/// Which channel a build belongs to.
///
/// The value is stamped into the app bundle's `Info.plist` at package time (see
/// `Scripts/build-app.sh`), so a build made off the `experimental` branch can
/// advertise itself without needing a separate binary. Missing or unrecognised
/// values fall back to `.release`, which keeps `swift run` / `swift test`
/// unbadged.
public enum BuildChannel: String, Sendable, CaseIterable {
    case release
    case experimental

    public var isExperimental: Bool { self == .experimental }

    /// Resolves the channel recorded in an `Info.plist` dictionary.
    public static func channel(from infoDictionary: [String: Any]?) -> BuildChannel {
        guard let raw = infoDictionary?["CuebarBuildChannel"] as? String else {
            return .release
        }
        return BuildChannel(rawValue: raw.lowercased()) ?? .release
    }

    /// The running app's channel.
    public static func current(in bundle: Bundle = .main) -> BuildChannel {
        channel(from: bundle.infoDictionary)
    }
}
