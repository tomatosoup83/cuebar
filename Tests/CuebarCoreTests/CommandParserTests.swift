import XCTest
@testable import CuebarCore

final class CommandParserTests: XCTestCase {
    func testPlayWithSong() {
        XCTAssertEqual(CommandParser.parse("play take on me"), .play(query: "take on me"))
    }

    func testPlayIsCaseInsensitive() {
        XCTAssertEqual(CommandParser.parse("PLAY Take On Me"), .play(query: "Take On Me"))
    }

    func testBareSongNameDefaultsToPlay() {
        XCTAssertEqual(CommandParser.parse("take on me"), .play(query: "take on me"))
    }

    func testBarePlayIsResume() {
        XCTAssertEqual(CommandParser.parse("play"), .resume)
    }

    func testTransportCommands() {
        XCTAssertEqual(CommandParser.parse("pause"), .pause)
        XCTAssertEqual(CommandParser.parse("resume"), .resume)
        XCTAssertEqual(CommandParser.parse("next"), .next)
        XCTAssertEqual(CommandParser.parse("previous"), .previous)
    }

    func testTransportAliases() {
        XCTAssertEqual(CommandParser.parse("skip"), .next)
        XCTAssertEqual(CommandParser.parse("forward"), .next)
        XCTAssertEqual(CommandParser.parse("prev"), .previous)
        XCTAssertEqual(CommandParser.parse("back"), .previous)
    }

    func testShuffleVariants() {
        XCTAssertEqual(CommandParser.parse("shuffle"), .shuffle(.toggle))
        XCTAssertEqual(CommandParser.parse("shuffle on"), .shuffle(.on))
        XCTAssertEqual(CommandParser.parse("shuffle off"), .shuffle(.off))
        XCTAssertEqual(CommandParser.parse("SHUFFLE OFF"), .shuffle(.off))
    }

    func testRepeatVariants() {
        XCTAssertNil(CommandParser.parse("repeat"))
        XCTAssertEqual(CommandParser.parse("repeat queue"), .setRepeat(.all))
        XCTAssertEqual(CommandParser.parse("repeat all"), .setRepeat(.all))
        XCTAssertEqual(CommandParser.parse("repeat track"), .setRepeat(.one))
        XCTAssertEqual(CommandParser.parse("repeat one"), .setRepeat(.one))
        XCTAssertEqual(CommandParser.parse("repeat song"), .setRepeat(.one))
        XCTAssertEqual(CommandParser.parse("repeat off"), .setRepeat(.off))
        XCTAssertEqual(CommandParser.parse("REPEAT QUEUE"), .setRepeat(.all))
    }

    func testEmptyInput() {
        XCTAssertNil(CommandParser.parse(""))
        XCTAssertNil(CommandParser.parse("   "))
    }

    func testSearchTermExtraction() {
        XCTAssertEqual(CommandParser.searchTerm(for: .play(query: "abc")), "abc")
        XCTAssertNil(CommandParser.searchTerm(for: .pause))
        XCTAssertNil(CommandParser.searchTerm(for: nil))
    }
}
