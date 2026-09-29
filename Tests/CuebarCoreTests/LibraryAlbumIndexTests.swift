import XCTest
@testable import CuebarCore

final class LibraryAlbumIndexTests: XCTestCase {
    private func song(
        _ id: String,
        _ title: String,
        album: String,
        artist: String = "Artist",
        albumArtist: String? = nil,
        disc: Int? = nil,
        track: Int? = nil,
        duration: Double? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: duration,
            persistentID: id,
            albumArtist: albumArtist,
            discNumber: disc,
            trackNumber: track
        )
    }

    func testGroupsTracksIntoOneAlbum() {
        let index = LibraryAlbumIndex(tracks: [
            song("1", "One", album: "Record", artist: "Band"),
            song("2", "Two", album: "Record", artist: "Band")
        ])
        XCTAssertEqual(index.albums.count, 1)
        let album = index.albums[0]
        XCTAssertEqual(album.kind, .album)
        XCTAssertEqual(album.source, .library)
        XCTAssertEqual(album.title, "Record")
        XCTAssertEqual(album.artist, "Band")
        XCTAssertEqual(album.trackCount, 2)
    }

    func testOrdersTracksByDiscThenTrackNumber() {
        let index = LibraryAlbumIndex(tracks: [
            song("c", "Third", album: "Record", track: 3),
            song("a", "First", album: "Record", track: 1),
            song("b2", "Second (disc 2)", album: "Record", disc: 2, track: 1),
            song("b", "Second", album: "Record", track: 2)
        ])
        let album = index.albums[0]
        XCTAssertEqual(index.tracks(forAlbumID: album.id)?.map(\.id), ["a", "b", "c", "b2"])
    }

    func testCompilationsStayTogetherViaAlbumArtist() {
        let index = LibraryAlbumIndex(tracks: [
            song("1", "A", album: "Hits", artist: "Artist A", albumArtist: "Various Artists"),
            song("2", "B", album: "Hits", artist: "Artist B", albumArtist: "Various Artists")
        ])
        XCTAssertEqual(index.albums.count, 1)
        XCTAssertEqual(index.albums[0].artist, "Various Artists")
        XCTAssertEqual(index.albums[0].trackCount, 2)
    }

    func testDifferentAlbumArtistsAreDifferentAlbums() {
        let index = LibraryAlbumIndex(tracks: [
            song("1", "A", album: "Live", albumArtist: "Band"),
            song("2", "B", album: "Live", albumArtist: "Other Band")
        ])
        XCTAssertEqual(index.albums.count, 2)
    }

    func testTracksWithoutAlbumAreExcluded() {
        let index = LibraryAlbumIndex(tracks: [
            song("1", "Loose", album: ""),
            song("2", "Kept", album: "Record")
        ])
        XCTAssertEqual(index.albums.count, 1)
        XCTAssertEqual(index.albums[0].title, "Record")
    }

    func testDurationIsSummed() {
        let index = LibraryAlbumIndex(tracks: [
            song("1", "One", album: "Record", duration: 100),
            song("2", "Two", album: "Record", duration: 50)
        ])
        XCTAssertEqual(index.albums[0].durationSeconds, 150)
    }

    func testArtworkTrackIDIsSet() {
        let index = LibraryAlbumIndex(tracks: [song("1", "One", album: "Record")])
        XCTAssertEqual(index.albums[0].artworkTrackID, "1")
        XCTAssertNil(index.albums[0].persistentID)
    }

    func testAlbumIDIsDeterministic() {
        let tracks = [song("1", "One", album: "Record")]
        XCTAssertEqual(
            LibraryAlbumIndex(tracks: tracks).albums[0].id,
            LibraryAlbumIndex(tracks: tracks).albums[0].id
        )
    }

    func testUnknownAlbumIDReturnsNil() {
        let index = LibraryAlbumIndex(tracks: [song("1", "One", album: "Record")])
        XCTAssertNil(index.tracks(forAlbumID: "library:album:nope"))
    }
}
