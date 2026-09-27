import XCTest
import AppKit
@testable import CuebarCore

private final class MockArtworkProvider: ArtworkDataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var data: Data?

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func artworkData(for persistentID: String?) async throws -> Data? {
        lock.lock(); count += 1; lock.unlock()
        return data
    }
}

final class ArtworkStoreTests: XCTestCase {
    // MARK: - Cache keys

    func testAlbumKeySharedAcrossTracksOfSameAlbum() {
        let first = ArtworkSource.library(persistentID: "1", artist: "a-ha", album: "Hunting High and Low")
        let second = ArtworkSource.library(persistentID: "2", artist: "A-HA", album: " hunting high and low ")
        XCTAssertEqual(first.cacheKey, second.cacheKey)
    }

    func testDifferentAlbumsHaveDifferentKeys() {
        let first = ArtworkSource.library(persistentID: "1", artist: "a-ha", album: "Album A")
        let second = ArtworkSource.library(persistentID: "1", artist: "a-ha", album: "Album B")
        XCTAssertNotEqual(first.cacheKey, second.cacheKey)
    }

    func testLibraryWithoutAlbumFallsBackToTrack() {
        let source = ArtworkSource.library(persistentID: "PID9", artist: "x", album: "")
        XCTAssertEqual(source.cacheKey, "track:PID9")
    }

    func testNowPlayingSharesAlbumKey() {
        let library = ArtworkSource.library(persistentID: "1", artist: "a-ha", album: "Album")
        let nowPlaying = ArtworkSource.nowPlaying(persistentID: "1", artist: "a-ha", album: "Album", title: "Song")
        XCTAssertEqual(library.cacheKey, nowPlaying.cacheKey)
    }

    func testRemoteKeyUsesURL() {
        let url = URL(string: "https://example.com/a.jpg")!
        XCTAssertEqual(ArtworkSource.remote(url).cacheKey, "remote:https://example.com/a.jpg")
    }

    // MARK: - Cache behaviour

    func testFetchesAndCachesOnce() async {
        let directory = makeTemporaryDirectory()
        let provider = MockArtworkProvider()
        provider.data = makeImageData(pixels: 800)
        let store = ArtworkStore(provider: provider, directory: directory)

        let source = ArtworkSource.library(persistentID: "1", artist: "a", album: "b")

        let first = await store.image(for: source)
        XCTAssertNotNil(first)
        XCTAssertEqual(provider.callCount, 1)

        let second = await store.image(for: source)
        XCTAssertNotNil(second)
        XCTAssertEqual(provider.callCount, 1, "Second lookup should hit the cache")
    }

    func testDownscalesToMaxDimension() async {
        let directory = makeTemporaryDirectory()
        let provider = MockArtworkProvider()
        provider.data = makeImageData(pixels: 800)
        let store = ArtworkStore(provider: provider, directory: directory, maxDimension: 256)

        let image = await store.image(for: ArtworkSource.library(persistentID: "1", artist: "a", album: "b"))

        XCTAssertEqual(image?.size.width, 256)
        XCTAssertEqual(image?.size.height, 256)
    }

    func testPersistsAcrossStoreInstances() async {
        let directory = makeTemporaryDirectory()
        let source = ArtworkSource.library(persistentID: "1", artist: "a", album: "b")

        let provider = MockArtworkProvider()
        provider.data = makeImageData(pixels: 400)
        let first = ArtworkStore(provider: provider, directory: directory)
        _ = await first.image(for: source)

        // A fresh store with a provider that returns nothing must still find the
        // image on disk, and must not consult the provider.
        let emptyProvider = MockArtworkProvider()
        let second = ArtworkStore(provider: emptyProvider, directory: directory)
        XCTAssertNotNil(second.cachedImage(for: source))
        XCTAssertEqual(emptyProvider.callCount, 0)
    }

    func testMissingArtworkReturnsNil() async {
        let directory = makeTemporaryDirectory()
        let store = ArtworkStore(provider: MockArtworkProvider(), directory: directory)
        let image = await store.image(for: ArtworkSource.library(persistentID: "1", artist: "a", album: "b"))
        XCTAssertNil(image)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cuebar-artwork-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeImageData(pixels: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let cgImage = context.makeImage()!
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
    }
}
