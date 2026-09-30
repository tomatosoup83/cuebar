import Foundation

/// Errors from the update system.
public enum UpdateError: Error, LocalizedError, Sendable {
    case unreachable(String)
    case badRelease
    case missingAsset(String)
    case signingNotConfigured
    case unsignedRelease
    case signatureMismatch
    case badArchive

    public var errorDescription: String? {
        switch self {
        case .unreachable(let detail):
            return "Couldn’t reach GitHub to check for updates. \(detail)"
        case .badRelease:
            return "The latest GitHub release couldn’t be understood."
        case .missingAsset(let name):
            return "The latest release has no “\(name)” download."
        case .signingNotConfigured:
            return "Updates aren’t signed (no public key in this build)."
        case .unsignedRelease:
            return "The update isn’t signed, so Cuebar won’t install it."
        case .signatureMismatch:
            return "The update’s signature didn’t match — install aborted."
        case .badArchive:
            return "The downloaded update wasn’t a valid app."
        }
    }
}

/// Fetches the latest GitHub release and reports whether it is newer.
public final class UpdateChecker: @unchecked Sendable {
    /// Injectable transport so the API/JSON can be tested without the network.
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let defaultAPIURL = URL(
        string: "https://api.github.com/repos/tomatosoup83/cuebar/releases/latest"
    )!

    /// The human-facing page for the latest release.
    public static let defaultReleasePageURL = URL(
        string: "https://github.com/tomatosoup83/cuebar/releases/latest"
    )!

    private let apiURL: URL
    private let assetName: String
    private let signatureName: String
    private let loader: Loader

    public init(
        apiURL: URL = UpdateChecker.defaultAPIURL,
        assetName: String = "Cuebar.zip",
        signatureName: String = "Cuebar.zip.sig",
        loader: Loader? = nil
    ) {
        self.apiURL = apiURL
        self.assetName = assetName
        self.signatureName = signatureName
        self.loader = loader ?? { request in try await URLSession.shared.data(for: request) }
    }

    public func check(current: AppVersion) async throws -> UpdateCheckResult {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Cuebar/\(AppVersion.current()?.description ?? "dev") (macOS)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await loader(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.unreachable("GitHub returned \(http.statusCode).")
        }

        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            throw UpdateError.badRelease
        }
        guard let version = AppVersion(release.tagName) else {
            throw UpdateError.badRelease
        }
        guard version > current else { return .upToDate(current) }

        guard let asset = release.assets.first(where: { $0.name == assetName }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.missingAsset(assetName)
        }
        let signatureURL = release.assets
            .first(where: { $0.name == signatureName })
            .flatMap { URL(string: $0.browserDownloadURL) }
        let releaseURL = URL(string: release.htmlURL) ?? apiURL

        return .available(
            UpdateInfo(
                version: version,
                tag: release.tagName,
                notes: release.body ?? "",
                downloadURL: downloadURL,
                signatureURL: signatureURL,
                releaseURL: releaseURL
            )
        )
    }

    // MARK: - GitHub payload

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
