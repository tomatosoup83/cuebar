import Foundation

/// A source of search results.
public protocol MusicSearchProviding: Sendable {
    func search(_ query: String, limit: Int) async throws -> [MusicCandidate]
}

/// Searches the in-memory library index. Local and effectively instant.
public final class LibrarySearchProvider: MusicSearchProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var tracks: [MusicCandidate] = []
    private var playlists: [MusicCandidate] = []
    private var albumIndex = LibraryAlbumIndex(tracks: [])

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

    /// Number of indexed playlists.
    public var playlistCount: Int {
        lock.lock(); defer { lock.unlock() }
        return playlists.count
    }

    /// The ordered tracks of a library album, or nil when unknown.
    public func tracks(forAlbumID id: String) -> [MusicCandidate]? {
        lock.lock(); defer { lock.unlock() }
        return albumIndex.tracks(forAlbumID: id)
    }

    public func search(_ query: String, limit: Int) async throws -> [MusicCandidate] {
        Ranking.rank(searchPool(), query: query, limit: limit)
    }

    /// Songs + derived album rows + playlists, copied under the lock.
    private func searchPool() -> [MusicCandidate] {
        lock.lock(); defer { lock.unlock() }
        return tracks + albumIndex.albums + playlists
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
        request.setValue("Cuebar/0.3 (macOS)", forHTTPHeaderField: "User-Agent")

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
