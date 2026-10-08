import XCTest
@testable import CuebarCore

final class AlbumFactsTests: XCTestCase {
    private func song(
        _ id: String,
        title: String = "Track",
        duration: Double? = nil,
        year: Int? = nil,
        genre: String? = nil,
        disc: Int? = nil,
        track: Int? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: "Band",
            album: "Record",
            durationSeconds: duration,
            persistentID: id,
            discNumber: disc,
            trackNumber: track,
            year: year,
            genre: genre
        )
    }

    private func album(
        trackCount: Int? = nil,
        duration: Double? = nil,
        year: Int? = nil,
        genre: String? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: "library:album:x",
            kind: .album,
            source: .library,
            title: "Record",
            artist: "Band",
            album: "Record",
            durationSeconds: duration,
            trackCount: trackCount,
            year: year,
            genre: genre
        )
    }

    /// The exact line the view shows.
    func testFullSummary() {
        let facts = AlbumFacts(year: 2007, genre: "Alternative", trackCount: 10, durationSeconds: 2520)
        XCTAssertEqual(facts.summary, "2007 · Alternative · 10 tracks · 42 min")
    }

    func testSingularTrack() {
        let facts = AlbumFacts(year: 1999, genre: "Pop", trackCount: 1, durationSeconds: 200)
        XCTAssertEqual(facts.summary, "1999 · Pop · 1 track · 3 min")
    }

    func testMissingPartsAreDroppedNotBlanked() {
        let facts = AlbumFacts(year: nil, genre: nil, trackCount: 4, durationSeconds: nil)
        XCTAssertEqual(facts.summary, "4 tracks")
    }

    func testEmptyGenreIsDropped() {
        let facts = AlbumFacts(year: 2001, genre: "", trackCount: 2, durationSeconds: 120)
        XCTAssertEqual(facts.summary, "2001 · 2 tracks · 2 min")
    }

    func testZeroTrackCountIsDropped() {
        let facts = AlbumFacts(year: 2020, genre: "Jazz", trackCount: 0, durationSeconds: nil)
        XCTAssertEqual(facts.summary, "2020 · Jazz")
    }

    func testSubThirtySecondsRoundsToNothing() {
        XCTAssertNil(AlbumFacts.minutes(20))
        XCTAssertNil(AlbumFacts.minutes(nil))
        XCTAssertNil(AlbumFacts.minutes(0))
    }

    func testMinutesRoundToNearest() {
        XCTAssertEqual(AlbumFacts.minutes(89), 1)
        XCTAssertEqual(AlbumFacts.minutes(2520), 42)
    }

    /// Built from an album row plus its tracks: the track list wins for the
    /// count and the total runtime.
    func testDerivesFromTracks() {
        let album = album(trackCount: 99, duration: 9999, year: 2007, genre: "Alternative")
        let tracks = [
            song("a", duration: 100),
            song("b", duration: 100),
            song("c", duration: 100)
        ]
        let facts = AlbumFacts(album: album, tracks: tracks)
        XCTAssertEqual(facts.summary, "2007 · Alternative · 3 tracks · 5 min")
    }

    /// With no tracks loaded it falls back to the album row's own totals.
    func testFallsBackToAlbumRowWhenTracksAreEmpty() {
        let album = album(trackCount: 12, duration: 2400, year: 1991, genre: "Rock")
        let facts = AlbumFacts(album: album, tracks: [])
        XCTAssertEqual(facts.summary, "1991 · Rock · 12 tracks · 40 min")
    }

    func testAlbumYearGenreComeFromTracksWhenTheRowHasNone() {
        let album = album(trackCount: 2)
        let tracks = [song("a", year: 1997, genre: "Electronic"), song("b", year: 1997, genre: "Electronic")]
        XCTAssertEqual(AlbumFacts(album: album, tracks: tracks).summary, "2 tracks")
    }
}

final class AlbumTrackListTests: XCTestCase {
    private func song(
        _ id: String,
        disc: Int? = nil,
        track: Int? = nil,
        duration: Double? = 200
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: "Track \(id)",
            artist: "Band",
            album: "Record",
            durationSeconds: duration,
            persistentID: id,
            discNumber: disc,
            trackNumber: track
        )
    }

    func testSingleDiscUsesPlainTrackNumbers() {
        let list = AlbumTrackList(tracks: [
            song("a", track: 1),
            song("b", track: 2),
            song("c", track: 3)
        ])
        XCTAssertEqual(list.entries.map(\.number), ["1", "2", "3"])
    }

    func testMultiDiscShowsDiscAndTrack() {
        let list = AlbumTrackList(tracks: [
            song("a", disc: 1, track: 1),
            song("b", disc: 1, track: 2),
            song("c", disc: 2, track: 1)
        ])
        XCTAssertEqual(list.entries.map(\.number), ["1-1", "1-2", "2-1"])
    }

    /// A track with no number tag falls back to its place in the list, so the
    /// column is never blank.
    func testUntaggedTracksFallBackToPosition() {
        let list = AlbumTrackList(tracks: [song("a"), song("b"), song("c")])
        XCTAssertEqual(list.entries.map(\.number), ["1", "2", "3"])
    }

    func testZeroOrNegativeTagsFallBackToPosition() {
        let list = AlbumTrackList(tracks: [song("a", track: 0), song("b", track: -4)])
        XCTAssertEqual(list.entries.map(\.number), ["1", "2"])
    }

    /// A disc number present on only one track still means multi-disc.
    func testSingleTaggedDiscCountsAsMultiDisc() {
        let list = AlbumTrackList(tracks: [song("a", disc: 2, track: 1), song("b", track: 2)])
        XCTAssertEqual(list.entries.map(\.number), ["2-1", "1-2"])
    }

    func testOrderIsPreservedExactly() {
        let list = AlbumTrackList(tracks: [song("z", track: 3), song("y", track: 1), song("x", track: 2)])
        XCTAssertEqual(list.entries.map(\.id), ["z", "y", "x"])
    }

    func testEmptyList() {
        XCTAssertTrue(AlbumTrackList(tracks: []).entries.isEmpty)
    }
}

final class TimeFormatTests: XCTestCase {
    func testMinutesAndSeconds() {
        XCTAssertEqual(TimeFormat.mmss(237), "3:57")
        XCTAssertEqual(TimeFormat.mmss(60), "1:00")
        XCTAssertEqual(TimeFormat.mmss(9), "0:09")
    }

    func testInvalidInputReadsAsZero() {
        XCTAssertEqual(TimeFormat.mmss(nil), "0:00")
        XCTAssertEqual(TimeFormat.mmss(-5), "0:00")
        XCTAssertEqual(TimeFormat.mmss(.nan), "0:00")
    }

    func testRoundsToNearestSecond() {
        XCTAssertEqual(TimeFormat.mmss(59.6), "1:00")
    }
}
