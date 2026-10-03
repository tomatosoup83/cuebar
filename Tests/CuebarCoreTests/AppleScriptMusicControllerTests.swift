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

    func testLovedScriptsEscapeIDs() {
        let query = AppleScriptMusicController.lovedQueryScript(persistentID: "a\"b")
        XCTAssertTrue(query.contains("persistent ID is \"a\\\"b\""))
        XCTAssertTrue(query.contains("(loved of t) as string"))

        let set = AppleScriptMusicController.setLovedScript(true, persistentID: "X")
        XCTAssertTrue(set.contains("set loved of t to true"))
        XCTAssertTrue(AppleScriptMusicController.setLovedScript(false, persistentID: "X")
            .contains("set loved of t to false"))
    }

    func testAddToPlaylistScriptUsesPersistentIDs() {
        let script = AppleScriptMusicController.addToPlaylistScript(
            trackPersistentID: "TRACK",
            playlistPersistentID: "PLAY"
        )
        XCTAssertTrue(script.contains("whose persistent ID is \"TRACK\""))
        XCTAssertTrue(script.contains("duplicate t to (first user playlist whose persistent ID is \"PLAY\")"))
    }

    func testRevealScriptSelectsAndActivates() {
        let script = AppleScriptMusicController.revealScript(persistentID: "TRACK")
        XCTAssertTrue(script.contains("reveal (some track of library playlist 1"))
        XCTAssertTrue(script.contains("activate"))
    }

    func testOpenLocationScriptEscapesURL() {
        let script = AppleScriptMusicController.openLocationScript(
            url: URL(string: "https://music.apple.com/x?y=1")!
        )
        XCTAssertTrue(script.contains("open location \"https://music.apple.com/x?y=1\""))
        XCTAssertTrue(script.contains("activate"))
    }
}
