import Foundation

/// A newer release found on GitHub.
public struct UpdateInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    public let notes: String
    public let downloadURL: URL
    /// The `.sig` asset, if the release published one.
    public let signatureURL: URL?
    public let releaseURL: URL

    public init(
        version: AppVersion,
        tag: String,
        notes: String,
        downloadURL: URL,
        signatureURL: URL?,
        releaseURL: URL
    ) {
        self.version = version
        self.tag = tag
        self.notes = notes
        self.downloadURL = downloadURL
        self.signatureURL = signatureURL
        self.releaseURL = releaseURL
    }
}

/// The outcome of an update check.
public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(AppVersion)
    case available(UpdateInfo)
}
