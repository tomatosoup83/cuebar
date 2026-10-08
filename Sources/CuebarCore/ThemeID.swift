import Foundation

/// A selectable palette theme for the panel.
public enum ThemeID: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Apple's plain Liquid Glass — Cuebar's original look.
    case tahoe
    /// A light gradient derived from the now-playing track's album art, using
    /// the original top/bottom-thirds + histogram extraction.
    case albumArt
    /// Album Art, but the stops come from median-cut clusters instead of a
    /// single histogram bucket. An opt-in A/B against `albumArt`.
    case albumArtV2

    public var id: String { rawValue }

    /// True for themes that tint the panel from album artwork (both Album Art
    /// variants), so callers can branch on the *family* rather than one case.
    public var isAlbumArt: Bool { self != .tahoe }

    /// The extraction algorithm this theme resolves artwork with, or nil when
    /// the theme does not use album art at all.
    public var paletteAlgorithm: PaletteExtractor.Algorithm? {
        switch self {
        case .tahoe: return nil
        case .albumArt: return .classic
        case .albumArtV2: return .clustered
        }
    }

    /// The full extraction recipe for this theme, given the user's global-colours
    /// preference. The preference only affects the clustered Album Art v2 theme;
    /// the classic path always keeps its gradient.
    public func paletteStyle(globalClusteredColours: Bool) -> PaletteStyle? {
        guard let algorithm = paletteAlgorithm else { return nil }
        let layout: PaletteExtractor.ClusterLayout =
            (algorithm == .clustered && globalClusteredColours) ? .global : .gradient
        return PaletteStyle(algorithm: algorithm, clusterLayout: layout)
    }

    /// Name shown in Settings and the `theme` command rows.
    public var title: String {
        switch self {
        case .tahoe: return "Tahoe"
        case .albumArt: return "Album Art"
        case .albumArtV2: return "Album Art v2"
        }
    }

    /// One-line description of the theme.
    public var blurb: String {
        switch self {
        case .tahoe: return "Plain Liquid Glass"
        case .albumArt: return "Tinted with the album cover"
        case .albumArtV2: return "Clustered album-cover colour"
        }
    }

    /// Symbol used when the theme is listed as a command row.
    public var symbolName: String {
        switch self {
        case .tahoe: return "circle.lefthalf.filled"
        case .albumArt: return "paintpalette"
        case .albumArtV2: return "circle.hexagongrid.fill"
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
        case .albumArtV2:
            return [
                "theme album art v2",
                "album art v2",
                "theme v2",
                "theme",
                "album art",
                "albumart v2",
                "albumartv2",
                "v2",
                "clustered",
                "cluster",
                "gradient",
                "tint",
                "album colour",
                "album color"
            ]
        }
    }
}
