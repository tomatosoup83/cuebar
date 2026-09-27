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
    private var currentQuery = ""

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

    public func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentQuery else { return }
        currentQuery = trimmed

        searchTask?.cancel()
        guard !trimmed.isEmpty else {
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
                let local = try await self.libraryProvider.search(trimmed, limit: self.resultLimit * 2)
                if Task.isCancelled { return }
                merged = Ranking.rank(local, query: trimmed, limit: self.resultLimit)
                libraryIsStrong = Ranking.hasStrongMatch(
                    local,
                    query: trimmed,
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
                let catalog = try await self.catalogProvider.search(trimmed, limit: 15)
                if Task.isCancelled { return }
                let combined = Ranking.rank(merged + catalog, query: trimmed, limit: self.resultLimit)
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
        currentQuery = ""
        results = []
        isSearching = false
        statusMessage = nil
    }
}
