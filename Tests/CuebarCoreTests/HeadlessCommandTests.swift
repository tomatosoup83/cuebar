import XCTest
@testable import CuebarCore

final class CuebarURLTests: XCTestCase {
    private func request(_ string: String) -> CuebarRequest? {
        CuebarURL.parse(string)
    }

    func testRunCommandParameter() {
        XCTAssertEqual(request("cuebar://run?command=next"), .run(input: "next"))
        XCTAssertEqual(
            request("cuebar://run?command=album%20swag%20ii"),
            .run(input: "album swag ii")
        )
    }

    func testInputParameterAliases() {
        XCTAssertEqual(request("cuebar://run?input=pause"), .run(input: "pause"))
        XCTAssertEqual(request("cuebar://run?q=pause"), .run(input: "pause"))
        XCTAssertEqual(request("cuebar://run?Command=pause"), .run(input: "pause"))
    }

    func testCommandParameterWinsOverTheHost() {
        // A mistyped host must not silently turn a command into a song search.
        XCTAssertEqual(request("cuebar://rn?command=pause"), .run(input: "pause"))
        XCTAssertEqual(request("cuebar://rebuild?command=next"), .run(input: "next"))
    }

    func testRebuildHost() {
        XCTAssertEqual(request("cuebar://rebuild"), .rebuildLibraryIndex)
        XCTAssertEqual(request("cuebar://Reindex"), .rebuildLibraryIndex)
        XCTAssertEqual(request("cuebar://rescan"), .rebuildLibraryIndex)
    }

    func testHostAsInput() {
        XCTAssertEqual(request("cuebar://pause"), .run(input: "pause"))
        XCTAssertEqual(request("cuebar://next"), .run(input: "next"))
        // The input keeps its case: it can be a song name.
        XCTAssertEqual(request("cuebar://Take%20On%20Me"), .run(input: "Take On Me"))
    }

    func testPathJoinsTheInput() {
        XCTAssertEqual(request("cuebar://album/SWAG%20II"), .run(input: "album SWAG II"))
    }

    func testRejectsOtherSchemesAndEmptyRequests() {
        XCTAssertNil(request("https://example.com/?command=pause"))
        XCTAssertNil(request("song://pause"))
        XCTAssertNil(request("cuebar://"))
        XCTAssertNil(request("cuebar://run?command="))
        XCTAssertNil(request("cuebar://run?command=%20%20"))
        XCTAssertNil(request("cuebar://run"))
    }

    func testRequestBridgesToAnAction() throws {
        XCTAssertEqual(try request("cuebar://run?command=pause")?.action(), .music(.pause))
        XCTAssertEqual(try request("cuebar://rebuild")?.action(), .rebuildLibraryIndex)
    }
}

final class HeadlessCommandParserTests: XCTestCase {
    func testTransportCommands() throws {
        XCTAssertEqual(try HeadlessCommandParser.parse("pause"), .music(.pause))
        XCTAssertEqual(try HeadlessCommandParser.parse("next"), .music(.next))
        XCTAssertEqual(try HeadlessCommandParser.parse("skip"), .music(.next))
        XCTAssertEqual(try HeadlessCommandParser.parse("previous"), .music(.previous))
        XCTAssertEqual(try HeadlessCommandParser.parse("play"), .music(.resume))
    }

    func testCatalogCommands() throws {
        XCTAssertEqual(try HeadlessCommandParser.parse("shuffle on"), .music(.shuffle(.on)))
        XCTAssertEqual(try HeadlessCommandParser.parse("repeat track"), .music(.setRepeat(.one)))
        XCTAssertEqual(try HeadlessCommandParser.parse("shuffle"), .music(.shuffle(.toggle)))
    }

    func testRebuildKeywords() throws {
        XCTAssertEqual(try HeadlessCommandParser.parse("rebuild"), .rebuildLibraryIndex)
        XCTAssertEqual(try HeadlessCommandParser.parse("rebuild index"), .rebuildLibraryIndex)
        XCTAssertEqual(try HeadlessCommandParser.parse("REINDEX"), .rebuildLibraryIndex)
    }

    /// The palette matches commands fuzzily because you pick from a list; a URL
    /// has no list, so only an exact command is a command.
    func testFuzzyInputStaysASongSearch() throws {
        XCTAssertEqual(
            try HeadlessCommandParser.parse("rebuilding my library"),
            .music(.play(query: "rebuilding my library"))
        )
        XCTAssertEqual(
            try HeadlessCommandParser.parse("shuffle it up"),
            .music(.play(query: "shuffle it up"))
        )
    }

    func testScopesAreLeftToTheRunner() throws {
        // CommandParser hands the whole string through; the runner parses the
        // scope out of it when it resolves the row.
        XCTAssertEqual(
            try HeadlessCommandParser.parse("album swag ii"),
            .music(.play(query: "album swag ii"))
        )
    }

