import XCTest
@testable import CuebarCore

final class LibraryArtistIndexTests: XCTestCase {
    private func song(
        _ id: String,
        _ title: String,
        album: String = "Record",
        artist: String = "Artist",
        albumArtist: String? = nil,
        disc: Int? = nil,
        track: Int? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: album,
            persistentID: id,
            albumArtist: albumArtist,
            discNumber: disc,
            trackNumber: track
        )
    }

    func testGroupsTracksIntoOneArtist() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "One", artist: "Band"),
            song("2", "Two", artist: "Band")
        ])
        XCTAssertEqual(index.artists.count, 1)
        let artist = index.artists[0]
        XCTAssertEqual(artist.kind, .artist)
        XCTAssertEqual(artist.source, .library)
        XCTAssertEqual(artist.title, "Band")
        XCTAssertEqual(artist.trackCount, 2)
    }

    func testSeparateArtistsAreSeparateRows() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "One", artist: "Band"),
            song("2", "Two", artist: "Other Band")
        ])
        XCTAssertEqual(Set(index.artists.map(\.title)), ["Band", "Other Band"])
    }

    func testCompilationsCollapseUnderAlbumArtist() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "A", album: "Hits", artist: "Artist A", albumArtist: "Various Artists"),
            song("2", "B", album: "Hits", artist: "Artist B", albumArtist: "Various Artists")
        ])
        XCTAssertEqual(index.artists.count, 1)
        XCTAssertEqual(index.artists[0].title, "Various Artists")
        XCTAssertEqual(index.artists[0].trackCount, 2)
    }

    func testFeatureCreditsAreNotSplit() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "One", artist: "Drake"),
            song("2", "Two", artist: "Drake feat. J. Cole")
        ])
        XCTAssertEqual(index.artists.count, 2)
    }

    func testNameMatchingIgnoresCaseAndPunctuation() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "One", artist: "a-ha"),
            song("2", "Two", artist: "A HA")
        ])
        XCTAssertEqual(index.artists.count, 1)
        XCTAssertEqual(index.artists[0].trackCount, 2)
    }

    func testSongsWithoutAnArtistAreExcluded() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "Loose", artist: ""),
            song("2", "Kept", artist: "Band")
        ])
        XCTAssertEqual(index.artists.map(\.title), ["Band"])
    }

    func testTracksAreOrderedByAlbumThenTrack() {
        let index = LibraryArtistIndex(tracks: [
            song("c", "Zed", album: "Second", artist: "Band", track: 1),
            song("a", "One", album: "First", artist: "Band", track: 1),
            song("b", "Two", album: "First", artist: "Band", track: 2)
        ])
        let artist = index.artists[0]
        XCTAssertEqual(index.tracks(forArtistID: artist.id)?.map(\.id), ["a", "b", "c"])
    }

    func testArtworkTrackIDIsSet() {
        let index = LibraryArtistIndex(tracks: [song("1", "One", artist: "Band")])
        XCTAssertEqual(index.artists[0].artworkTrackID, "1")
        XCTAssertNil(index.artists[0].persistentID)
    }

    func testArtistIDIsDeterministic() {
        let tracks = [song("1", "One", artist: "Band")]
        XCTAssertEqual(
            LibraryArtistIndex(tracks: tracks).artists[0].id,
            LibraryArtistIndex(tracks: tracks).artists[0].id
        )
    }

    func testUnknownArtistIDReturnsNil() {
        let index = LibraryArtistIndex(tracks: [song("1", "One", artist: "Band")])
        XCTAssertNil(index.tracks(forArtistID: "library:artist:nope"))
    }

    func testArtistSubtitleIsTheSongCountOnly() {
        let index = LibraryArtistIndex(tracks: [
            song("1", "One", artist: "Band"),
            song("2", "Two", artist: "Band")
        ])
        XCTAssertEqual(index.artists[0].subtitle, "2 songs")
    }

    func testSingleSongArtistSubtitleIsSingular() {
        let index = LibraryArtistIndex(tracks: [song("1", "One", artist: "Band")])
        XCTAssertEqual(index.artists[0].subtitle, "1 song")
    }
}

/// The `artist ` scope is a hard filter, so it must search the artist pool
/// directly — ranking the whole library first would let song matches crowd
/// every artist out of the result limit.
final class LibraryArtistSearchTests: XCTestCase {
    private func song(_ id: String, _ title: String, artist: String) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: "Record",
            persistentID: id
        )
    }

    private func provider() -> LibrarySearchProvider {
        let provider = LibrarySearchProvider()
        provider.setIndex([
            song("1", "Creep", artist: "Radiohead"),
            song("2", "Karma Police", artist: "Radiohead"),
            song("3", "Take On Me", artist: "a-ha")
        ])
        return provider
    }

    func testSearchArtistsReturnsArtistRowsOnly() {
        let results = provider().searchArtists("radio", limit: 40)
        XCTAssertEqual(results.map(\.title), ["Radiohead"])
        XCTAssertTrue(results.allSatisfy { $0.kind == .artist })
    }

    func testSearchArtistsIsNotCrowdedOutBySongs() {
        // Many songs match "hit" through their artist field; the artist rows must
        // still come back.
        let provider = LibrarySearchProvider()
        provider.setIndex(
            (0..<120).map { song("s\($0)", "Hit \($0)", artist: "Hits Machine") }
                + [song("x", "Something", artist: "Hit Parade")]
        )
        let results = provider.searchArtists("hit", limit: 40)
        XCTAssertEqual(Set(results.map(\.title)), ["Hits Machine", "Hit Parade"])
    }

    func testSearchArtistsEmptyTermIsAlphabetical() {
        let results = provider().searchArtists("   ", limit: 40)
        XCTAssertEqual(results.map(\.title), ["a-ha", "Radiohead"])
    }

    func testTracksForArtistIDRoundTrips() {
        let provider = provider()
        let artist = provider.artists().first { $0.title == "Radiohead" }!
        XCTAssertEqual(provider.tracks(forArtistID: artist.id)?.map(\.title), ["Creep", "Karma Police"])
        XCTAssertNil(provider.tracks(forArtistID: "library:artist:nope"))
    }

    func testArtistBrowseReturnsArtists() async {
        let items = await provider().browse(.artists, limit: 40)
        XCTAssertEqual(Set(items.map(\.title)), ["a-ha", "Radiohead"])
    }

    func testGeneralSearchSurfacesArtistRows() async throws {
        let results = try await provider().search("radiohead", limit: 40)
        XCTAssertEqual(results.first?.kind, .artist)
        XCTAssertEqual(results.first?.title, "Radiohead")
    }
}
