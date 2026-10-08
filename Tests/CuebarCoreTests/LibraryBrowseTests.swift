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

    private func artist(_ id: String) -> MusicCandidate {
        MusicCandidate(id: id, kind: .artist, source: .library, title: id, artist: id, album: "")
    }

    private func song(_ id: String) -> MusicCandidate {
        MusicCandidate(
            id: id, kind: .song, source: .library,
            title: id, artist: "Band", album: "Record", persistentID: id
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

    func testArtistsPreferenceReturnsArtistsOnly() {
        var generator = SeededGenerator(seed: 6)
        let items = LibraryBrowse.items(
            albums: [album("a")],
            playlists: [playlist("p")],
            artists: [artist("x"), artist("y")],
            preference: .artists,
            limit: 40,
            using: &generator
        )
        XCTAssertEqual(Set(items.map(\.id)), ["x", "y"])
    }

    func testShuffledCapsAndKeepsEveryElement() {
        var generator = SeededGenerator(seed: 7)
        let pool = (0..<10).map { song("s\($0)") }
        let sample = LibraryBrowse.shuffled(pool, limit: 4, using: &generator)
        XCTAssertEqual(sample.count, 4)
        XCTAssertTrue(sample.allSatisfy { pool.contains($0) })
    }

    func testShuffledZeroLimitIsEmpty() {
        var generator = SeededGenerator(seed: 8)
        XCTAssertTrue(LibraryBrowse.shuffled([song("s0")], limit: 0, using: &generator).isEmpty)
    }
}
