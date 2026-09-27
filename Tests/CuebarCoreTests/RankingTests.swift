import XCTest
@testable import CuebarCore

final class RankingTests: XCTestCase {
    private func song(
        _ id: String,
        _ title: String,
        artist: String = "",
        album: String = "",
        source: MusicSource = .catalog
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: source,
            title: title,
            artist: artist,
            album: album,
            persistentID: source == .library ? "PID-\(id)" : nil
        )
    }

    private func album(
        _ id: String,
        _ title: String,
        artist: String = "",
        source: MusicSource = .catalog
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .album,
            source: source,
            title: title,
            artist: artist,
            album: ""
        )
    }

    /// The explicit MVP requirement.
    func testExactSongTitleOutranksAlbumWithSameName() {
        let items = [
            album("album", "Take On Me", artist: "Various Artists"),
            song("song", "Take On Me", artist: "a-ha")
        ]
        let ranked = Ranking.rank(items, query: "take on me")
        XCTAssertEqual(ranked.first?.id, "song")
    }

    /// Even when the album is in the library and the song is in the catalog.
    func testExactSongOutranksLibraryAlbum() {
        let items = [
            album("album", "Take On Me", source: .library),
            song("song", "Take On Me", source: .catalog)
        ]
        XCTAssertEqual(Ranking.rank(items, query: "take on me").first?.id, "song")
    }

    func testPrefixOutranksSubstring() {
        let items = [
            song("substring", "Do Not Take It"),
            song("prefix", "Take On Me")
        ]
        let ranked = Ranking.rank(items, query: "take")
        XCTAssertEqual(ranked.first?.id, "prefix")
    }

    func testLibraryWinsTies() {
        let items = [
            song("catalog", "Nightfall", source: .catalog),
            song("library", "Nightfall", source: .library)
        ]
        XCTAssertEqual(Ranking.rank(items, query: "nightfall").first?.id, "library")
    }

    func testTypoTolerance() {
        let items = [
            song("target", "Take On Me", artist: "a-ha"),
            song("other", "Sunshine Reggae")
        ]
        let ranked = Ranking.rank(items, query: "Tke On Me")
        XCTAssertEqual(ranked.first?.id, "target")
    }

    func testArtistMatchIsConsidered() {
        let items = [
            song("a", "Some Song", artist: "a-ha"),
            song("b", "Some Song", artist: "Someone Else")
        ]
        XCTAssertEqual(Ranking.rank(items, query: "a-ha").first?.id, "a")
    }

    func testDeterministicOrderingRegardlessOfInputOrder() {
        let items = [
            song("one", "Take On Me", artist: "a-ha"),
            song("two", "Take It Easy", artist: "Eagles"),
            song("three", "Take Five", artist: "Dave Brubeck"),
            song("four", "Takin' Care of Business"),
            song("five", "Mistake")
        ]
        let forward = Ranking.rank(items, query: "take").map(\.id)
        let backward = Ranking.rank(items.reversed(), query: "take").map(\.id)
        XCTAssertEqual(forward, backward)
    }

    func testEmptyQueryReturnsInputOrder() {
        let items = [song("a", "A"), song("b", "B")]
        XCTAssertEqual(Ranking.rank(items, query: "").map(\.id), ["a", "b"])
    }

    func testUnrelatedQueryReturnsNoMatches() {
        let items = [song("a", "Take On Me")]
        XCTAssertTrue(Ranking.rank(items, query: "zzzzzqqqq").isEmpty)
    }
}
