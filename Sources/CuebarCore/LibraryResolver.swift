import Foundation

/// Maps an Apple Music catalog item onto the matching track in the user's
/// library, so selecting a catalog row can play the local copy.
///
/// Deliberately conservative: an artist that is *known* and disagrees is never
/// overridden by a title match, and a unique title alone is not enough to
/// identify a track. When the catalog item can't be identified confidently, it
/// returns nil rather than guessing and playing the wrong song.
public enum LibraryResolver {
    public static func resolve(
        _ candidate: MusicCandidate,
        in library: [MusicCandidate]
    ) -> MusicCandidate? {
        // Already a library item.
        if candidate.source == .library { return candidate }

        // Only songs are playable by persistent ID; a catalog album or artist
        // must never resolve onto a same-named library song.
        guard candidate.kind == .song else { return nil }

        let title = candidate.normalizedTitle
        guard !title.isEmpty else { return nil }
        let artist = candidate.normalizedArtist

        let sameTitle = library.filter { $0.kind == .song && $0.normalizedTitle == title }
        if !sameTitle.isEmpty {
            guard !artist.isEmpty else {
                // The catalog artist is unknown, so a unique title is the only
                // safe signal; several copies are ambiguous.
                return sameTitle.count == 1 ? sameTitle[0] : nil
            }
            if let exact = sameTitle.first(where: { $0.normalizedArtist == artist }) {
                return exact
            }
            if let loose = sameTitle.first(where: { artistMatches(artist, $0.normalizedArtist) }) {
                return loose
            }
            // A known artist that disagrees is decisive: never fall back to a
            // same-title library song by someone else (covers, remixes, …).
            return nil
        }

        return nearMatch(candidate, in: library)
    }

    /// Handles small title differences ("Blinding Light" vs "Blinding Lights").
    private static func nearMatch(
        _ candidate: MusicCandidate,
        in library: [MusicCandidate]
    ) -> MusicCandidate? {
        // A fuzzy title is only acceptable when the artist can confirm it.
        let artist = candidate.normalizedArtist
        guard !artist.isEmpty else { return nil }

        let ranked = Ranking.rank(library, query: candidate.title, limit: 8)
        for result in ranked where result.kind == .song {
            let similarity = Similarity.ratio(candidate.normalizedTitle, result.normalizedTitle)
            guard similarity >= 0.85 else { continue }
            if result.normalizedArtist == artist
                || artistMatches(artist, result.normalizedArtist) {
                return result
            }
        }
        return nil
    }

    /// Whole-token artist agreement: `"the beatles"` matches `"beatles"`, but
    /// `"muse"` does not match `"museum"`.
    private static func artistMatches(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs == rhs { return true }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }
        return lhsTokens.isSubset(of: rhsTokens) || rhsTokens.isSubset(of: lhsTokens)
    }
}
