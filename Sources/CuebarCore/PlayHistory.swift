import Foundation

/// A track Cuebar saw start playing.
public struct PlayRecord: Codable, Equatable, Sendable {
    public let persistentID: String
    public let playedAt: Date

    public init(persistentID: String, playedAt: Date) {
        self.persistentID = persistentID
        self.playedAt = playedAt
    }
}

/// What Music announces on every player change (`com.apple.Music.playerInfo`).
public struct PlayerInfoEvent: Equatable, Sendable {
    public static let notificationName = "com.apple.Music.playerInfo"

    public let persistentID: String?
    public let isPlaying: Bool
    public let isStopped: Bool

    public init(persistentID: String?, isPlaying: Bool, isStopped: Bool = false) {
        self.persistentID = persistentID
        self.isPlaying = isPlaying
        self.isStopped = isStopped
    }

    /// The track Music has loaded after this event, if any.
    public var loadedTrackID: String? { isStopped ? nil : persistentID }

    /// Reads the notification's `userInfo`.
    ///
    /// `PersistentID` arrives as a 64-bit integer; AppleScript (and so the
    /// library index) writes the same value as 16 upper-case hex digits.
    public static func parse(_ userInfo: [AnyHashable: Any]?) -> PlayerInfoEvent? {
        guard let userInfo else { return nil }
        let state = (userInfo["Player State"] as? String) ?? ""

        var id: String?
        if let number = userInfo["PersistentID"] as? NSNumber {
            id = String(format: "%016llX", number.uint64Value)
        }
        return PlayerInfoEvent(
            persistentID: id,
            isPlaying: state == "Playing",
            isStopped: state == "Stopped"
        )
    }
}

/// A short, persisted log of the tracks that started playing while Cuebar was
/// running.
///
/// Music's own `played date` is unreliable (streamed and partly played tracks are
/// often never stamped), so the home screen's "Recently Played" shelf merges this
/// log with it. Each track appears once, at its latest play.
public final class PlayHistory: @unchecked Sendable {
    public static let defaultLimit = 200

    private let fileURL: URL?
    private let limit: Int
    private let lock = NSLock()
    private var records: [PlayRecord] = []   // newest first

    /// - Parameter fileURL: where to persist; `nil` keeps the log in memory.
    public init(fileURL: URL? = nil, limit: Int = PlayHistory.defaultLimit) {
        self.fileURL = fileURL
        self.limit = max(1, limit)
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([PlayRecord].self, from: data) {
            records = Array(saved.sorted { $0.playedAt > $1.playedAt }.prefix(self.limit))
        }
    }

    /// The default on-disk log in Application Support.
    public static func standard(directoryName: String = "Cuebar") -> PlayHistory {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return PlayHistory(fileURL: directory.appendingPathComponent("play-history.json"))
    }

    /// Notes that `persistentID` is playing at `date`, moving it to the front.
    public func record(_ persistentID: String, at date: Date = Date()) {
        guard !persistentID.isEmpty else { return }
        lock.lock()
        records.removeAll { $0.persistentID == persistentID }
        records.insert(PlayRecord(persistentID: persistentID, playedAt: date), at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        let snapshot = records
        lock.unlock()
        save(snapshot)
    }

    /// Records the track an event describes, when it is a track that is playing.
    /// Returns whether anything was recorded.
    @discardableResult
    public func record(_ event: PlayerInfoEvent, at date: Date = Date()) -> Bool {
        guard event.isPlaying, let id = event.persistentID else { return false }
        record(id, at: date)
        return true
    }

    public var all: [PlayRecord] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    /// The log as ages relative to `now`, for merging with Music's played dates.
    public func entries(now: Date = Date()) -> [PlayedEntry] {
        all.map { PlayedEntry(persistentID: $0.persistentID, secondsAgo: max(0, now.timeIntervalSince($0.playedAt))) }
    }

    private func save(_ snapshot: [PlayRecord]) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
