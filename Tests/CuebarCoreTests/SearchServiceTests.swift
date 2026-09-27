import XCTest
@testable import CuebarCore

private func makeSong(_ id: String, _ title: String, source: MusicSource) -> MusicCandidate {
    MusicCandidate(
        id: id,
        kind: .song,
        source: source,
        title: title,
        artist: "",
        album: "",
        persistentID: source == .library ? id : nil
    )
}

@MainActor
final class SearchServiceTests: XCTestCase {
    func testStrongLibraryMatchSkipsCatalog() async {
        let library = MockSearchProvider { _, _ in [makeSong("lib", "Take On Me", source: .library)] }
        let catalog = MockSearchProvider { _, _ in [makeSong("cat", "Take On Me", source: .catalog)] }

        let service = SearchService(
            libraryProvider: library,
            catalogProvider: catalog,
            resultLimit: 20,
            catalogDebounceNanoseconds: 0
        )

        service.updateQuery("take on me")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(service.results.map(\.id), ["lib"])
        XCTAssertTrue(catalog.queries.isEmpty, "Catalog should not be queried when the library already matches")
    }

    func testWeakLibraryMatchFallsBackToCatalog() async {
        // "take on me" is only a weak (fuzzy) match against "Take Me Home",
        // so the catalog should be consulted and its exact match should win.
        let library = MockSearchProvider { _, _ in [makeSong("lib", "Take Me Home", source: .library)] }
        let catalog = MockSearchProvider { _, _ in [makeSong("cat", "Take On Me", source: .catalog)] }

        let service = SearchService(
            libraryProvider: library,
            catalogProvider: catalog,
            resultLimit: 20,
            catalogDebounceNanoseconds: 0
        )

        service.updateQuery("take on me")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(service.results.map(\.id), ["cat", "lib"])
        XCTAssertFalse(catalog.queries.isEmpty)
    }

    func testStaleQueryResultsAreDiscarded() async {
        let library = MockSearchProvider { query, _ in
            if query == "alpha" {
                try await Task.sleep(nanoseconds: 80_000_000)
                return [makeSong("alpha", "Alpha", source: .library)]
            }
            return [makeSong("beta", "Beta", source: .library)]
        }
        let catalog = MockSearchProvider { _, _ in [] }

        let service = SearchService(
            libraryProvider: library,
            catalogProvider: catalog,
            resultLimit: 20,
            catalogDebounceNanoseconds: 0
        )

        service.updateQuery("alpha")
        try? await Task.sleep(nanoseconds: 10_000_000)
        service.updateQuery("beta")

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(service.results.map(\.id), ["beta"])
    }

    func testClearResetsResults() async {
        let library = MockSearchProvider { _, _ in [makeSong("lib", "Hello", source: .library)] }
        let service = SearchService(
            libraryProvider: library,
            catalogProvider: MockSearchProvider { _, _ in [] },
            resultLimit: 20,
            catalogDebounceNanoseconds: 0
        )

        service.updateQuery("hello")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(service.results.isEmpty)

        service.clear()
        XCTAssertTrue(service.results.isEmpty)
    }
}
