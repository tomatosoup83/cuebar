import Foundation
import Combine

/// Orchestrates library + catalog search and exposes the merged, ranked results.
///
/// Library results are published first (they are local and fast); catalog
/// results are merged in once the (debounced) network request returns.
@MainActor
public final class SearchService: ObservableObject {
    @Published public private(set) var results: [MusicCandidate] = []
    @Published public private(set) var isSearching = false
    @Published public var isIndexing = false
    @Published public private(set) var statusMessage: String?

    private let libraryProvider: MusicSearchProviding
    private let catalogProvider: MusicSearchProviding
    private let resultLimit: Int
    private let catalogDebounce: UInt64

    private var searchTask: Task<Void, Never>?
    private var currentQuery: SearchQuery?

    public init(
        libraryProvider: MusicSearchProviding,
        catalogProvider: MusicSearchProviding,
        resultLimit: Int = 40,
        catalogDebounceNanoseconds: UInt64 = 150_000_000
    ) {
        self.libraryProvider = libraryProvider
        self.catalogProvider = catalogProvider
        self.resultLimit = resultLimit
        self.catalogDebounce = catalogDebounceNanoseconds
    }

    /// Parses `query` (including any `album`/`playlist` keyword) and searches.
    public func updateQuery(_ query: String) {
        updateQuery(SearchQuery.parse(query))
    }

    public func updateQuery(_ parsed: SearchQuery) {
        guard parsed != currentQuery else { return }
        currentQuery = parsed

        let term = parsed.term
        let preference = parsed.preference

        searchTask?.cancel()
        guard !term.isEmpty else {
            results = []
            isSearching = false
            statusMessage = nil
            return
        }

        isSearching = true
        statusMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }

            // 1. Library: local, show immediately.
            var merged: [MusicCandidate] = []
            var libraryIsStrong = false
            do {
                let local = try await self.libraryProvider.search(term, limit: self.resultLimit * 2)
                if Task.isCancelled { return }
                merged = Ranking.rank(
                    local,
                    query: term,
                    preference: preference,
                    limit: self.resultLimit
                )
                // The catalog is skipped only when the library has a strong
                // *song* match; album/playlist rows never suppress it.
                libraryIsStrong = Ranking.hasStrongMatch(
                    local.filter { $0.kind == .song },
                    query: term,
                    threshold: Ranking.strongMatchThreshold
                )
                self.results = merged
            } catch {
                if Task.isCancelled { return }
            }

            // 2. Catalog is only a fallback: skip it when the library already
            //    has a strong (non-fuzzy) match.
            guard !libraryIsStrong else {
                self.isSearching = false
                return
            }

            if self.catalogDebounce > 0 {
                try? await Task.sleep(nanoseconds: self.catalogDebounce)
            }
            if Task.isCancelled { return }

            do {
                let catalog = try await self.catalogProvider.search(term, limit: 15)
                if Task.isCancelled { return }
                let combined = Ranking.rank(
                    merged + catalog,
                    query: term,
                    preference: preference,
                    limit: self.resultLimit
                )
                self.results = combined
            } catch {
                if Task.isCancelled { return }
                if merged.isEmpty {
                    self.statusMessage = "No matches in your library and couldn’t reach the Apple Music catalog."
                }
            }

            self.isSearching = false
        }
    }

    public func clear() {
        searchTask?.cancel()
        searchTask = nil
        currentQuery = nil
        results = []
        isSearching = false
        statusMessage = nil
    }
}
