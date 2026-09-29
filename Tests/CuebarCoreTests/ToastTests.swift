import XCTest
@testable import CuebarCore

final class ToastTests: XCTestCase {
    private func song(
        _ title: String,
        artist: String = "a-ha",
        album: String = ""
    ) -> MusicCandidate {
        MusicCandidate(
            id: "1",
            kind: .song,
            source: .library,
            title: title,
            artist: artist,
            album: album,
            persistentID: "1"
        )
    }

    func testKindDurations() {
        XCTAssertEqual(Toast.Kind.success.defaultDuration, 2.0)
        XCTAssertEqual(Toast.Kind.info.defaultDuration, 2.0)
        XCTAssertEqual(Toast.Kind.error.defaultDuration, 4.0)
    }

    func testPlayingCopy() {
        let toast = PlaybackFeedback.playing(song("Take On Me"))
        XCTAssertEqual(toast.kind, .success)
        XCTAssertEqual(toast.message, "Playing “Take On Me”")
        XCTAssertEqual(toast.detail, "a-ha")
    }

    func testPlayingFallsBackToAlbumWhenNoArtist() {
        let toast = PlaybackFeedback.playing(song("Untitled", artist: "", album: "Record"))
        XCTAssertEqual(toast.detail, "Record")
    }

    func testPlayingAlbumCopy() {
        let album = MusicCandidate(
            id: "a",
            kind: .album,
            source: .library,
            title: "After Hours",
            artist: "The Weeknd",
            album: "After Hours"
        )
        let toast = PlaybackFeedback.playingAlbum(album, trackCount: 14)
        XCTAssertEqual(toast.message, "Playing album “After Hours”")
        XCTAssertEqual(toast.detail, "The Weeknd · 14 tracks")
    }

    func testPlayingPlaylistCopy() {
        let playlist = MusicCandidate(
            id: "p",
            kind: .playlist,
            source: .library,
            title: "Focus",
            artist: "",
            album: "",
            persistentID: "p",
            trackCount: 5
        )
        let toast = PlaybackFeedback.playingPlaylist(playlist, trackCount: 5)
        XCTAssertEqual(toast.kind, .success)
        XCTAssertEqual(toast.message, "Playing playlist “Focus”")
        XCTAssertEqual(toast.detail, "5 tracks")
    }

    func testLibraryIndexCopy() {
        XCTAssertEqual(PlaybackFeedback.rebuildingIndex().kind, .info)

        let rebuilt = PlaybackFeedback.indexRebuilt(
            LibraryIndexSummary(trackCount: 6355, playlistCount: 1)
        )
        XCTAssertEqual(rebuilt.kind, .success)
        XCTAssertEqual(rebuilt.message, "Library indexed")
        XCTAssertEqual(rebuilt.detail, "6355 tracks · 1 playlist")

        XCTAssertEqual(PlaybackFeedback.indexRebuildFailed().kind, .error)
    }

    func testTransportCopy() {
        XCTAssertEqual(PlaybackFeedback.paused().message, "Paused")
        XCTAssertEqual(PlaybackFeedback.resumed().message, "Resumed")
        XCTAssertEqual(PlaybackFeedback.nextTrack().message, "Next track")
        XCTAssertEqual(PlaybackFeedback.previousTrack().message, "Previous track")
        XCTAssertEqual(PlaybackFeedback.shuffle(true).message, "Shuffle on")
        XCTAssertEqual(PlaybackFeedback.shuffle(false).message, "Shuffle off")
        XCTAssertEqual(PlaybackFeedback.shuffleToggled().message, "Shuffle toggled")
    }

    func testRepeatCopy() {
        XCTAssertEqual(PlaybackFeedback.repeatMode(.off).message, "Repeat off")
        XCTAssertEqual(PlaybackFeedback.repeatMode(.all).message, "Repeat queue")
        XCTAssertEqual(PlaybackFeedback.repeatMode(.one).message, "Repeat track")
    }

    func testNotInLibraryCopy() {
        let toast = PlaybackFeedback.notInLibrary("Yesterday")
        XCTAssertEqual(toast.kind, .error)
        XCTAssertTrue(toast.message.contains("Yesterday"))
        XCTAssertNotNil(toast.detail)
    }

    func testEmptyAlbumCopy() {
        let toast = PlaybackFeedback.emptyAlbum("Record")
        XCTAssertEqual(toast.kind, .error)
        XCTAssertTrue(toast.message.contains("Record"))
    }

    func testFailureUsesLocalizedDescription() {
        let toast = PlaybackFeedback.failure(PlaybackError.notInLibrary("X"))
        XCTAssertEqual(toast.kind, .error)
        XCTAssertEqual(toast.message, PlaybackError.notInLibrary("X").errorDescription)
    }

    func testPermissionFailureLingersLonger() {
        let toast = PlaybackFeedback.failure(AppleScriptError(code: -1743, message: "denied"))
        XCTAssertEqual(toast.kind, .error)
        XCTAssertEqual(toast.duration, 6.0)
    }
}

@MainActor
final class ToastCenterTests: XCTestCase {
    func testShowPublishesCurrent() {
        let center = ToastCenter(dismissDelay: { _ in })
        center.show(Toast(kind: .success, message: "Hi"))
        XCTAssertEqual(center.current?.message, "Hi")
    }

    func testNewerToastReplacesCurrent() {
        let center = ToastCenter(dismissDelay: { _ in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch {}
        })
        center.show(Toast(kind: .success, message: "A"))
        center.show(Toast(kind: .error, message: "B"))
        XCTAssertEqual(center.current?.message, "B")
    }

    func testDismissClearsCurrent() {
        let center = ToastCenter(dismissDelay: { _ in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch {}
        })
        center.show(Toast(kind: .success, message: "A"))
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testAutoDismissClearsAfterDelay() async {
        let center = ToastCenter(dismissDelay: { _ in
            do { try await Task.sleep(nanoseconds: 10_000_000) } catch {}
        })
        center.show(Toast(kind: .success, message: "Bye", duration: 0.01))
        XCTAssertNotNil(center.current)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(center.current)
    }
}
