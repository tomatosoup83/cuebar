import XCTest
@testable import CuebarCore

@MainActor
final class AmbientPaletteCoordinatorTests: XCTestCase {
    // MARK: - Fixtures

    private let track = NowPlayingTrack(
        state: .playing,
        title: "Track",
        artist: "Artist",
        album: "NowAlbum",
        persistentID: "NP"
    )

    /// A palette whose `accent.red` identifies which artwork it came from.
    private func palette(_ marker: Double, usable: Bool = true) -> AlbumPalette {
        AlbumPalette(
            top: ThemeColor(red: marker, green: 0.6, blue: 0.6),
            bottom: ThemeColor(red: marker, green: 0.6, blue: 0.6),
            accent: ThemeColor(red: marker, green: 0.5, blue: 0.5),
            selection: ThemeColor(red: marker, green: 0.3, blue: 0.4),
            isUsable: usable
        )
    }

    /// Album artwork keys are artist+album based, so `.nowPlaying` and `.library`
    /// for the same album share a key.
    private func cacheKey(album: String) -> String {
        ArtworkSource.library(persistentID: "x", artist: "Artist", album: album).cacheKey
    }

    private func song(album: String) -> PaletteItem {
        .music(
            MusicCandidate(
                id: "song:\(album)",
                kind: .song,
                source: .library,
                title: "Song",
                artist: "Artist",
                album: album,
                persistentID: "ID-\(album)"
            )
        )
    }

    private func command() -> PaletteItem {
        .command(
            CommandEntry(
                id: "settings",
                title: "Settings",
                subtitle: "",
                symbolName: "gearshape",
                action: .openSettings,
                keywords: ["settings"]
            )
        )
    }

    /// Records what the coordinator asked to resolve and what it slept.
    private final class Recorder {
        var sources: [ArtworkSource] = []
        var styles: [PaletteStyle] = []
        var sleeps: [Duration] = []
    }

    private func makeCoordinator(
        followsSelection: Bool,
        palettes: [String: AlbumPalette] = [:],
        recorder: Recorder
    ) -> AmbientPaletteCoordinator {
        AmbientPaletteCoordinator(
            followsSelection: followsSelection,
            delay: .milliseconds(350),
            resolve: { source, style in
                recorder.sources.append(source)
                recorder.styles.append(style)
                return palettes[source.cacheKey]
            },
            sleep: { duration in
                recorder.sleeps.append(duration)
            }
        )
    }

    // MARK: - Which artwork drives the colour

