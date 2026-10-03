import XCTest
@testable import CuebarCore

final class QuickActionsTests: XCTestCase {
    private func song(_ id: String = "song", source: MusicSource = .library) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: source,
            title: "Take On Me",
            artist: "a-ha",
            album: "Hunting High and Low",
            persistentID: source == .library ? id : nil
        )
    }

    private func album() -> MusicCandidate {
        MusicCandidate(
            id: "album",
            kind: .album,
            source: .library,
            title: "Hunting High and Low",
            artist: "a-ha",
            album: "Hunting High and Low",
            persistentID: "album"
        )
    }

    private func playlist() -> MusicCandidate {
        MusicCandidate(
            id: "playlist",
            kind: .playlist,
            source: .library,
            title: "80s",
            artist: "",
            album: "",
            persistentID: "playlist"
        )
    }

    private func titles(_ items: [QuickActionItem]) -> [String] {
        items.map(\.title)
    }

    func testSongActions() {
        let items = QuickActions.items(for: .music(song()), loved: false, canLike: true)
        XCTAssertEqual(titles(items), ["Play", "Like", "Add to Playlist…", "Open in Music", "Dismiss"])
        XCTAssertEqual(items.first?.shortcut, "↩")
        XCTAssertTrue(items.last?.isDestructive == true)
    }

    func testLovedSongShowsRemove() {
        let items = QuickActions.items(for: .music(song()), loved: true, canLike: true)
        XCTAssertEqual(items.first(where: { $0.action == .unlike })?.title, "Remove from Loved")
        XCTAssertNil(items.first(where: { $0.action == .like }))
    }

    func testCatalogOnlySongHasNoLikeOrPlaylist() {
        let items = QuickActions.items(for: .music(song(source: .catalog)), loved: nil, canLike: false)
        XCTAssertEqual(titles(items), ["Play", "Open in Music", "Dismiss"])
    }

    func testAlbumActions() {
        let items = QuickActions.items(for: .music(album()))
        XCTAssertEqual(titles(items), ["Play Album", "Open in Music", "Dismiss"])
        XCTAssertNil(items.first(where: { $0.action == .like }))
    }

    func testPlaylistActions() {
        let items = QuickActions.items(for: .music(playlist()))
        XCTAssertEqual(titles(items), ["Play Playlist", "Open in Music", "Dismiss"])
    }

    func testCommandActions() {
        let entry = CommandCatalog.all.first { $0.id == "next" }!
        let items = QuickActions.items(for: .command(entry))
        XCTAssertEqual(titles(items), ["Run “Next Track”", "Dismiss"])
        XCTAssertNil(items.first(where: { $0.action == .openInMusic }))
    }

    func testNowPlayingPrimaryReflectsState() {
        let playing = NowPlayingTrack(state: .playing, title: "Take On Me", artist: "a-ha", album: "HHAL")
        let paused = NowPlayingTrack(state: .paused, title: "Take On Me", artist: "a-ha", album: "HHAL")
        XCTAssertEqual(QuickActions.items(for: .nowPlaying(playing)).first?.title, "Pause")
        XCTAssertEqual(QuickActions.items(for: .nowPlaying(paused)).first?.title, "Play")
    }

    func testPlaylistItemsSkipMissingIDs() {
        let withID = MusicCandidate(
            id: "p1", kind: .playlist, source: .library,
            title: "Road Trip", artist: "", album: "", persistentID: "PID"
        )
        let withoutID = MusicCandidate(
            id: "p2", kind: .playlist, source: .library,
            title: "Broken", artist: "", album: ""
        )
        let items = QuickActions.playlistItems([withID, withoutID])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Road Trip")
        XCTAssertEqual(items[0].action, .addToPlaylist(playlistID: "PID", name: "Road Trip"))
    }

    func testFilterMatchesTitleAndKeywords() {
        let items = QuickActions.items(for: .music(song()), loved: false, canLike: true)
        XCTAssertEqual(QuickActions.filter(items, query: "").count, items.count)
        XCTAssertEqual(QuickActions.filter(items, query: "music").map(\.title), ["Open in Music"])
        XCTAssertEqual(QuickActions.filter(items, query: "favourite").map(\.title), ["Like"])
        XCTAssertTrue(QuickActions.filter(items, query: "zzz").isEmpty)
    }
}
