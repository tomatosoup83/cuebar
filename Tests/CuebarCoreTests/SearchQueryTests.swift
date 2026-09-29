import XCTest
@testable import CuebarCore

final class SearchQueryTests: XCTestCase {
    func testPlainTermHasNoPreference() {
        let query = SearchQuery.parse("take on me")
        XCTAssertEqual(query.term, "take on me")
        XCTAssertEqual(query.preference, .songs)
    }

    func testTrailingAlbumKeywordIsStripped() {
        let query = SearchQuery.parse("take on me album")
        XCTAssertEqual(query.term, "take on me")
        XCTAssertEqual(query.preference, .albums)
    }

    func testLeadingAlbumKeywordIsStripped() {
        let query = SearchQuery.parse("album take on me")
        XCTAssertEqual(query.term, "take on me")
        XCTAssertEqual(query.preference, .albums)
    }

    func testKeywordIsCaseInsensitive() {
        let query = SearchQuery.parse("Take On Me ALBUM")
        XCTAssertEqual(query.term, "Take On Me")
        XCTAssertEqual(query.preference, .albums)
    }

    func testKeywordWithPunctuation() {
        let query = SearchQuery.parse("take on me, album")
        XCTAssertEqual(query.term, "take on me,")
        XCTAssertEqual(query.preference, .albums)
    }

    func testAlbumAloneStaysLiteral() {
        let query = SearchQuery.parse("album")
        XCTAssertEqual(query.term, "album")
        XCTAssertEqual(query.preference, .songs)
    }

    func testKeywordAloneWithSpaceIsAnEmptyScope() {
        let query = SearchQuery.parse("album ")
        XCTAssertEqual(query.term, "")
        XCTAssertEqual(query.preference, .albums)
    }

    func testAlbumInTheMiddleIsNotAKeyword() {
        let query = SearchQuery.parse("the album collection")
        XCTAssertEqual(query.term, "the album collection")
        XCTAssertEqual(query.preference, .songs)
    }

    func testPlaylistKeywordBothEnds() {
        let leading = SearchQuery.parse("playlist focus")
        XCTAssertEqual(leading.term, "focus")
        XCTAssertEqual(leading.preference, .playlists)

        let trailing = SearchQuery.parse("focus playlist")
        XCTAssertEqual(trailing.term, "focus")
        XCTAssertEqual(trailing.preference, .playlists)
    }

    func testPlaylistsPluralKeyword() {
        let query = SearchQuery.parse("focus playlists")
        XCTAssertEqual(query.term, "focus")
        XCTAssertEqual(query.preference, .playlists)
    }

    func testPlaylistAloneStaysLiteral() {
        let query = SearchQuery.parse("playlist")
        XCTAssertEqual(query.term, "playlist")
        XCTAssertEqual(query.preference, .songs)
    }

    func testTrailingKeywordWinsOverLeading() {
        let query = SearchQuery.parse("album playlist")
        XCTAssertEqual(query.term, "album")
        XCTAssertEqual(query.preference, .playlists)
    }

    func testEmptyInput() {
        let query = SearchQuery.parse("   ")
        XCTAssertEqual(query.term, "")
        XCTAssertEqual(query.preference, .songs)
    }
}
