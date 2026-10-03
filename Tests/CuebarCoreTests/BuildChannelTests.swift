import XCTest
@testable import CuebarCore

final class BuildChannelTests: XCTestCase {
    func testDefaultsToReleaseWhenMissing() {
        XCTAssertEqual(BuildChannel.channel(from: nil), .release)
        XCTAssertEqual(BuildChannel.channel(from: [:]), .release)
        XCTAssertFalse(BuildChannel.release.isExperimental)
    }

    func testReadsExperimental() {
        let info: [String: Any] = ["CuebarBuildChannel": "experimental"]
        XCTAssertEqual(BuildChannel.channel(from: info), .experimental)
        XCTAssertTrue(BuildChannel.channel(from: info).isExperimental)
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(BuildChannel.channel(from: ["CuebarBuildChannel": "Experimental"]), .experimental)
    }

    func testUnknownValueFallsBackToRelease() {
        XCTAssertEqual(BuildChannel.channel(from: ["CuebarBuildChannel": "nightly"]), .release)
        XCTAssertEqual(BuildChannel.channel(from: ["CuebarBuildChannel": 42]), .release)
    }
}
