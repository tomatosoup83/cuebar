import XCTest
@testable import CuebarCore

final class RecentlyPlayedTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func song(_ id: String, title: String? = nil) -> MusicCandidate {
        MusicCandidate(
            id: id,
            kind: .song,
            source: .library,
            title: title ?? "Song \(id)",
            artist: "Artist",
            album: "Album",
            persistentID: id
        )
    }

    private func raw(_ records: [(String, String)]) -> String {
        records
            .map { $0.0 + AppleScriptLibraryProvider.fieldSeparator + $0.1 }
            .joined(separator: AppleScriptLibraryProvider.listSeparator)
    }

    // MARK: - Parsing

    func testParsesRecords() {
        let entries = RecentlyPlayed.parse(raw([("A", "120"), ("B", "5")]))
        XCTAssertEqual(entries, [
            PlayedEntry(persistentID: "A", secondsAgo: 120),
            PlayedEntry(persistentID: "B", secondsAgo: 5)
        ])
    }

    func testParseSkipsMalformedRecords() {
        let text = raw([("A", "10"), ("", "4"), ("C", "soon"), ("D", "-3")]) + "\u{1e}junk"
        XCTAssertEqual(RecentlyPlayed.parse(text).map(\.persistentID), ["A"])
    }

    func testParseEmptyOutput() {
        XCTAssertTrue(RecentlyPlayed.parse("").isEmpty)
    }

    // MARK: - Shelf

    func testNewestFirstAndLimited() {
        let library = (1...5).map { song("\($0)") }
        let entries = [
            PlayedEntry(persistentID: "1", secondsAgo: 500),
            PlayedEntry(persistentID: "2", secondsAgo: 10),
            PlayedEntry(persistentID: "3", secondsAgo: 90),
            PlayedEntry(persistentID: "4", secondsAgo: 3000)
        ]
        let shelf = RecentlyPlayed.tracks(from: entries, library: library, limit: 3, now: now)
        XCTAssertEqual(shelf.map(\.id), ["2", "3", "1"])
        XCTAssertEqual(shelf.first?.playedAt, now.addingTimeInterval(-10))
    }

    func testExcludesNowPlayingTrack() {
        let library = [song("A"), song("B")]
        let entries = [
            PlayedEntry(persistentID: "A", secondsAgo: 1),
            PlayedEntry(persistentID: "B", secondsAgo: 2)
        ]
        let shelf = RecentlyPlayed.tracks(from: entries, library: library, excluding: "A", now: now)
        XCTAssertEqual(shelf.map(\.id), ["B"])
    }

    func testDropsTracksMissingFromTheIndexAndDuplicates() {
        let library = [song("A")]
        let entries = [
            PlayedEntry(persistentID: "GONE", secondsAgo: 1),
            PlayedEntry(persistentID: "A", secondsAgo: 2),
            PlayedEntry(persistentID: "A", secondsAgo: 3)
        ]
        let shelf = RecentlyPlayed.tracks(from: entries, library: library, now: now)
        XCTAssertEqual(shelf.map(\.id), ["A"])
    }

    func testIgnoresNonSongsInTheLibrary() {
        let album = MusicCandidate(
            id: "ALB", kind: .album, source: .library,
            title: "Album", artist: "Artist", album: "Album", persistentID: "ALB"
        )
        let shelf = RecentlyPlayed.tracks(
            from: [PlayedEntry(persistentID: "ALB", secondsAgo: 1)],
            library: [album],
            now: now
        )
        XCTAssertTrue(shelf.isEmpty)
    }

    func testTiesBreakDeterministically() {
        let library = [song("B"), song("A")]
        let entries = [
            PlayedEntry(persistentID: "B", secondsAgo: 7),
            PlayedEntry(persistentID: "A", secondsAgo: 7)
        ]
        let shelf = RecentlyPlayed.tracks(from: entries, library: library, now: now)
        XCTAssertEqual(shelf.map(\.id), ["A", "B"])
    }

    // MARK: - Relative labels

    func testRelativeLabels() {
        func label(_ secondsAgo: Double) -> String {
            RecentlyPlayed.relativeLabel(for: now.addingTimeInterval(-secondsAgo), now: now)
        }
        XCTAssertEqual(label(5), "Just now")
        XCTAssertEqual(label(-30), "Just now")
        XCTAssertEqual(label(5 * 60), "5m ago")
        XCTAssertEqual(label(3 * 3600 + 100), "3h ago")
        XCTAssertEqual(label(30 * 3600), "Yesterday")
        XCTAssertEqual(label(4 * 86_400), "4d ago")
        XCTAssertEqual(label(15 * 86_400), "2w ago")
        XCTAssertEqual(label(95 * 86_400), "3mo ago")
        XCTAssertEqual(label(800 * 86_400), "2y ago")
    }

    // MARK: - Home composition

    private let track = NowPlayingTrack(
        state: .playing, title: "Now", artist: "Artist", album: "Album", persistentID: "NOW"
    )

    func testHomeShowsNowPlayingThenRecentShelf() {
        let recent = [RecentTrack(candidate: song("A"), playedAt: now)]
        let items = PaletteListComposer.compose(
            query: "",
            nowPlaying: track,
            commands: [],
            music: [],
            recent: recent
        )
        XCTAssertEqual(items.map(\.id), ["nowPlaying", "recent:A"])
    }

    func testRecentShelfHiddenWhileSearching() {
        let recent = [RecentTrack(candidate: song("A"), playedAt: now)]
        let items = PaletteListComposer.compose(
            query: "take",
            nowPlaying: track,
            commands: [],
            music: [song("S")],
            recent: recent
        )
        XCTAssertEqual(items.map(\.id), ["music:S"])
    }

    func testRecentRowUsesItsTrackArtwork() {
        let item = PaletteItem.recent(RecentTrack(candidate: song("A"), playedAt: now))
        XCTAssertEqual(item.artworkSource, PaletteItem.music(song("A")).artworkSource)
        XCTAssertNotNil(item.artworkSource)
    }

    func testHomeCommandsGiveWayToTheShelf() {
        let all = CommandCatalog.matches(for: "")
        let update = CommandEntry(
            id: "installUpdate", title: "Install Update", subtitle: "",
            symbolName: "arrow.down.circle", action: .installUpdate, keywords: []
        )

        XCTAssertEqual(PaletteListComposer.homeCommands(all, hasRecent: false), all)
        XCTAssertTrue(PaletteListComposer.homeCommands(all, hasRecent: true).isEmpty)
        XCTAssertEqual(
            PaletteListComposer.homeCommands([update] + all, hasRecent: true).map(\.id),
            ["installUpdate"]
        )
    }
}
