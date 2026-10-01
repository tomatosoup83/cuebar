import Foundation

/// When a library track was last played, as read from Music.
public struct PlayedEntry: Equatable, Sendable {
    public let persistentID: String
    /// Seconds between the play and the moment the script ran.
    public let secondsAgo: Double

    public init(persistentID: String, secondsAgo: Double) {
        self.persistentID = persistentID
        self.secondsAgo = secondsAgo
    }
}

/// A library track on the home screen's "Recently Played" shelf.
public struct RecentTrack: Identifiable, Equatable, Sendable {
    public let candidate: MusicCandidate
    public let playedAt: Date

    public var id: String { candidate.id }

    public init(candidate: MusicCandidate, playedAt: Date) {
        self.candidate = candidate
        self.playedAt = playedAt
    }
}

/// Builds the "Recently Played" list from Music's `played date`s.
public enum RecentlyPlayed {
    /// How many tracks the home screen shows.
    public static let defaultLimit = 8

    /// Parses `id⟨US⟩secondsAgo⟨RS⟩…` records; malformed records are skipped.
    public static func parse(_ raw: String) -> [PlayedEntry] {
        raw.components(separatedBy: AppleScriptLibraryProvider.listSeparator).compactMap { record in
            let parts = record.components(separatedBy: AppleScriptLibraryProvider.fieldSeparator)
            guard parts.count >= 2 else { return nil }
            let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard !id.isEmpty, let ago = Double(seconds), ago >= 0 else { return nil }
            return PlayedEntry(persistentID: id, secondsAgo: ago)
        }
    }

    /// The most recently played library songs, newest first.
    ///
    /// Entries that aren't in the index (deleted since, or not songs) are
    /// dropped, each track appears once, and the track that is playing right now
    /// is left out — it already has the now-playing card.
    public static func tracks(
        from entries: [PlayedEntry],
        library: [MusicCandidate],
        excluding nowPlayingID: String? = nil,
        limit: Int = defaultLimit,
        now: Date = Date()
    ) -> [RecentTrack] {
        guard limit > 0, !entries.isEmpty else { return [] }

        var byID: [String: MusicCandidate] = [:]
        byID.reserveCapacity(library.count)
        for track in library where track.kind == .song && track.source == .library {
            if let id = track.persistentID { byID[id] = track }
        }

        let ordered = entries.sorted {
            if $0.secondsAgo != $1.secondsAgo { return $0.secondsAgo < $1.secondsAgo }
            return $0.persistentID < $1.persistentID
        }

        var seen = Set<String>()
        var result: [RecentTrack] = []
        for entry in ordered {
            guard entry.persistentID != nowPlayingID,
                  let candidate = byID[entry.persistentID],
                  seen.insert(entry.persistentID).inserted else { continue }
            result.append(RecentTrack(
                candidate: candidate,
                playedAt: now.addingTimeInterval(-entry.secondsAgo)
            ))
            if result.count == limit { break }
        }
        return result
    }

    /// A compact "how long ago" label: `Just now`, `5m ago`, `3h ago`,
    /// `Yesterday`, `4d ago`, `2w ago`, `3mo ago`, `1y ago`.
    public static func relativeLabel(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minute = 60.0, hour = 3600.0, day = 86_400.0

        if seconds < minute { return "Just now" }
        if seconds < hour { return "\(Int(seconds / minute))m ago" }
        if seconds < day { return "\(Int(seconds / hour))h ago" }
        if seconds < 2 * day { return "Yesterday" }
        if seconds < 7 * day { return "\(Int(seconds / day))d ago" }
        if seconds < 30 * day { return "\(Int(seconds / (7 * day)))w ago" }
        if seconds < 365 * day { return "\(Int(seconds / (30 * day)))mo ago" }
        return "\(Int(seconds / (365 * day)))y ago"
    }
}
