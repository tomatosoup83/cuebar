import XCTest
@testable import CuebarCore

final class AppVersionTests: XCTestCase {
    func testParsesPlainAndPrefixed() {
        XCTAssertEqual(AppVersion("0.4.0")?.description, "0.4.0")
        XCTAssertEqual(AppVersion("v0.5.0")?.description, "0.5.0")
        XCTAssertEqual(AppVersion("V1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(AppVersion("2")?.description, "2.0.0")
        XCTAssertEqual(AppVersion("0.5.0-beta.1")?.description, "0.5.0")
    }

    func testRejectsNonVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("release"))
    }

    func testOrdering() {
        XCTAssertTrue(AppVersion("0.4.9")! < AppVersion("0.4.10")!)
        XCTAssertTrue(AppVersion("0.9.0")! < AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("1.0.0")! < AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("1.0.0")! < AppVersion("0.9.9")!)
    }
}
