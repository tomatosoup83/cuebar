import Foundation

/// Deterministic scoring and ordering for search results.
///
/// Design rules (see plan.md):
/// - exact title match is the strongest signal
/// - an exact **song** title outranks an exact **album** title
/// - library results are preferred over catalog results
/// - fuzzy matching tolerates minor typos
/// - ordering is stable for identical inputs
public enum Ranking {
    // Base match scores.
    private static let exactScore: Double = 1000
    private static let prefixScore: Double = 850
    private static let tokenInOrderScore: Double = 700
    private static let containsScore: Double = 600
    private static let fuzzyScale: Double = 500
    private static let fuzzyThreshold: Double = 0.60
    /// Base scores when the title doesn't match but the artist/album does.
    private static let artistMatchScore: Double = 500
    private static let albumMatchScore: Double = 400

    /// A base match at or above this is treated as "the library already has it".
    public static let strongMatchThreshold: Double = 550

    // Bonuses applied on top of a base match.
    private static let libraryBonus: Double = 100
    private static let artistBonus: Double = 150
    private static let albumBonus: Double = 30

    /// Bonus/penalty that guarantees song > album > artist for equal base matches.
    private static func kindBonus(_ kind: MusicKind) -> Double {
        switch kind {
        case .song: return 200
        case .album: return 0
        case .artist: return -100
        }
    }

    public static func kindRank(_ kind: MusicKind) -> Int {
        switch kind {
        case .song: return 0
        case .album: return 1
        case .artist: return 2
        }
    }

    public static func sourceRank(_ source: MusicSource) -> Int {
        source == .library ? 0 : 1
    }

    /// Ranks `candidates` against `query`, returning the best `limit` results.
    public static func rank(
        _ candidates: [MusicCandidate],
        query: String,
        limit: Int = 40
    ) -> [MusicCandidate] {
        let normalizedQuery = TextNormalizer.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return Array(candidates.prefix(limit))
        }
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)

        var scored: [(candidate: MusicCandidate, score: Double)] = []
        scored.reserveCapacity(candidates.count)

        for candidate in candidates {
            let score = score(candidate, normalizedQuery: normalizedQuery, queryTokens: queryTokens)
            if score > 0 {
                scored.append((candidate, score))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }

            let lhsKind = kindRank(lhs.candidate.kind)
            let rhsKind = kindRank(rhs.candidate.kind)
            if lhsKind != rhsKind { return lhsKind < rhsKind }

            let lhsSource = sourceRank(lhs.candidate.source)
            let rhsSource = sourceRank(rhs.candidate.source)
            if lhsSource != rhsSource { return lhsSource < rhsSource }

            if lhs.candidate.normalizedTitle != rhs.candidate.normalizedTitle {
                return lhs.candidate.normalizedTitle < rhs.candidate.normalizedTitle
            }
            return lhs.candidate.id < rhs.candidate.id
        }

        return scored.prefix(limit).map(\.candidate)
    }

    /// Scores a single candidate. Returns 0 when there is no meaningful match.
    public static func score(
        _ candidate: MusicCandidate,
        normalizedQuery query: String,
        queryTokens: [String]
    ) -> Double {
        evaluate(candidate, normalizedQuery: query, queryTokens: queryTokens).total
    }

    /// The match strength before type/source bonuses are applied.
    ///
    /// Used to decide whether the library already has a good enough answer, in
    /// which case the catalog is not queried at all.
    public static func baseScore(_ candidate: MusicCandidate, query: String) -> Double {
        let normalized = TextNormalizer.normalize(query)
        guard !normalized.isEmpty else { return 0 }
        let tokens = normalized.split(separator: " ").map(String.init)
        return evaluate(candidate, normalizedQuery: normalized, queryTokens: tokens).base
    }

    /// True when any candidate is a strong (non-fuzzy) match for `query`.
    public static func hasStrongMatch(
        _ candidates: [MusicCandidate],
        query: String,
        threshold: Double
    ) -> Bool {
        candidates.contains { baseScore($0, query: query) >= threshold }
    }

    private static func evaluate(
        _ candidate: MusicCandidate,
        normalizedQuery query: String,
        queryTokens: [String]
    ) -> (base: Double, total: Double) {
        let title = candidate.normalizedTitle
        var base: Double = 0

        if title == query {
            base = exactScore
        } else if title.hasPrefix(query) {
            base = prefixScore
        } else if tokensMatchInOrder(
            titleTokens: title.split(separator: " ").map(String.init),
            queryTokens: queryTokens
        ) {
            base = tokenInOrderScore
        } else if title.contains(query) {
            base = containsScore
        } else if abs(title.count - query.count) <= 4 {
            // Only pay for fuzzy comparison when lengths are plausible.
            let similarity = Similarity.ratio(query, title)
            if similarity >= fuzzyThreshold {
                base = (similarity * fuzzyScale).rounded()
            }
        }

        // Fall back to artist / album matches so "play a-ha" works too.
        if base == 0 {
            if !candidate.normalizedArtist.isEmpty, candidate.normalizedArtist.contains(query) {
                base = artistMatchScore
            } else if !candidate.normalizedAlbum.isEmpty, candidate.normalizedAlbum.contains(query) {
                base = albumMatchScore
            }
        }

        guard base > 0 else { return (0, 0) }

        var total = base + kindBonus(candidate.kind)
        if candidate.source == .library { total += libraryBonus }

        let artist = candidate.normalizedArtist
        if !artist.isEmpty, queryTokens.contains(where: { $0.count >= 3 && artist.contains($0) }) {
            total += artistBonus
        }
        let album = candidate.normalizedAlbum
        if !album.isEmpty, queryTokens.contains(where: { $0.count >= 3 && album.contains($0) }) {
            total += albumBonus
        }
        return (base, total)
    }

    /// True when every query token prefixes a later title token, in order.
    private static func tokensMatchInOrder(titleTokens: [String], queryTokens: [String]) -> Bool {
        guard !queryTokens.isEmpty, !titleTokens.isEmpty else { return false }
        var titleIndex = 0
        for queryToken in queryTokens {
            var matched = false
            while titleIndex < titleTokens.count {
                if titleTokens[titleIndex].hasPrefix(queryToken) {
                    matched = true
                    titleIndex += 1
                    break
                }
                titleIndex += 1
            }
            if !matched { return false }
        }
        return true
    }
}