    func testOffFollowsTheTrack() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1), cacheKey(album: "RowAlbum"): palette(0.2)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)

        // Moving the selection must not move the ambient colour.
        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)
    }

    func testOnFollowsTheSelection() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1), cacheKey(album: "RowAlbum"): palette(0.2)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        // No row highlighted yet, so the track still drives it.
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)

        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.2, accuracy: 0.001)
    }

    /// A music row whose artwork yields nothing goes **neutral** — it must not
    /// revert to the playing track's colour. A command row, which has no artwork
    /// at all, does keep the track's colour so the panel never blanks while
    /// arrowing through the default screen.
    func testMusicRowsWithNoColourGoNeutralButCommandsKeepTheTrack() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)

        // No palette for that album → neutral, *not* the track's colour.
        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        XCTAssertNil(coordinator.palette)

        // A command row has no artwork to follow, so the track still drives it.
        coordinator.update(selection: command())
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)
    }

    /// A colourless cover is used *as is* — it must never be replaced by the
    /// playing track's colour.
    func testColourlessCoverIsUsedRatherThanRevertingToTheTrack() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [
                cacheKey(album: "NowAlbum"): palette(0.1),
                cacheKey(album: "RowAlbum"): palette(0.2, usable: false)
            ],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)

        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        // The row's own (grey) palette, not the track's.
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.2, accuracy: 0.001)
    }

    func testNothingPlayingAndNoArtworkGoesNeutral() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(followsSelection: true, recorder: recorder)

        coordinator.setEnabled(true)
        coordinator.update(selection: command())
        await coordinator.settle()
        XCTAssertNil(coordinator.palette)
    }

    // MARK: - Timing

    func testFirstColourIsNotDelayedButAChangeIs() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1), cacheKey(album: "RowAlbum"): palette(0.2)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertTrue(recorder.sleeps.isEmpty, "the first colour should appear immediately")

        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        XCTAssertEqual(recorder.sleeps, [.milliseconds(350)], "a change should pause first")
    }

    /// The pause is *leading*: it starts when a burst begins and is not restarted
    /// by every change, so a long burst pauses once, not once per row.
    func testABurstPausesOnceNotPerRow() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [
                cacheKey(album: "NowAlbum"): palette(0.1),
                cacheKey(album: "AlbumA"): palette(0.3),
                cacheKey(album: "AlbumB"): palette(0.4)
            ],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        recorder.sleeps.removeAll()

        coordinator.update(selection: song(album: "AlbumA"))
        coordinator.update(selection: song(album: "AlbumB"))
        await coordinator.settle()

        XCTAssertEqual(recorder.sleeps, [.milliseconds(350)])
    }

    func testRapidChangesResolveOnlyTheSettledRow() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: true,
            palettes: [
                cacheKey(album: "NowAlbum"): palette(0.1),
                cacheKey(album: "AlbumA"): palette(0.3),
                cacheKey(album: "AlbumB"): palette(0.4),
                cacheKey(album: "AlbumC"): palette(0.5)
            ],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        recorder.sources.removeAll()

        // Three selections in the same run-loop turn, as when holding an arrow key.
        coordinator.update(selection: song(album: "AlbumA"))
        coordinator.update(selection: song(album: "AlbumB"))
        coordinator.update(selection: song(album: "AlbumC"))
        await coordinator.settle()

        // Only the row the user actually settled on was ever resolved.
        XCTAssertEqual(recorder.sources.map(\.cacheKey), [cacheKey(album: "AlbumC")])
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.5, accuracy: 0.001)
    }

    // MARK: - Theme and option switches

    func testDisablingClearsThePalette() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertNotNil(coordinator.palette)

        coordinator.setEnabled(false)
        await coordinator.settle()
        XCTAssertNil(coordinator.palette)
    }

    func testTogglingFollowsSelectionTakesEffectImmediately() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1), cacheKey(album: "RowAlbum"): palette(0.2)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        coordinator.update(selection: song(album: "RowAlbum"))
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)

        coordinator.setFollowsSelection(true)
        await coordinator.settle()
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.2, accuracy: 0.001)
    }

    /// Switching between the two Album Art themes keeps the same artwork but
    /// must extract again with the new style — otherwise the panel would keep
    /// the old palette because the *source* never changed.
    func testSwitchingStyleReResolvesTheSameArtwork() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(recorder.styles, [.classic])

        coordinator.setStyle(.clustered)
        await coordinator.settle()

        XCTAssertEqual(recorder.styles, [.classic, .clustered])
        XCTAssertEqual(
            recorder.sources.map(\.cacheKey),
            [cacheKey(album: "NowAlbum"), cacheKey(album: "NowAlbum")],
            "the artwork must be resolved again with the new style"
        )
        XCTAssertEqual(coordinator.palette?.accent.red ?? -1, 0.1, accuracy: 0.001)
    }

    /// Toggling the global-colours option on Album Art v2 is a style change too,
    /// so it must re-resolve the same artwork without a gradient.
    func testSwitchingClusterLayoutReResolves() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.setStyle(.clustered)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(recorder.styles, [.clustered])

        coordinator.setStyle(.clusteredGlobal)
        await coordinator.settle()
        XCTAssertEqual(recorder.styles, [.clustered, .clusteredGlobal])
    }

    /// Setting the style it is already using is a no-op, so a theme rebuild
    /// can't cause a redundant resolve.
    func testSettingTheSameStyleDoesNothing() async {
        let recorder = Recorder()
        let coordinator = makeCoordinator(
            followsSelection: false,
            palettes: [cacheKey(album: "NowAlbum"): palette(0.1)],
            recorder: recorder
        )

        coordinator.setEnabled(true)
        coordinator.setStyle(.classic)
        coordinator.update(nowPlaying: track)
        await coordinator.settle()
        XCTAssertEqual(recorder.sources.count, 1)

        coordinator.setStyle(.classic)
        await coordinator.settle()
        XCTAssertEqual(recorder.sources.count, 1)
    }
}
