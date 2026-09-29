import XCTest
@testable import CuebarCore

final class NowPlayingTests: XCTestCase {
    private let sep = NowPlayingTrack.fieldSeparator

    // MARK: - Parsing

    func testParsesPlayingTrack() {
        let raw = ["playing", "Take On Me", "a-ha", "Hunting High and Low", "PID123", "42.5", "225.7"]
            .joined(separator: sep)

        let track = NowPlayingTrack.parse(raw)

        XCTAssertEqual(track?.state, .playing)
        XCTAssertTrue(track?.isPlaying == true)
        XCTAssertEqual(track?.title, "Take On Me")
        XCTAssertEqual(track?.artist, "a-ha")
        XCTAssertEqual(track?.album, "Hunting High and Low")
        XCTAssertEqual(track?.persistentID, "PID123")
        XCTAssertEqual(track?.position, 42.5)
        XCTAssertEqual(track?.duration, 225.7)
    }

    func testParsesPausedTrack() {
        let raw = ["paused", "Nightfall", "Artist", "Album", "PID", "10", "200"]
            .joined(separator: sep)

        let track = NowPlayingTrack.parse(raw)
        XCTAssertEqual(track?.state, .paused)
        XCTAssertFalse(track?.isPlaying == true)
        XCTAssertEqual(track?.title, "Nightfall")
    }

    func testParsesStoppedTrackWithMissingFields() {
        let raw = ["stopped", "Just A Title"].joined(separator: sep)

        let track = NowPlayingTrack.parse(raw)
        XCTAssertEqual(track?.state, .stopped)
        XCTAssertEqual(track?.title, "Just A Title")
        XCTAssertEqual(track?.artist, "")
        XCTAssertNil(track?.persistentID)
        XCTAssertNil(track?.position)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(NowPlayingTrack.parse(""))
        XCTAssertNil(NowPlayingTrack.parse("   \n"))
    }

    /// When nothing is loaded the script returns just the state.
    func testStateOnlyReturnsNil() {
        XCTAssertNil(NowPlayingTrack.parse("paused"))
        XCTAssertNil(NowPlayingTrack.parse("stopped"))
    }

    func testMalformedMissingTitleReturnsNil() {
        let raw = ["playing", ""].joined(separator: sep)
        XCTAssertNil(NowPlayingTrack.parse(raw))
    }

    func testMissingValueCoercion() {
        let raw = ["playing", "Song", "missing value", "missing value", "", "missing value", "0"]
            .joined(separator: sep)
        let track = NowPlayingTrack.parse(raw)
        XCTAssertEqual(track?.artist, "")
        XCTAssertEqual(track?.album, "")
        XCTAssertNil(track?.persistentID)
        XCTAssertNil(track?.position)
    }

    func testSubtitleOmitsEmptyAndDuplicateFields() {
        let track = NowPlayingTrack(state: .playing, title: "Song", artist: "Artist", album: "Song")
        XCTAssertEqual(track.subtitle, "Artist")
    }

    // MARK: - Composition

    private func song(_ id: String) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: "Song",
            artist: "Artist",
            album: "Album",
            persistentID: id
        )
    }

    private let track = NowPlayingTrack(
        state: .playing,
        title: "Take On Me",
        artist: "a-ha",
        album: "Hunting High and Low",
        persistentID: "PID"
    )

    func testNowPlayingIsFirstWhenQueryIsEmpty() {
        let items = PaletteListComposer.compose(
            query: "",
            nowPlaying: track,
            commands: CommandCatalog.matches(for: ""),
            music: []
        )

        guard case .nowPlaying = items.first else {
            return XCTFail("Expected the now-playing row first")
        }
        XCTAssertEqual(items.first?.id, "nowPlaying")
    }

    func testNowPlayingHiddenWhenQueryIsPresent() {
        let items = PaletteListComposer.compose(
            query: "pause",
            nowPlaying: track,
            commands: CommandCatalog.matches(for: "pause"),
            music: [song("s1")]
        )

        XCTAssertFalse(items.contains { $0.id == "nowPlaying" })
    }

    func testNoNowPlayingRowWhenNothingLoaded() {
        let items = PaletteListComposer.compose(
            query: "",
            nowPlaying: nil,
            commands: CommandCatalog.matches(for: ""),
            music: []
        )

        XCTAssertFalse(items.contains { $0.id == "nowPlaying" })
        XCTAssertFalse(items.isEmpty, "Empty query should still list commands")
    }

    // MARK: - Controller mock

    func testMockNowPlayingIsReturned() async throws {
        let controller = MockMusicController()
        controller.nowPlayingResult = track
        let result = try await controller.nowPlaying()
        XCTAssertEqual(result, track)
    }

    // MARK: - Shuffle / repeat

    func testParsesShuffleAndRepeat() {
        let raw = ["playing", "Song", "Artist", "Album", "PID", "10", "200", "true", "all"]
            .joined(separator: sep)
        let parsed = NowPlayingTrack.parse(raw)
        XCTAssertEqual(parsed?.shuffleEnabled, true)
        XCTAssertEqual(parsed?.repeatMode, .all)
    }

    func testParsesWithoutShuffleRepeatFields() {
        let raw = ["paused", "Song", "Artist", "Album", "PID", "10", "200"]
            .joined(separator: sep)
        let parsed = NowPlayingTrack.parse(raw)
        XCTAssertEqual(parsed?.shuffleEnabled, false)
        XCTAssertEqual(parsed?.repeatMode, .off)
    }

    func testShuffleRepeatMissingValue() {
        let raw = ["playing", "Song", "Artist", "Album", "", "missing value", "0", "missing value", "missing value"]
            .joined(separator: sep)
        let parsed = NowPlayingTrack.parse(raw)
        XCTAssertEqual(parsed?.shuffleEnabled, false)
        XCTAssertEqual(parsed?.repeatMode, .off)
    }

    func testRepeatTogglingAll() {
        XCTAssertEqual(RepeatMode.off.togglingAll, .all)
        XCTAssertEqual(RepeatMode.all.togglingAll, .off)
        XCTAssertEqual(RepeatMode.one.togglingAll, .off)
    }

    func testCopyReplacesSelectedFields() {
        let original = NowPlayingTrack(state: .playing, title: "S", artist: "A", album: "B")
        let paused = original.copy(state: .paused, shuffleEnabled: true)
        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.shuffleEnabled, true)
        XCTAssertEqual(original.state, .playing)
        XCTAssertEqual(original.shuffleEnabled, false)
    }
}
