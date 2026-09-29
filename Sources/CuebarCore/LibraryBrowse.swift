import Foundation

/// The random list shown when a scope (`album ` / `playlist `) is active but
/// nothing has been typed: pick that kind's pool, shuffle, cap.
public enum LibraryBrowse {
    public static func items(
        albums: [MusicCandidate],
        playlists: [MusicCandidate],
        preference: RankPreference,
        limit: Int
    ) -> [MusicCandidate] {
        var generator = SystemRandomNumberGenerator()
        return items(
            albums: albums,
            playlists: playlists,
            preference: preference,
            limit: limit,
            using: &generator
        )
    }

    public static func items(
        albums: [MusicCandidate],
        playlists: [MusicCandidate],
        preference: RankPreference,
        limit: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [MusicCandidate] {
        guard limit > 0 else { return [] }

        let pool: [MusicCandidate]
        switch preference {
        case .albums: pool = albums
        case .playlists: pool = playlists
        case .songs: pool = []
        }

        return Array(pool.shuffled(using: &generator).prefix(limit))
    }
}