    func testSongNames() throws {
        XCTAssertEqual(
            try HeadlessCommandParser.parse("take on me"),
            .music(.play(query: "take on me"))
        )
        XCTAssertEqual(
            try HeadlessCommandParser.parse("play take on me"),
            .music(.play(query: "take on me"))
        )
    }

    func testPaletteOnlyCommandsAreRejected() {
        XCTAssertThrowsError(try HeadlessCommandParser.parse("settings")) { error in
            guard case HeadlessCommandError.paletteOnly(let title) = error else {
                return XCTFail("expected paletteOnly, got \(error)")
            }
            XCTAssertEqual(title, "Settings")
        }
        XCTAssertThrowsError(try HeadlessCommandParser.parse("preferences"))
    }

    func testEmptyInput() {
        XCTAssertThrowsError(try HeadlessCommandParser.parse("")) { error in
            XCTAssertEqual(error as? HeadlessCommandError, .emptyInput)
        }
        XCTAssertThrowsError(try HeadlessCommandParser.parse("   \n ")) { error in
            XCTAssertEqual(error as? HeadlessCommandError, .emptyInput)
        }
    }

    func testNeedsIndexedLibrary() {
        XCTAssertTrue(HeadlessAction.music(.play(query: "take on me")).needsIndexedLibrary)
        XCTAssertFalse(HeadlessAction.music(.play(query: "  ")).needsIndexedLibrary)
        XCTAssertFalse(HeadlessAction.music(.pause).needsIndexedLibrary)
        XCTAssertFalse(HeadlessAction.music(.resume).needsIndexedLibrary)
        XCTAssertFalse(HeadlessAction.music(.shuffle(.toggle)).needsIndexedLibrary)
        XCTAssertFalse(HeadlessAction.rebuildLibraryIndex.needsIndexedLibrary)
    }
}

final class HeadlessCommandRunnerTests: XCTestCase {
    // MARK: - Fixtures

    private func song(
        _ id: String,
        title: String,
        artist: String = "a-ha",
        album: String = "Hunting High and Low",
        albumArtist: String? = nil,
        trackNumber: Int? = nil
    ) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: album,
            persistentID: id,
            albumArtist: albumArtist ?? artist,
            discNumber: 1,
            trackNumber: trackNumber
        )
    }

    private func playlist(_ id: String, title: String, trackCount: Int) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .playlist,
            source: .library,
            title: title,
            artist: "",
            album: "",
            persistentID: id,
            trackCount: trackCount
        )
    }

    private func library(
        tracks: [MusicCandidate],
        playlists: [MusicCandidate] = []
    ) -> LibrarySearchProvider {
        let provider = LibrarySearchProvider()
        provider.setIndex(tracks, playlists: playlists)
        return provider
    }

    private var twoTracks: [MusicCandidate] {
        [
            song("t1", title: "Take On Me", trackNumber: 1),
            song("t2", title: "The Sun Always Shines on T.V.", trackNumber: 2)
        ]
    }

    // MARK: - Transport

    func testTransportCommand() async throws {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        let outcome = try await runner.run(.music(.pause))

        XCTAssertEqual(outcome, .transport(.pause, shuffleBefore: nil))
        XCTAssertEqual(controller.calls, [.pause])
    }

    func testShuffleToggleReadsTheStateBeforeChangingIt() async throws {
        let controller = MockMusicController()
        controller.shuffleEnabledResult = true
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        let outcome = try await runner.run(.music(.shuffle(.toggle)))

        XCTAssertEqual(outcome, .transport(.shuffle(.toggle), shuffleBefore: true))
        XCTAssertEqual(controller.calls, [.shuffleEnabled, .shuffle(nil)])
    }

    // MARK: - Playback

    func testPlaysTheTopSongMatch() async throws {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        let outcome = try await runner.run(.music(.play(query: "take on me")))

        XCTAssertEqual(outcome, .played(twoTracks[0]))
        XCTAssertEqual(controller.calls, [.play("t1")])
    }

    func testBareSongNamePlays() async throws {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        let outcome = try await runner.run(
            try CuebarRequest.run(input: "the sun always shines").action()
        )

        XCTAssertEqual(outcome, .played(twoTracks[1]))
        XCTAssertEqual(controller.calls, [.play("t2")])
    }

    func testAlbumScopeQueuesTheAlbumInRunningOrder() async throws {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        let outcome = try await runner.run(.music(.play(query: "album hunting high and low")))

        guard case .playedAlbum(let album, let trackCount) = outcome else {
            return XCTFail("expected an album, got \(outcome)")
        }
        XCTAssertEqual(album.title, "Hunting High and Low")
        XCTAssertEqual(trackCount, 2)
        XCTAssertEqual(controller.calls, [.playAlbum(["t1", "t2"])])
    }

    func testPlaylistScopePlaysThePlaylist() async throws {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(
                tracks: twoTracks,
                playlists: [playlist("p1", title: "Focus", trackCount: 12)]
            ),
            musicController: controller
        )

        let outcome = try await runner.run(.music(.play(query: "playlist focus")))

        XCTAssertEqual(outcome, .playedPlaylist(playlist("p1", title: "Focus", trackCount: 12), trackCount: 12))
        XCTAssertEqual(controller.calls, [.playPlaylist("p1")])
    }

    // MARK: - Refusals

    func testUnknownSongReportsNoMatch() async {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        await assertThrows(.noMatch("nothing like this"), from: runner, .music(.play(query: "nothing like this")))
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func testArtistRowsAreNotPlayable() async {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        await assertThrows(.artistUnsupported("a-ha"), from: runner, .music(.play(query: "artist a-ha")))
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func testThemeScopeIsPaletteOnly() async {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller
        )

        await assertThrows(.paletteOnly("Theme"), from: runner, .music(.play(query: "theme tahoe")))
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func testEmptyLibraryReportsNoMatch() async {
        let controller = MockMusicController()
        let runner = HeadlessCommandRunner(library: library(tracks: []), musicController: controller)

        await assertThrows(.noMatch("take on me"), from: runner, .music(.play(query: "take on me")))
    }

    // MARK: - Rebuild

    func testRebuildUsesTheInjectedClosure() async throws {
        let controller = MockMusicController()
        let summary = LibraryIndexSummary(trackCount: 12, playlistCount: 3)
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: controller,
            rebuild: { summary }
        )

        let outcome = try await runner.run(.rebuildLibraryIndex)

        XCTAssertEqual(outcome, .rebuiltLibraryIndex(summary))
    }

    func testRebuildFailure() async {
        let runner = HeadlessCommandRunner(
            library: library(tracks: twoTracks),
            musicController: MockMusicController()
        )

        await assertThrows(.rebuildFailed, from: runner, .rebuildLibraryIndex)
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: HeadlessCommandError,
        from runner: HeadlessCommandRunner,
        _ action: HeadlessAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let outcome = try await runner.run(action)
            XCTFail("expected \(expected), got \(outcome)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HeadlessCommandError, expected, file: file, line: line)
        }
    }
}

