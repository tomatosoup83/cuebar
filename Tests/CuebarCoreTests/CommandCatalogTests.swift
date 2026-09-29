import XCTest
@testable import CuebarCore

final class CommandCatalogTests: XCTestCase {
    func testEmptyInputReturnsEveryCommand() {
        let matches = CommandCatalog.matches(for: "")
        XCTAssertEqual(matches.count, CommandCatalog.all.count)
        XCTAssertEqual(Set(matches.map(\.id)), Set(CommandCatalog.all.map(\.id)))
    }

    func testExactKeywordWins() {
        XCTAssertEqual(CommandCatalog.matches(for: "pause").first?.id, "pause")
        XCTAssertEqual(CommandCatalog.matches(for: "resume").first?.id, "resume")
        XCTAssertEqual(CommandCatalog.matches(for: "next").first?.id, "next")
        XCTAssertEqual(CommandCatalog.matches(for: "previous").first?.id, "previous")
    }

    func testPrefixTyping() {
        XCTAssertEqual(CommandCatalog.matches(for: "pau").first?.id, "pause")
        XCTAssertEqual(CommandCatalog.matches(for: "nex").first?.id, "next")
        XCTAssertEqual(CommandCatalog.matches(for: "shuf").first?.id, "shuffle.toggle")
    }

    func testAliases() {
        XCTAssertEqual(CommandCatalog.matches(for: "skip").first?.id, "next")
        XCTAssertEqual(CommandCatalog.matches(for: "prev").first?.id, "previous")
    }

    func testShuffleVariants() {
        // "shuffle" alone: toggle is an exact match and must rank first.
        XCTAssertEqual(CommandCatalog.matches(for: "shuffle").first?.id, "shuffle.toggle")

        // "shuffle o" partially matches on/off but not the toggle.
        let matches = CommandCatalog.matches(for: "shuffle o")
        let ids = Set(matches.map(\.id))
        XCTAssertTrue(ids.contains("shuffle.on"))
        XCTAssertTrue(ids.contains("shuffle.off"))
        XCTAssertFalse(ids.contains("shuffle.toggle"))

        XCTAssertEqual(CommandCatalog.matches(for: "shuffle on").first?.id, "shuffle.on")
        XCTAssertEqual(CommandCatalog.matches(for: "shuffle off").first?.id, "shuffle.off")
    }

    func testFuzzySingleWord() {
        XCTAssertEqual(CommandCatalog.matches(for: "pase").first?.id, "pause")
    }

    func testRepeatVariants() {
        // "repeat" alone surfaces the three explicit modes, no cycle.
        let bare = Set(CommandCatalog.matches(for: "repeat").map(\.id))
        XCTAssertEqual(bare, ["repeat.queue", "repeat.track", "repeat.off"])

        XCTAssertEqual(CommandCatalog.matches(for: "repeat queue").first?.id, "repeat.queue")
        XCTAssertEqual(CommandCatalog.matches(for: "repeat all").first?.id, "repeat.queue")
        XCTAssertEqual(CommandCatalog.matches(for: "repeat track").first?.id, "repeat.track")
        XCTAssertEqual(CommandCatalog.matches(for: "repeat off").first?.id, "repeat.off")
    }

    /// The important negative: a song query must not match the "play" keyword.
    func testSongQueryMatchesNoCommand() {
        XCTAssertTrue(CommandCatalog.matches(for: "play take on me").isEmpty)
        XCTAssertTrue(CommandCatalog.matches(for: "take on me").isEmpty)
    }

    func testBarePlayShowsResume() {
        XCTAssertEqual(CommandCatalog.matches(for: "play").first?.id, "resume")
    }

    func testRebuildIndexCommand() {
        XCTAssertEqual(CommandCatalog.matches(for: "rebuild").first?.id, "rebuildIndex")
        XCTAssertEqual(CommandCatalog.matches(for: "reindex").first?.id, "rebuildIndex")
        XCTAssertEqual(CommandCatalog.matches(for: "library index").first?.id, "rebuildIndex")
    }

    func testCommandsAreComposedBeforeMusic() {
        let commands = CommandCatalog.matches(for: "pau")
        let music = [
            MusicCandidate(
                id: "song",
                kind: .song,
                source: .library,
                title: "Pause",
                artist: "Artist",
                album: "Album",
                persistentID: "song"
            )
        ]

        let items = PaletteListComposer.compose(
            query: "pau",
            nowPlaying: nil,
            commands: commands,
            music: music
        )

        XCTAssertEqual(items.count, commands.count + 1)
        if case .command = items.first {} else {
            XCTFail("Expected command rows first")
        }
        if case .music = items.last {} else {
            XCTFail("Expected music rows last")
        }
    }
}
