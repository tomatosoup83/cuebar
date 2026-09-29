import XCTest
@testable import CuebarCore

/// Deterministic generator (SplitMix-ish) so shuffle order is reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class LibraryBrowseTests: XCTestCase {
    private func album(_ id: String) -> MusicCandidate {
        MusicCandidate(id: id, kind: .album, source: .library, title: id, artist: "", album: id)
    }

    private func playlist(_ id: String) -> MusicCandidate {
        MusicCandidate(
            id: id, kind: .playlist, source: .library,
            title: id, artist: "", album: "", persistentID: id
        )
    }

    func testAlbumsPreferenceReturnsAlbumsOnly() {
        var generator = SeededGenerator(seed: 1)
        let items = LibraryBrowse.items(
            albums: [album("a"), album("b")],
            playlists: [playlist("p")],
            preference: .albums,
            limit: 40,
            using: &generator
        )
        XCTAssertEqual(Set(items.map(\.id)), ["a", "b"])
    }

    func testPlaylistsPreferenceReturnsPlaylistsOnly() {
        var generator = SeededGenerator(seed: 1)
        let items = LibraryBrowse.items(
            albums: [album("a")],
            playlists: [playlist("p"), playlist("q")],
            preference: .playlists,
            limit: 40,
            using: &generator
        )
        XCTAssertEqual(Set(items.map(\.id)), ["p", "q"])
    }

    func testLimitCapsResults() {
        var generator = SeededGenerator(seed: 2)
        let albums = (0..<10).map { album("a\($0)") }
        let items = LibraryBrowse.items(
            albums: albums, playlists: [], preference: .albums, limit: 3, using: &generator
        )
        XCTAssertEqual(items.count, 3)
    }

    func testSeededGeneratorIsDeterministic() {
        let albums = (0..<10).map { album("a\($0)") }
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        let a = LibraryBrowse.items(albums: albums, playlists: [], preference: .albums, limit: 10, using: &first).map(\.id)
        let b = LibraryBrowse.items(albums: albums, playlists: [], preference: .albums, limit: 10, using: &second).map(\.id)
        XCTAssertEqual(a, b)
    }

    func testEmptyPool() {
        var generator = SeededGenerator(seed: 3)
        XCTAssertTrue(
            LibraryBrowse.items(albums: [], playlists: [], preference: .albums, limit: 40, using: &generator).isEmpty
        )
    }

    func testSongsPreferenceIsEmpty() {
        var generator = SeededGenerator(seed: 4)
        XCTAssertTrue(
            LibraryBrowse.items(albums: [album("a")], playlists: [], preference: .songs, limit: 40, using: &generator).isEmpty
        )
    }

    func testZeroLimit() {
        var generator = SeededGenerator(seed: 5)
        XCTAssertTrue(
            LibraryBrowse.items(albums: [album("a")], playlists: [], preference: .albums, limit: 0, using: &generator).isEmpty
        )
    }
}