final class HeadlessFeedbackTests: XCTestCase {
    func testOutcomeToasts() {
        let candidate = MusicCandidate(
            id: "t1",
            kind: .song,
            source: .library,
            title: "Take On Me",
            artist: "a-ha",
            album: "Hunting High and Low",
            persistentID: "t1"
        )

        XCTAssertEqual(
            PlaybackFeedback.toast(for: .played(candidate)).message,
            "Playing “Take On Me”"
        )
        XCTAssertEqual(
            PlaybackFeedback.toast(for: .transport(.next, shuffleBefore: nil)).message,
            "Next track"
        )
        XCTAssertEqual(
            PlaybackFeedback.toast(for: .transport(.shuffle(.toggle), shuffleBefore: false)).message,
            "Shuffle on"
        )
        XCTAssertEqual(
            PlaybackFeedback.toast(for: .rebuiltLibraryIndex(
                LibraryIndexSummary(trackCount: 2, playlistCount: 1)
            )).message,
            "Library indexed"
        )
    }

    func testCommandToastsMatchThePalette() {
        let candidate = MusicCandidate(
            id: "t1",
            kind: .song,
            source: .library,
            title: "Take On Me",
            artist: "a-ha",
            album: "Hunting High and Low",
            persistentID: "t1"
        )

        // `Toast` carries a fresh id each time, so compare its copy.
        assertSameCopy(
            PlaybackFeedback.toast(for: .play(query: "take on me"), shuffleBefore: nil, selected: candidate),
            PlaybackFeedback.playing(candidate)
        )
        assertSameCopy(
            PlaybackFeedback.toast(for: .play(query: ""), shuffleBefore: nil, selected: nil),
            PlaybackFeedback.resumed()
        )
        assertSameCopy(
            PlaybackFeedback.toast(for: .shuffle(.toggle), shuffleBefore: nil, selected: nil),
            PlaybackFeedback.shuffleToggled()
        )
    }

    private func assertSameCopy(
        _ lhs: Toast,
        _ rhs: Toast,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.kind, rhs.kind, file: file, line: line)
        XCTAssertEqual(lhs.message, rhs.message, file: file, line: line)
        XCTAssertEqual(lhs.detail, rhs.detail, file: file, line: line)
        XCTAssertEqual(lhs.duration, rhs.duration, file: file, line: line)
    }

    func testHeadlessErrorToasts() {
        XCTAssertEqual(
            HeadlessCommandError.paletteOnly("Settings").toast.message,
            "“Settings” only works in the Cuebar window"
        )
        XCTAssertEqual(
            HeadlessCommandError.noMatch("nope").toast.message,
            "No match for “nope”"
        )
        XCTAssertEqual(
            HeadlessCommandError.libraryNotReady.toast.kind,
            .error
        )
        // A LocalizedError description comes from the toast copy, so the failure
        // path and the toast can't drift.
        XCTAssertEqual(
            HeadlessCommandError.emptyInput.errorDescription,
            HeadlessCommandError.emptyInput.toast.message
        )
    }
}
