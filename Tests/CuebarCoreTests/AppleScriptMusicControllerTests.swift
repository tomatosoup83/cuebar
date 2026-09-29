import XCTest
@testable import CuebarCore

final class AppleScriptMusicControllerTests: XCTestCase {
    func testAlbumQueueScriptOrdersIDsAndDisablesShuffle() {
        let script = AppleScriptMusicController.albumQueueScript(trackIDs: ["AAA", "BBB", "CCC"])
        XCTAssertTrue(script.contains("{\"AAA\", \"BBB\", \"CCC\"}"))
        XCTAssertTrue(script.contains("set shuffle enabled to false"))
        XCTAssertTrue(script.contains("delete every track of q"))
        XCTAssertTrue(script.contains("play q"))
        XCTAssertTrue(script.contains(AppleScriptMusicController.albumQueuePlaylistName))
        XCTAssertTrue(script.contains("duplicate (first track of library playlist 1"))
    }

    func testAlbumQueueScriptEscapesIDs() {
        let script = AppleScriptMusicController.albumQueueScript(trackIDs: ["a\"b\\c"])
        XCTAssertTrue(script.contains("\"a\\\"b\\\\c\""))
    }

    func testEmptyAlbumScriptHasEmptyList() {
        let script = AppleScriptMusicController.albumQueueScript(trackIDs: [])
        XCTAssertTrue(script.contains("repeat with pid in {}"))
    }
}
