import XCTest
@testable import CuebarCore

final class CommandExecutorTests: XCTestCase {
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

    func testTransportCommands() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.execute(.pause, selected: nil)
        try await executor.execute(.resume, selected: nil)
        try await executor.execute(.next, selected: nil)
        try await executor.execute(.previous, selected: nil)

        XCTAssertEqual(controller.calls, [.pause, .resume, .next, .previous])
    }

    func testShuffleVariants() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.execute(.shuffle(.toggle), selected: nil)
        try await executor.execute(.shuffle(.on), selected: nil)
        try await executor.execute(.shuffle(.off), selected: nil)

        XCTAssertEqual(controller.calls, [.shuffle(nil), .shuffle(true), .shuffle(false)])
    }

    func testPlayUsesSelection() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.execute(.play(query: "song"), selected: song("abc"))
        XCTAssertEqual(controller.calls, [.play("abc")])
    }

    func testPlayWithoutSelectionThrows() async {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        do {
            try await executor.execute(.play(query: "song"), selected: nil)
            XCTFail("Expected noSelection error")
        } catch {
            XCTAssertTrue(error is CommandError)
        }
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func testBarePlayResumes() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.execute(.play(query: ""), selected: nil)
        XCTAssertEqual(controller.calls, [.resume])
    }

    func testExecuteAlbumPlaysTracksInOrder() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.executeAlbum([song("a"), song("b")])
        XCTAssertEqual(controller.calls, [.playAlbum(["a", "b"])])
    }

    func testShuffleEnabledReadsBackState() async throws {
        let controller = MockMusicController()
        controller.shuffleEnabledResult = true

        let value = try await controller.shuffleEnabled()
        XCTAssertTrue(value)
        XCTAssertEqual(controller.calls, [.shuffleEnabled])
    }

    func testRepeatCommands() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)

        try await executor.execute(.setRepeat(.all), selected: nil)
        try await executor.execute(.setRepeat(.one), selected: nil)
        XCTAssertEqual(controller.calls, [.setRepeat(.all), .setRepeat(.one)])
    }

    func testExecutePlaylistPlaysIt() async throws {
        let controller = MockMusicController()
        let executor = CommandExecutor(controller: controller)
        let playlist = MusicCandidate(
            id: "library:playlist:PID",
            kind: .playlist,
            source: .library,
            title: "Focus",
            artist: "",
            album: "",
            persistentID: "PID",
            trackCount: 5
        )

        try await executor.executePlaylist(playlist)
        XCTAssertEqual(controller.calls, [.playPlaylist("library:playlist:PID")])
    }
}
