import AppKit
import Combine
import CuebarCore

/// Checks GitHub for a newer release, and downloads + verifies + installs it.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableUpdate: UpdateInfo?
    @Published private(set) var isInstalling = false

    /// Shows a toast (wired to the toast window by the app delegate).
    var onToast: ((Toast) -> Void)?

    private let checker: UpdateChecker
    private let store: UpdatePreferenceStore
    private let currentVersion: AppVersion

    init(
        checker: UpdateChecker = UpdateChecker(),
        store: UpdatePreferenceStore = UpdatePreferenceStore(),
        currentVersion: AppVersion? = AppVersion.current()
    ) {
        self.checker = checker
        self.store = store
        self.currentVersion = currentVersion ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    var currentVersionText: String { currentVersion.description }
    var checksAutomatically: Bool { store.checksAutomatically }

    func setChecksAutomatically(_ enabled: Bool) {
        store.checksAutomatically = enabled
    }

    /// Launch-time check (quiet unless an update exists).
    func checkIfEnabled() {
        guard store.checksAutomatically else { return }
        check(announceUpToDate: false)
    }

    /// Manual check (reports up-to-date and failures too).
    func check(announceUpToDate: Bool = true) {
        Task {
            do {
                switch try await checker.check(current: currentVersion) {
                case .upToDate(let version):
                    availableUpdate = nil
                    if announceUpToDate { onToast?(UpdateFeedback.upToDate(version)) }
                case .available(let info):
                    availableUpdate = info
                    onToast?(UpdateFeedback.available(info))
                }
            } catch {
                if announceUpToDate { onToast?(UpdateFeedback.failed(error)) }
            }
        }
    }

    func install() {
        guard let info = availableUpdate, !isInstalling else { return }
        isInstalling = true
        onToast?(UpdateFeedback.downloading())

        Task {
            do {
                let staged = try await downloadAndStage(info)
                onToast?(UpdateFeedback.installing())
                try launchSwap(stagedApp: staged)
                NSApp.terminate(nil)
            } catch {
                isInstalling = false
                onToast?(UpdateFeedback.failed(error))
            }
        }
    }

    // MARK: - Download & verify

    private func downloadAndStage(_ info: UpdateInfo) async throws -> URL {
        guard UpdateKey.isConfigured else { throw UpdateError.signingNotConfigured }
        guard let signatureURL = info.signatureURL else { throw UpdateError.unsignedRelease }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("cuebar-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (zip, _) = try await URLSession.shared.data(from: info.downloadURL)
        let (signature, _) = try await URLSession.shared.data(from: signatureURL)
        let signatureText = String(data: signature, encoding: .utf8) ?? ""

        guard ReleaseVerifier.verify(
            data: zip,
            signatureBase64: signatureText,
            publicKeyBase64: UpdateKey.publicKeyBase64
        ) else {
            throw UpdateError.signatureMismatch
        }

        let zipURL = work.appendingPathComponent("Cuebar.zip")
        try zip.write(to: zipURL)
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path])

        let staged = work.appendingPathComponent("Cuebar.app")
        guard FileManager.default.fileExists(atPath: staged.path) else {
            throw UpdateError.badArchive
        }
        return staged
    }

    /// Runs the swap script detached so it survives our termination.
    private func launchSwap(stagedApp: URL) throws {
        let work = stagedApp.deletingLastPathComponent()
        let destination = Bundle.main.bundleURL.path
        let script = SwapScript.make(destination: destination, workDirectory: work.path)
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "nohup /bin/sh '\(scriptURL.path)' >/dev/null 2>&1 &"]
        try process.run()
    }

    private func runProcess(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.badArchive }
    }
}
