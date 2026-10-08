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

    func testSongWinsByDefaultButAlbumWinsWithKeyword() {
        let items = [
            song("song", "Take On Me", artist: "a-ha", source: .library),
            album("album", "Take On Me", artist: "a-ha", source: .library)
        ]
        XCTAssertEqual(Ranking.rank(items, query: "take on me").first?.id, "song")
        XCTAssertEqual(
            Ranking.rank(items, query: "take on me", preference: .albums).first?.id,
            "album"
        )
    }

    func testPlaylistPreferencePutsPlaylistsFirst() {
        let playlist = MusicCandidate(
            id: "pl", kind: .playlist, source: .library,
            title: "Nightfall", artist: "", album: ""
        )
        let song = song("song", "Nightfall", source: .library)
        let album = album("album", "Nightfall", source: .library)

        XCTAssertEqual(Ranking.rank([song, album, playlist], query: "nightfall").first?.id, "song")
        XCTAssertEqual(
            Ranking.rank([song, album, playlist], query: "nightfall", preference: .playlists).first?.id,
            "pl"
        )
    }

    func testArtistPreferencePutsArtistsFirst() {
        let artist = MusicCandidate(
            id: "ar", kind: .artist, source: .library,
            title: "Nightfall", artist: "", album: ""
        )
        let track = song("song", "Nightfall", source: .library)

        // Without the artist scope a song leads; with it, the artist row does.
        XCTAssertEqual(Ranking.rank([track, artist], query: "nightfall").first?.id, "song")
        XCTAssertEqual(
            Ranking.rank([track, artist], query: "nightfall", preference: .artists).first?.id,
            "ar"
        )
    }

    /// Typing an artist's name still surfaces their row by default (its title is
    /// the artist), which is how the artist page is reachable outside the scope.
    func testExactArtistNameSurfacesTheArtistRow() {
        let artist = MusicCandidate(
            id: "ar", kind: .artist, source: .library,
            title: "Radiohead", artist: "Radiohead", album: ""
        )
        let track = song("song", "Creep", artist: "Radiohead", source: .library)
        XCTAssertEqual(Ranking.rank([track, artist], query: "radiohead").first?.id, "ar")
    }

    // MARK: - rankWithin

    func testRankWithinArtistRanksByTitle() {
        let tracks = [
            song("a", "Karma Police", artist: "Radiohead"),
            song("b", "Creep", artist: "Radiohead")
        ]
        XCTAssertEqual(Ranking.rankWithin(tracks, query: "creep").map(\.id), ["b"])
    }

    /// The whole point of `rankWithin`: the artist's name is on every
    /// track, so the usual artist fallback would return the entire catalogue.
    func testRankWithinArtistIgnoresTheArtistName() {
        let tracks = [
            song("a", "Karma Police", artist: "Radiohead"),
            song("b", "Creep", artist: "Radiohead")
        ]
        XCTAssertTrue(Ranking.rankWithin(tracks, query: "radio").isEmpty)
    }

    func testRankWithinArtistIgnoresTheAlbumName() {
        let tracks = [song("a", "Creep", artist: "Radiohead", album: "Pablo Honey")]
        XCTAssertTrue(Ranking.rankWithin(tracks, query: "pablo").isEmpty)
    }

    func testRankWithinArtistToleratesTypos() {
        let tracks = [
            song("a", "Karma Police", artist: "Radiohead"),
            song("b", "Creep", artist: "Radiohead")
        ]
        XCTAssertEqual(Ranking.rankWithin(tracks, query: "crep").map(\.id), ["b"])
    }

    func testRankWithinArtistRespectsTheLimit() {
        let tracks = (0..<10).map { song("s\($0)", "Song \($0)", artist: "Band") }
        XCTAssertEqual(Ranking.rankWithin(tracks, query: "song", limit: 3).count, 3)
    }

    func testRankWithinArtistEmptyQueryReturnsThePrefix() {
        let tracks = (0..<5).map { song("s\($0)", "Song \($0)", artist: "Band") }
        XCTAssertEqual(Ranking.rankWithin(tracks, query: "  ", limit: 2).map(\.id), ["s0", "s1"])
    }
}
