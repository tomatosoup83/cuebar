import Foundation

/// What a row in the ⌘K quick-actions menu does.
public enum QuickAction: Equatable, Sendable {
    /// Run the row's normal action (play the song/album/playlist, or run a command).
    case primary
    /// Add the row's track to Music's "Loved" (heart) list.
    case like
    /// Remove the row's track from Music's "Loved" list.
    case unlike
    /// Open the "Add to Playlist" submenu.
    case openAddToPlaylist
    /// Add the row's track to a user playlist.
    case addToPlaylist(playlistID: String, name: String)
    /// Reveal the row in Music.app (or open its catalog page).
    case openInMusic
    /// Close the actions menu.
    case dismiss
}

/// A single row shown in the ⌘K quick-actions menu.
public struct QuickActionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let action: QuickAction
    /// Extra words the actions search field matches against.
    public let keywords: [String]
    /// Destructive rows (Dismiss) render in red, like Raycast.
    public let isDestructive: Bool
    /// A trailing shortcut hint, e.g. "↩".
    public let shortcut: String?

    public init(
        id: String,
        title: String,
        symbolName: String,
        action: QuickAction,
        keywords: [String] = [],
        isDestructive: Bool = false,
        shortcut: String? = nil
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.action = action
        self.keywords = keywords
        self.isDestructive = isDestructive
        self.shortcut = shortcut
    }
}

/// Builds the contextual quick actions for a row, and filters them.
public enum QuickActions {
    /// The actions offered for `item`.
    ///
    /// - `loved` is the track's current "Loved" state, or nil while unknown.
    /// - `canLike` is false for album/playlist/catalog-only rows, which have no
    ///   single library track to love or add.
    public static func items(
        for item: PaletteItem,
        loved: Bool? = nil,
        canLike: Bool = false
    ) -> [QuickActionItem] {
        var items: [QuickActionItem] = []

        switch item {
        case .nowPlaying(let track):
            items.append(primary(
                id: "primary",
                title: track.isPlaying ? "Pause" : "Play",
                symbolName: track.isPlaying ? "pause.fill" : "play.fill",
                keywords: ["play", "pause", "resume"]
            ))
            appendTrackActions(to: &items, loved: loved, canLike: canLike)

        case .command(let entry):
            items.append(primary(
                id: "run",
                title: "Run “\(entry.title)”",
                symbolName: entry.symbolName,
                keywords: ["run", "execute", "open"] + entry.keywords
            ))

        case .recent:
            items.append(primary(id: "play", title: "Play", symbolName: "play.fill", keywords: ["play"]))
            appendTrackActions(to: &items, loved: loved, canLike: canLike)

        case .music(let candidate):
            switch candidate.kind {
            case .album:
                items.append(primary(id: "play", title: "Play Album", symbolName: "play.fill", keywords: ["play", "album"]))
                items.append(openInMusicItem)
            case .playlist:
                items.append(primary(id: "play", title: "Play Playlist", symbolName: "play.fill", keywords: ["play", "playlist"]))
                items.append(openInMusicItem)
            case .song, .artist:
                items.append(primary(id: "play", title: "Play", symbolName: "play.fill", keywords: ["play"]))
                appendTrackActions(to: &items, loved: loved, canLike: canLike)
            }
        }

        items.append(dismissItem)
        return items
    }

    /// The user's playlists, as "Add to Playlist" rows.
    public static func playlistItems(_ playlists: [MusicCandidate]) -> [QuickActionItem] {
        playlists.compactMap { playlist in
            guard let id = playlist.persistentID, !id.isEmpty else { return nil }
            return QuickActionItem(
                id: "playlist:\(id)",
                title: playlist.title,
                symbolName: "music.note.list",
                action: .addToPlaylist(playlistID: id, name: playlist.title),
                keywords: [playlist.title]
            )
        }
    }

    /// Live filter for the actions search field. Empty query returns everything.
    public static func filter(_ items: [QuickActionItem], query: String) -> [QuickActionItem] {
        let normalized = TextNormalizer.normalize(query)
        guard !normalized.isEmpty else { return items }
        let tokens = normalized.split(separator: " ")
        return items.filter { item in
            let haystack = TextNormalizer.normalize(
                ([item.title] + item.keywords).joined(separator: " ")
            )
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: - Builders

    private static func appendTrackActions(
        to items: inout [QuickActionItem],
        loved: Bool?,
        canLike: Bool
    ) {
        if canLike {
            items.append(loveItem(loved: loved))
            items.append(addToPlaylistItem)
        }
        items.append(openInMusicItem)
    }

    private static func primary(
        id: String,
        title: String,
        symbolName: String,
        keywords: [String]
    ) -> QuickActionItem {
        QuickActionItem(
            id: id,
            title: title,
            symbolName: symbolName,
            action: .primary,
            keywords: keywords,
            shortcut: "↩"
        )
    }

    private static func loveItem(loved: Bool?) -> QuickActionItem {
        let isLoved = loved ?? false
        return QuickActionItem(
            id: "love",
            title: isLoved ? "Remove from Loved" : "Like",
            symbolName: isLoved ? "heart.fill" : "heart",
            action: isLoved ? .unlike : .like,
            keywords: ["like", "love", "favourite", "favorite", "heart", "unlike"]
        )
    }

    private static var addToPlaylistItem: QuickActionItem {
        QuickActionItem(
            id: "addToPlaylist",
            title: "Add to Playlist…",
            symbolName: "text.badge.plus",
            action: .openAddToPlaylist,
            keywords: ["playlist", "add", "queue"]
        )
    }

    private static var openInMusicItem: QuickActionItem {
        QuickActionItem(
            id: "openInMusic",
            title: "Open in Music",
            symbolName: "arrow.up.forward.app",
            action: .openInMusic,
            keywords: ["open", "music", "show", "reveal", "apple music"]
        )
    }

    private static var dismissItem: QuickActionItem {
        QuickActionItem(
            id: "dismiss",
            title: "Dismiss",
            symbolName: "xmark.circle",
            action: .dismiss,
            keywords: ["close", "cancel", "dismiss", "escape"],
            isDestructive: true,
            shortcut: "esc"
        )
    }
}
