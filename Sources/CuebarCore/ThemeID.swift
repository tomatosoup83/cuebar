import Foundation

/// A selectable palette theme for the panel.
public enum ThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Apple's plain Liquid Glass — Cuebar's original look.
    case tahoe
    /// A light gradient derived from the now-playing track's album art.
    case albumArt

    public var id: String { rawValue }

    /// Name shown in Settings and the `theme` command rows.
    public var title: String {
        switch self {
        case .tahoe: return "Tahoe"
        case .albumArt: return "Album Art"
        }
    }

    /// One-line description of the theme.
    public var blurb: String {
        switch self {
        case .tahoe: return "Plain Liquid Glass"
        case .albumArt: return "Tinted with the album cover"
        }
    }

    /// Symbol used when the theme is listed as a command row.
    public var symbolName: String {
        switch self {
        case .tahoe: return "circle.lefthalf.filled"
        case .albumArt: return "paintpalette"
        }
    }

    /// Words the user can type to surface this theme as a command row.
    public var keywords: [String] {
        switch self {
        case .tahoe:
            return ["theme tahoe", "tahoe theme", "theme", "tahoe", "liquid glass", "glass"]
        case .albumArt:
            return [
                "theme album art",
                "album art theme",
                "theme",
                "album art",
                "albumart",
                "gradient",
                "tint",
                "album colour",
                "album color"
            ]
        }
    }
}
