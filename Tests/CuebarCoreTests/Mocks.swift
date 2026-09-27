import Foundation
import CuebarCore

final class MockSearchProvider: MusicSearchProviding, @unchecked Sendable {
    private let handler: @Sendable (String, Int) async throws -> [MusicCandidate]
    private let lock = NSLock()
    private var recordedQueries: [String] = []

    init(handler: @escaping @Sendable (String, Int) async throws -> [MusicCandidate]) {
        self.handler = handler
    }

    convenience init(results: [MusicCandidate]) {
        self.init { _, limit in Array(results.prefix(limit)) }
    }

    var queries: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedQueries
    }

    func search(_ query: String, limit: Int) async throws -> [MusicCandidate] {
        lock.lock(); recordedQueries.append(query); lock.unlock()
        return try await handler(query, limit)
    }
}

final class MockMusicController: MusicController, @unchecked Sendable {
    enum Call: Equatable {
        case play(String)
        case pause
        case resume
        case next
        case previous
        case shuffle(Bool?)
    }

    private let lock = NSLock()
    private var storage: [Call] = []
    var errorToThrow: Error?
    var nowPlayingResult: NowPlayingTrack?

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    private func record(_ call: Call) {
        lock.lock(); defer { lock.unlock() }
        storage.append(call)
    }

    func play(_ candidate: MusicCandidate) async throws {
        if let errorToThrow { throw errorToThrow }
        record(.play(candidate.id))
    }

    func pause() async throws { record(.pause) }
    func resume() async throws { record(.resume) }
    func next() async throws { record(.next) }
    func previous() async throws { record(.previous) }
    func setShuffle(_ enabled: Bool) async throws { record(.shuffle(enabled)) }
    func toggleShuffle() async throws { record(.shuffle(nil)) }
    func nowPlaying() async throws -> NowPlayingTrack? { nowPlayingResult }
}
