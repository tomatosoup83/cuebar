import XCTest
import CryptoKit
@testable import CuebarCore

final class UpdateCheckerTests: XCTestCase {
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func checker(status: Int = 200, body: Data) -> UpdateChecker {
        UpdateChecker(loader: { _ in (body, self.response(status)) })
    }

    private func fixture(releaseJSON: String) -> Data { Data(releaseJSON.utf8) }

    private let availableJSON = """
    {
      "tag_name": "v0.5.0",
      "body": "Release notes",
      "html_url": "https://github.com/tomatosoup83/cuebar/releases/tag/v0.5.0",
      "assets": [
        {"name": "Cuebar.zip", "browser_download_url": "https://example.com/Cuebar.zip"},
        {"name": "Cuebar.zip.sig", "browser_download_url": "https://example.com/Cuebar.zip.sig"},
        {"name": "Cuebar-0.5.0.zip", "browser_download_url": "https://example.com/Cuebar-0.5.0.zip"}
      ]
    }
    """

    func testFindsNewerRelease() async throws {
        let result = try await checker(body: fixture(releaseJSON: availableJSON))
            .check(current: AppVersion("0.4.0")!)

        guard case .available(let info) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(info.version, AppVersion("0.5.0"))
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/Cuebar.zip")
        XCTAssertEqual(info.signatureURL?.absoluteString, "https://example.com/Cuebar.zip.sig")
        XCTAssertEqual(info.notes, "Release notes")
    }

    func testUpToDate() async throws {
        let result = try await checker(body: fixture(releaseJSON: availableJSON))
            .check(current: AppVersion("0.5.0")!)
        XCTAssertEqual(result, .upToDate(AppVersion("0.5.0")!))
    }

    func testBadStatusThrows() async {
        do {
            _ = try await checker(status: 500, body: Data()).check(current: AppVersion("0.4.0")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error is UpdateError)
        }
    }

    func testMissingAssetThrows() async {
        let json = """
        {"tag_name": "v0.5.0", "html_url": "https://x", "assets": []}
        """
        do {
            _ = try await checker(body: fixture(releaseJSON: json)).check(current: AppVersion("0.4.0")!)
            XCTFail("Expected a missing-asset error")
        } catch let error as UpdateError {
            guard case .missingAsset = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}

final class ReleaseVerifierTests: XCTestCase {
    func testVerifiesValidSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("Cuebar update archive".utf8)
        let signature = try key.signature(for: data)

        XCTAssertTrue(ReleaseVerifier.verify(
            data: data,
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testRejectsTamperedData() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signature = try key.signature(for: Data("real".utf8))

        XCTAssertFalse(ReleaseVerifier.verify(
            data: Data("tampered".utf8),
            signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
        ))
    }

    func testRejectsUnconfiguredKey() {
        XCTAssertFalse(ReleaseVerifier.verify(data: Data(), signatureBase64: "sig", publicKeyBase64: ""))
    }
}

final class SwapScriptTests: XCTestCase {
    func testScriptContents() {
        let script = SwapScript.make(destination: "/Applications/Cuebar.app", workDirectory: "/tmp/work")
        XCTAssertTrue(script.contains("DEST=\"/Applications/Cuebar.app\""))
        XCTAssertTrue(script.contains("WORK=\"/tmp/work\""))
        XCTAssertTrue(script.contains("while pgrep -x Cuebar"))
        XCTAssertTrue(script.contains("ditto \"$WORK/Cuebar.app\" \"$DEST\""))
        XCTAssertTrue(script.contains("mv \"$WORK/Cuebar.bak\" \"$DEST\""))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("open \"$DEST\""))
    }
}

final class UpdatePreferenceStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "cuebar-update-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToOn() {
        XCTAssertTrue(UpdatePreferenceStore(defaults: makeDefaults()).checksAutomatically)
    }

    func testRoundTrip() {
        let store = UpdatePreferenceStore(defaults: makeDefaults())
        store.checksAutomatically = false
        XCTAssertFalse(store.checksAutomatically)
    }
}

final class UpdateFeedbackTests: XCTestCase {
    private func info(_ version: String) -> UpdateInfo {
        UpdateInfo(
            version: AppVersion(version)!,
            tag: "v\(version)",
            notes: "",
            downloadURL: URL(string: "https://example.com/Cuebar.zip")!,
            signatureURL: nil,
            releaseURL: URL(string: "https://example.com")!
        )
    }

    func testCopy() {
        let available = UpdateFeedback.available(info("0.5.0"))
        XCTAssertEqual(available.kind, .info)
        XCTAssertTrue(available.message.contains("0.5.0"))

        XCTAssertEqual(UpdateFeedback.downloading().kind, .info)
        XCTAssertEqual(UpdateFeedback.installing().kind, .info)
        XCTAssertEqual(UpdateFeedback.upToDate(AppVersion("0.5.0")!).kind, .success)

        let failure = UpdateFeedback.failed(UpdateError.signatureMismatch)
        XCTAssertEqual(failure.kind, .error)
        XCTAssertEqual(failure.message, UpdateError.signatureMismatch.errorDescription)
    }
}
