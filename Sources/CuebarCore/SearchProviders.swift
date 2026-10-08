import Foundation

/// A source of search results.
public protocol MusicSearchProviding: Sendable {
    func search(_ query: String, limit: Int) async throws -> [MusicCandidate]
    /// A random list of a kind's items, for the empty-scope browse mode.
    func browse(_ preference: RankPreference, limit: Int) async -> [MusicCandidate]
}

public extension MusicSearchProviding {
    /// Sources without a local catalogue (e.g. the iTunes API) browse to nothing.
    func browse(_ preference: RankPreference, limit: Int) async -> [MusicCandidate] { [] }
}

/// Searches the in-memory library index. Local and effectively instant.
public final class LibrarySearchProvider: MusicSearchProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var tracks: [MusicCandidate] = []
    private var playlists: [MusicCandidate] = []
    private var albumIndex = LibraryAlbumIndex(tracks: [])
    private var artistIndex = LibraryArtistIndex(tracks: [])

    public init() {}

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return tracks.count
    }

    public func setIndex(_ tracks: [MusicCandidate]) {
        setIndex(tracks, playlists: [])
    }

    public func setIndex(_ tracks: [MusicCandidate], playlists: [MusicCandidate]) {
        lock.lock(); defer { lock.unlock() }
        self.tracks = tracks
        self.playlists = playlists
        self.albumIndex = LibraryAlbumIndex(tracks: tracks)
        self.artistIndex = LibraryArtistIndex(tracks: tracks)
    }

    /// Songs only — catalog→library resolution must never see album/playlist rows.
    public func snapshot() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return tracks
    }

    public func albums() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return albumIndex.albums
    }

    /// Every derived artist row, alphabetically (the ranker re-sorts).
    public func artists() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return artistIndex.artists
    }

    /// Searches **only** artists, for the `artist ` scope's hard filter. The
    /// whole artist pool is ranked, so a broad query can't be crowded out by
    /// thousands of song matches before the filter is applied.
    public func searchArtists(_ query: String, limit: Int) -> [MusicCandidate] {
        let pool = artists()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return Array(pool.prefix(limit)) }
        return Ranking.rank(pool, query: term, preference: .artists, limit: limit)
    }

    /// Number of indexed playlists.
    public var playlistCount: Int {
        lock.lock(); defer { lock.unlock() }
        return playlists.count
    }

    /// All indexed user playlists, for the "Add to Playlist" actions menu.
    public func playlistSnapshot() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return playlists
    }

    /// The ordered tracks of a library album, or nil when unknown.
    public func tracks(forAlbumID id: String) -> [MusicCandidate]? {
        lock.lock(); defer { lock.unlock() }
        return albumIndex.tracks(forAlbumID: id)
    }

    /// Every track by a library artist, or nil when unknown.
    public func tracks(forArtistID id: String) -> [MusicCandidate]? {
        lock.lock(); defer { lock.unlock() }
        return artistIndex.tracks(forArtistID: id)
    }

    public func search(_ query: String, limit: Int) async throws -> [MusicCandidate] {
        Ranking.rank(searchPool(), query: query, limit: limit)
    }

    /// Searches the whole pool for a parsed query, honouring its scope.
    ///
    /// Ranks the full pool once with the query's own preference, which is what
    /// `SearchService` reaches by ranking its (already truncated) library pass a
    /// second time. Callers that need a single best row — the headless
    /// `cuebar://` path — use this so an `album `-scoped query can't lose its
    /// albums to the song-first pre-ranking.
    public func search(_ query: SearchQuery, limit: Int) -> [MusicCandidate] {
        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        if query.scope?.selectsOnlyItsKind == true {
            return searchArtists(term, limit: limit)
        }
        return Ranking.rank(searchPool(), query: term, preference: query.preference, limit: limit)
    }

    public func browse(_ preference: RankPreference, limit: Int) async -> [MusicCandidate] {
        let pool = browsePool()
        return LibraryBrowse.items(
            albums: pool.albums,
            playlists: pool.playlists,
            artists: pool.artists,
            preference: preference,
            limit: limit
        )
    }

    /// Songs + derived album rows + derived artist rows + playlists, copied
    /// under the lock.
    private func searchPool() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return tracks + albumIndex.albums + artistIndex.artists + playlists
    }

    private func browsePool() -> (
        albums: [MusicCandidate],
        playlists: [MusicCandidate],
        artists: [MusicCandidate]
    ) {
        lock.lock(); defer { lock.unlock() }
        return (albumIndex.albums, playlists, artistIndex.artists)
    }
}

/// Searches the public iTunes Search API. No authentication required.
public final class ITunesCatalogProvider: MusicSearchProviding, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(_ query: String, limit: Int) async throws -> [MusicCandidate] {
        async let songs = fetch(entity: "song", query: query, limit: limit)
        async let albums = fetch(entity: "album", query: query, limit: max(3, limit / 3))
        return try await songs + albums
    }

    private func fetch(entity: String, query: String, limit: Int) async throws -> [MusicCandidate] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Cuebar/0.8 (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
        return decoded.results.compactMap { $0.candidate(entity: entity) }
    }
}

private struct ITunesResponse: Decodable {
    let results: [ITunesItem]
}

private struct ITunesItem: Decodable {
    let wrapperType: String?
    let trackId: Int?
    let collectionId: Int?
    let trackName: String?
    let collectionName: String?
    let artistName: String?
    let artworkUrl100: String?
    let trackViewUrl: String?
    let collectionViewUrl: String?
    let trackTimeMillis: Int?

    func candidate(entity: String) -> MusicCandidate? {
        let isSong = trackName != nil
        let title = trackName ?? collectionName
        guard let title, !title.isEmpty else { return nil }

        let id: String
        if isSong, let trackId {
            id = "catalog:song:\(trackId)"
        } else if let collectionId {
            id = "catalog:album:\(collectionId)"
        } else {
            return nil
        }

        let playback = isSong ? trackViewUrl : collectionViewUrl
        let artwork = artworkUrl100.map { $0.replacingOccurrences(of: "100x100bb", with: "200x200bb") }

        return MusicCandidate(
            id: id,
            kind: isSong ? .song : .album,
            source: .catalog,
            title: title,
            artist: artistName ?? "",
            album: isSong ? (collectionName ?? "") : "",
            durationSeconds: trackTimeMillis.map { Double($0) / 1000.0 },
            artworkURL: artwork.flatMap(URL.init(string:)),
            playbackURL: playback.flatMap(URL.init(string:))
        )
    }
}
