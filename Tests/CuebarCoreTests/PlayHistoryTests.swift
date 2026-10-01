import XCTest
@testable import CuebarCore

final class PlayHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cuebar-history-\(UUID().uuidString).json")
    }

    // MARK: - Notification parsing

    func testParsesPersistentIDAsSixteenHexDigits() {
        // The value captured from a real Music notification, and the ID
        // AppleScript reports for the same track.
        let event = PlayerInfoEvent.parse([
            "Player State": "Playing",
            "PersistentID": NSNumber(value: 495_800_278_932_627_889 as Int64)
        ])
        XCTAssertEqual(event?.persistentID, "06E16FBA1151A1B1")
        XCTAssertEqual(event?.isPlaying, true)
    }

    func testParsesPausedAndStopped() {
        let paused = PlayerInfoEvent.parse(["Player State": "Paused", "PersistentID": NSNumber(value: 1)])
        XCTAssertEqual(paused?.isPlaying, false)
        XCTAssertEqual(paused?.loadedTrackID, "0000000000000001")

        let stopped = PlayerInfoEvent.parse(["Player State": "Stopped"])
        XCTAssertEqual(stopped?.isStopped, true)
        XCTAssertNil(stopped?.loadedTrackID)
    }

    func testParseWithoutUserInfo() {
        XCTAssertNil(PlayerInfoEvent.parse(nil))
    }

    // MARK: - Recording

    func testRecordsOnlyPlayingTracks() {
        let history = PlayHistory()
        XCTAssertTrue(history.record(PlayerInfoEvent(persistentID: "A", isPlaying: true), at: now))
        XCTAssertFalse(history.record(PlayerInfoEvent(persistentID: "B", isPlaying: false), at: now))
        XCTAssertFalse(history.record(PlayerInfoEvent(persistentID: nil, isPlaying: true), at: now))
        XCTAssertEqual(history.all.map(\.persistentID), ["A"])
    }

    func testReplayMovesTrackToTheFrontOnce() {
        let history = PlayHistory()
        history.record("A", at: now)
        history.record("B", at: now.addingTimeInterval(10))
        history.record("A", at: now.addingTimeInterval(20))
        XCTAssertEqual(history.all.map(\.persistentID), ["A", "B"])
        XCTAssertEqual(history.all.first?.playedAt, now.addingTimeInterval(20))
    }

    func testLimitDropsTheOldest() {
        let history = PlayHistory(limit: 3)
        for (index, id) in ["A", "B", "C", "D"].enumerated() {
            history.record(id, at: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(history.all.map(\.persistentID), ["D", "C", "B"])
    }

    func testPersistsAcrossInstances() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = PlayHistory(fileURL: url)
        first.record("A", at: now)
        first.record("B", at: now.addingTimeInterval(5))

        let second = PlayHistory(fileURL: url)
        XCTAssertEqual(second.all.map(\.persistentID), ["B", "A"])
    }

    func testCorruptFileStartsEmpty() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(PlayHistory(fileURL: url).all.isEmpty)
    }

    // MARK: - Merging with Music's played dates

    private func song(_ id: String) -> MusicCandidate {
        MusicCandidate(
            id: id, kind: .song, source: .library,
            title: "Song \(id)", artist: "Artist", album: "Album", persistentID: id
        )
    }

    func testLiveLogOutranksStaleMusicDates() {
        let history = PlayHistory()
        history.record("NEW", at: now.addingTimeInterval(-60))

        // Music's stamp for "OLD" is two days old and has none for "NEW".
        let fromMusic = [PlayedEntry(persistentID: "OLD", secondsAgo: 2 * 86_400)]
        let shelf = RecentlyPlayed.tracks(
            from: fromMusic + history.entries(now: now),
            library: [song("OLD"), song("NEW")],
            now: now
        )
        XCTAssertEqual(shelf.map(\.id), ["NEW", "OLD"])
    }

    func testNewestPlayWinsWhenBothSourcesKnowATrack() {
        let history = PlayHistory()
        history.record("A", at: now.addingTimeInterval(-30))

        let shelf = RecentlyPlayed.tracks(
            from: [PlayedEntry(persistentID: "A", secondsAgo: 5_000)] + history.entries(now: now),
            library: [song("A")],
            now: now
        )
        XCTAssertEqual(shelf.count, 1)
        XCTAssertEqual(shelf.first?.playedAt, now.addingTimeInterval(-30))
    }
}
