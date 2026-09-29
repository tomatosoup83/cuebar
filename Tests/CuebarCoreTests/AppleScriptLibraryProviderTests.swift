import XCTest
@testable import CuebarCore

final class AppleScriptLibraryProviderTests: XCTestCase {
    private let field = AppleScriptLibraryProvider.fieldSeparator
    private let list = AppleScriptLibraryProvider.listSeparator

    private func joined(_ values: [String]) -> String {
        values.joined(separator: field)
    }

    private func raw(_ sections: [String]) -> String {
        sections.joined(separator: list)
    }

    func testParsesAllSections() {
        let text = raw([
            joined(["One", "Two"]),            // names
            joined(["Band", "Band"]),          // artists
            joined(["Record", "Record"]),      // albums
            joined(["ID1", "ID2"]),            // ids
            joined(["100.0", "50.0"]),         // durations
            joined(["Band", "Band"]),          // album artists
            joined(["1", "1"]),                // disc numbers
            joined(["1", "2"])                 // track numbers
        ])

        let tracks = AppleScriptLibraryProvider.parse(text)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].title, "One")
        XCTAssertEqual(tracks[0].albumArtist, "Band")
        XCTAssertEqual(tracks[0].discNumber, 1)
        XCTAssertEqual(tracks[0].trackNumber, 1)
        XCTAssertEqual(tracks[1].trackNumber, 2)
        XCTAssertEqual(tracks[0].persistentID, "ID1")
    }

    func testMissingTrailingSectionsAreTolerated() {
        // An older/short response (5 sections) still parses.
        let text = raw([
            joined(["One"]),
            joined(["Band"]),
            joined(["Record"]),
            joined(["ID1"]),
            joined(["100.0"])
        ])
        let tracks = AppleScriptLibraryProvider.parse(text)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertNil(tracks[0].albumArtist)
        XCTAssertNil(tracks[0].discNumber)
        XCTAssertNil(tracks[0].trackNumber)
    }

    func testMissingValueBecomesEmpty() {
        let text = raw([
            joined(["One"]),
            joined(["Band"]),
            joined(["Record"]),
            joined(["ID1"]),
            joined(["100.0"]),
            joined(["missing value"]),
            joined(["missing value"]),
            joined(["missing value"])
        ])
        let tracks = AppleScriptLibraryProvider.parse(text)
        XCTAssertNil(tracks[0].albumArtist)
        XCTAssertNil(tracks[0].discNumber)
        XCTAssertNil(tracks[0].trackNumber)
    }

    func testSkipsTracksWithoutPersistentID() {
        let text = raw([
            joined(["One", "Two"]),
            joined(["Band", "Band"]),
            joined(["Record", "Record"]),
            joined(["", "ID2"]),
            joined(["100.0", "50.0"]),
            joined(["Band", "Band"]),
            joined(["1", "1"]),
            joined(["1", "2"])
        ])
        let tracks = AppleScriptLibraryProvider.parse(text)
        XCTAssertEqual(tracks.map(\.persistentID), ["ID2"])
    }

    // MARK: - Playlists

    private func playlistRecord(_ name: String, _ id: String, _ count: String, _ first: String) -> String {
        [name, id, count, first].joined(separator: field)
    }

    func testParsesPlaylists() {
        let text = [
            playlistRecord("Focus", "PID1", "12", "T1"),
            playlistRecord("Chill", "PID2", "3", "T2")
        ].joined(separator: list)

        let playlists = AppleScriptLibraryProvider.parsePlaylists(text)
        XCTAssertEqual(playlists.count, 2)

        let first = playlists[0]
        XCTAssertEqual(first.kind, .playlist)
        XCTAssertEqual(first.source, .library)
        XCTAssertEqual(first.title, "Focus")
        XCTAssertEqual(first.persistentID, "PID1")
        XCTAssertEqual(first.trackCount, 12)
        XCTAssertEqual(first.id, "library:playlist:PID1")
        XCTAssertEqual(first.artworkTrackID, "T1")
    }

    func testPlaylistsExcludeQueueAndEmpty() {
        let text = [
            playlistRecord("Focus", "PID1", "12", "T1"),
            playlistRecord(AppleScriptMusicController.albumQueuePlaylistName, "PQ", "5", "T3"),
            playlistRecord("Empty", "PID3", "0", "")
        ].joined(separator: list)

        let playlists = AppleScriptLibraryProvider.parsePlaylists(text)
        XCTAssertEqual(playlists.map(\.title), ["Focus"])
    }

    func testPlaylistsTolerateMissingArtworkTrack() {
        let text = playlistRecord("Focus", "PID1", "4", "missing value")
        let playlists = AppleScriptLibraryProvider.parsePlaylists(text)
        XCTAssertNil(playlists[0].artworkTrackID)
    }
}
