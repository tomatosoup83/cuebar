import Foundation

/// A parsed palette search: the term to search for plus an optional in-field scope.
///
/// A leading or trailing `album` / `playlist` / `theme` keyword — separated by
/// whitespace from the rest — is a scope, not part of the term: `playlist focus`
/// and `focus playlist` both search for `focus` and prioritise playlists. Typing
/// the word alone (no space) stays a literal search, and the trailing keyword wins
/// if both appear.
public struct SearchQuery: Equatable, Sendable {
    public let term: String
    /// The active in-field filter, or nil for a plain search.
    public let scope: SearchScope?

    public init(term: String, scope: SearchScope? = nil) {
        self.term = term
        self.scope = scope
    }

    /// Convenience for callers that think in music rankings.
    public init(term: String, preference: RankPreference) {
        let scope: SearchScope?
        switch preference {
        case .albums: scope = .albums
        case .playlists: scope = .playlists
        case .songs: scope = nil
        }
        self.init(term: term, scope: scope)
    }

    /// The music ranking this query implies — `.songs` when unfiltered, or when the
    /// scope isn't a music one.
    public var preference: RankPreference { scope?.rankPreference ?? .songs }

    public static func parse(_ raw: String) -> SearchQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchQuery(term: "") }

        let tokens = trimmed.split(separator: " ").map(String.init)
        let hasLeadingSpace = raw.first?.isWhitespace ?? false
        let hasTrailingSpace = raw.last?.isWhitespace ?? false

        // Trailing keyword wins.
        if let last = tokens.last, let scope = SearchScope.scope(forToken: last),
           tokens.count > 1 || hasLeadingSpace {
            return SearchQuery(term: tokens.dropLast().joined(separator: " "), scope: scope)
        }
        if let first = tokens.first, let scope = SearchScope.scope(forToken: first),
           tokens.count > 1 || hasTrailingSpace {
            return SearchQuery(term: tokens.dropFirst().joined(separator: " "), scope: scope)
        }
        return SearchQuery(term: trimmed)
    }
}
