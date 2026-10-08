import Foundation

/// The random list shown when a scope (`album ` / `playlist ` / `artist `) is
/// active but nothing has been typed: pick that kind's pool, shuffle, cap.
public enum LibraryBrowse {
    public static func items(
        albums: [MusicCandidate],
        playlists: [MusicCandidate],
        artists: [MusicCandidate] = [],
        preference: RankPreference,
        limit: Int
    ) -> [MusicCandidate] {
        var generator = SystemRandomNumberGenerator()
        return items(
            albums: albums,
            playlists: playlists,
            artists: artists,
            preference: preference,
            limit: limit,
            using: &generator
        )
    }

    public static func items(
        albums: [MusicCandidate],
        playlists: [MusicCandidate],
        artists: [MusicCandidate] = [],
        preference: RankPreference,
        limit: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [MusicCandidate] {
        let pool: [MusicCandidate]
        switch preference {
        case .albums: pool = albums
        case .playlists: pool = playlists
        case .artists: pool = artists
        case .songs: pool = []
        }

        return shuffled(pool, limit: limit, using: &generator)
    }

    /// A shuffled sample of `pool`, capped at `limit`.
    ///
    /// Used for the artist *page*, which shuffles one artist's songs rather than
    /// a kind's items.
    public static func shuffled(_ pool: [MusicCandidate], limit: Int) -> [MusicCandidate] {
        var generator = SystemRandomNumberGenerator()
        return shuffled(pool, limit: limit, using: &generator)
    }

    public static func shuffled(
        _ pool: [MusicCandidate],
        limit: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [MusicCandidate] {
        guard limit > 0 else { return [] }
        return Array(pool.shuffled(using: &generator).prefix(limit))
    }
}
