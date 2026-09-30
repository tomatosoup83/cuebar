import Foundation

/// The in-field filter shown as a chip in the search box.
///
/// Distinct from `RankPreference`: that is a *music* ranking, and a theme scope is
/// not a ranking at all. Scopes are therefore their own type, and only the music
/// ones map back to a preference.
public enum SearchScope: String, CaseIterable, Equatable, Sendable {
    case albums
    case playlists
    case themes

    /// The music ranking this scope implies, or nil when it isn't a music scope.
    public var rankPreference: RankPreference? {
        switch self {
        case .albums: return .albums
        case .playlists: return .playlists
        case .themes: return nil
        }
    }

    /// The word that creates the scope when typed with a space.
    public var keyword: String {
        switch self {
        case .albums: return "album"
        case .playlists: return "playlist"
        case .themes: return "theme"
        }
    }

    /// The chip label, and the badge on rows inside the scope.
    public var title: String {
        switch self {
        case .albums: return "Album"
        case .playlists: return "Playlist"
        case .themes: return "Theme"
        }
    }

    public var symbolName: String {
        switch self {
        case .albums: return "rectangle.stack"
        case .playlists: return "music.note.list"
        case .themes: return "paintpalette"
        }
    }

    /// The scope a keyword token creates, if any.
    static func scope(forToken token: String) -> SearchScope? {
        switch TextNormalizer.normalize(token) {
        case "album": return .albums
        case "playlist", "playlists": return .playlists
        case "theme", "themes": return .themes
        default: return nil
        }
    }
}
