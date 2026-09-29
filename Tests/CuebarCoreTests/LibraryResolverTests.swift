import XCTest
@testable import CuebarCore

final class LibraryResolverTests: XCTestCase {
    private func librarySong(_ id: String, _ title: String, artist: String) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: "",
            persistentID: id
        )
    }

    private func catalogSong(_ id: String, _ title: String, artist: String) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .catalog,
            title: title,
            artist: artist,
            album: ""
        )
    }

    func testExactTitleAndArtistResolves() {
        let library = [librarySong("L1", "Blinding Lights", artist: "The Weeknd")]
        let catalog = catalogSong("C1", "Blinding Lights", artist: "The Weeknd")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "L1")
    }

    func testPrefersMatchingArtistAmongSameTitle() {
        let library = [
            librarySong("cover", "Blinding Lights", artist: "Kidz Bop Kids"),
            librarySong("original", "Blinding Lights", artist: "The Weeknd")
        ]
        let catalog = catalogSong("C1", "Blinding Lights", artist: "The Weeknd")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "original")
    }

    func testAmbiguousTitleWithDifferentArtistDoesNotGuess() {
        let library = [
            librarySong("adele", "Hello", artist: "Adele"),
            librarySong("lionel", "Hello", artist: "Lionel Richie")
        ]
        let catalog = catalogSong("C1", "Hello", artist: "Some Other Band")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testSingleCopyWithDifferentKnownArtistDoesNotResolve() {
        let library = [librarySong("only", "Rare Song", artist: "Somebody")]
        let catalog = catalogSong("C1", "Rare Song", artist: "A Different Performer")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testRealWorldYesterdayDoesNotResolveToCover() {
        // The Beatles' "Yesterday" is in the catalog only; the library's single
        // "Yesterday" is a different song by a different artist.
        let library = [librarySong("goddard", "Yesterday", artist: "goddard.")]
        let catalog = catalogSong("C1", "Yesterday", artist: "The Beatles")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testSingleCopyWithUnknownCatalogArtistResolves() {
        let library = [librarySong("only", "Rare Song", artist: "Somebody")]
        let catalog = catalogSong("C1", "Rare Song", artist: "")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "only")
    }

    func testAmbiguousTitleWithUnknownCatalogArtistDoesNotResolve() {
        let library = [
            librarySong("a", "Hello", artist: "Adele"),
            librarySong("b", "Hello", artist: "Lionel Richie")
        ]
        let catalog = catalogSong("C1", "Hello", artist: "")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testCatalogAlbumNeverResolvesToSong() {
        let library = [librarySong("rod", "25", artist: "Rod Wave")]
        let catalog = MusicCandidate(
            id: "catalog:album:1544494115",
            kind: .album,
            source: .catalog,
            title: "25",
            artist: "Adele",
            album: ""
        )
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testArtistTokensMustAgree() {
        let library = [librarySong("museum", "Song", artist: "Museum")]
        let catalog = catalogSong("C1", "Song", artist: "Muse")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testNearTitleWithUnknownCatalogArtistDoesNotResolve() {
        let library = [librarySong("L1", "Blinding Lights", artist: "The Weeknd")]
        let catalog = catalogSong("C1", "Blinding Light", artist: "")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testNearTitleWithMatchingArtistResolves() {
        let library = [librarySong("L1", "Blinding Lights", artist: "The Weeknd")]
        let catalog = catalogSong("C1", "Blinding Light", artist: "The Weeknd")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "L1")
    }

    func testUnrelatedSongDoesNotResolve() {
        let library = [librarySong("L1", "Sunshine Reggae", artist: "Laid Back")]
        let catalog = catalogSong("C1", "Hey Jude", artist: "The Beatles")
        XCTAssertNil(LibraryResolver.resolve(catalog, in: library))
    }

    func testLibraryCandidatePassesThrough() {
        let library = [librarySong("L1", "Song", artist: "Artist")]
        XCTAssertEqual(LibraryResolver.resolve(library[0], in: library)?.id, "L1")
    }

    func testCaseAndDiacriticsAreIgnored() {
        let library = [librarySong("L1", "Café Noir", artist: "Édith Piaf")]
        let catalog = catalogSong("C1", "cafe noir", artist: "edith piaf")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "L1")
    }

    func testArtistNameVariantsMatch() {
        let library = [librarySong("L1", "Come Together", artist: "The Beatles")]
        let catalog = catalogSong("C1", "Come Together", artist: "Beatles")
        XCTAssertEqual(LibraryResolver.resolve(catalog, in: library)?.id, "L1")
    }
}
