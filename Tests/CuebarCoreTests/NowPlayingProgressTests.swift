import XCTest
@testable import CuebarCore

final class NowPlayingProgressTests: XCTestCase {
    private let poll = Date(timeIntervalSinceReferenceDate: 1000)

    func testInterpolatesWhilePlaying() {
        let now = poll.addingTimeInterval(5)
        XCTAssertEqual(
            NowPlayingProgress.position(reported: 10, duration: 200, isPlaying: true, lastPoll: poll, now: now),
            15, accuracy: 0.001
        )
    }

    func testFrozenWhenPaused() {
        let now = poll.addingTimeInterval(5)
        XCTAssertEqual(
            NowPlayingProgress.position(reported: 10, duration: 200, isPlaying: false, lastPoll: poll, now: now),
            10, accuracy: 0.001
        )
    }

    func testClampsToDuration() {
        let now = poll.addingTimeInterval(500)
        XCTAssertEqual(
            NowPlayingProgress.position(reported: 10, duration: 200, isPlaying: true, lastPoll: poll, now: now),
            200, accuracy: 0.001
        )
    }

    func testNoDurationDoesNotClamp() {
        XCTAssertEqual(
            NowPlayingProgress.position(reported: 10, duration: nil, isPlaying: false, lastPoll: poll, now: poll),
            10, accuracy: 0.001
        )
    }

    func testNilLastPollDoesNotAdvance() {
        let now = poll.addingTimeInterval(5)
        XCTAssertEqual(
            NowPlayingProgress.position(reported: 10, duration: 200, isPlaying: true, lastPoll: nil, now: now),
            10, accuracy: 0.001
        )
    }

    func testFraction() {
        XCTAssertEqual(NowPlayingProgress.fraction(position: 50, duration: 200) ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(NowPlayingProgress.fraction(position: 500, duration: 200) ?? -1, 1.0, accuracy: 0.001)
        XCTAssertNil(NowPlayingProgress.fraction(position: 50, duration: nil))
        XCTAssertNil(NowPlayingProgress.fraction(position: 50, duration: 0))
    }
}
