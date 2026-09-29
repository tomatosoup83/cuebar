import Foundation

/// A parsed palette search: the term to search for plus an optional kind
/// preference.
///
/// A leading or trailing `album` / `playlist` keyword — separated by whitespace
/// from the rest — is a scope, not part of the term: `playlist focus` and
/// `focus playlist` both search for `focus` and prioritise playlists. Typing the
/// word alone (no space) stays a literal search, and the trailing keyword wins
/// if both appear.
public struct SearchQuery: Equatable, Sendable {
    public let term: String
    public let preference: RankPreference

    public init(term: String, preference: RankPreference = .songs) {
        self.term = term
        self.preference = preference
    }

    public static func parse(_ raw: String) -> SearchQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchQuery(term: "") }

        let tokens = trimmed.split(separator: " ").map(String.init)
        let hasLeadingSpace = raw.first?.isWhitespace ?? false
        let hasTrailingSpace = raw.last?.isWhitespace ?? false

        // Trailing keyword wins.
        if let last = tokens.last, let preference = preference(for: last),
           tokens.count > 1 || hasLeadingSpace {
            return SearchQuery(term: tokens.dropLast().joined(separator: " "), preference: preference)
        }
        if let first = tokens.first, let preference = preference(for: first),
           tokens.count > 1 || hasTrailingSpace {
            return SearchQuery(term: tokens.dropFirst().joined(separator: " "), preference: preference)
        }
        return SearchQuery(term: trimmed)
    }

    private static func preference(for token: String) -> RankPreference? {
        switch TextNormalizer.normalize(token) {
        case "album": return .albums
        case "playlist", "playlists": return .playlists
        default: return nil
        }
    }
}
