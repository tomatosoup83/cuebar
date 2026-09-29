import Foundation

/// A semantic `major.minor.patch` version, tolerant of a leading `v` and
/// trailing pre-release suffixes (e.g. `v0.5.0`, `0.5.0-beta`).
public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        func number(_ sub: Substring) -> Int? {
            let digits = sub.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }

        guard let major = number(parts[0]) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (number(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (number(parts[2]) ?? 0) : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// The running app's version from its Info.plist.
    public static func current(in bundle: Bundle = .main) -> AppVersion? {
        guard let raw = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return AppVersion(raw)
    }
}
