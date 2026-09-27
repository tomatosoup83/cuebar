import Foundation

/// Read-only access to the user's Music.app library via AppleScript.
///
/// A full enumeration of ~6k tracks takes well under a second because each
/// property is fetched in a single bulk Apple Event instead of per-track.
public final class AppleScriptLibraryProvider: @unchecked Sendable {
    private let runner: AppleScriptRunner

    public init(runner: AppleScriptRunner = .shared) {
        self.runner = runner
    }

    /// Fetches every track in the main library.
    public func fetchLibrary() async throws -> [MusicCandidate] {
        let raw = try await runner.string(Self.enumerationScript)
        return Self.parse(raw)
    }

    // MARK: - Parsing

    static let listSeparator = "\u{1e}"   // ASCII record separator
    static let fieldSeparator = "\u{1f}"  // ASCII unit separator

    static func parse(_ raw: String) -> [MusicCandidate] {
        // The script joins five property lists with the record separator.
        var sections = raw.components(separatedBy: listSeparator)
        while sections.count < 5 { sections.append("") }

        let names = split(sections[0])
        let artists = split(sections[1])
        let albums = split(sections[2])
        let ids = split(sections[3])
        let durations = split(sections[4])

        let count = names.count
        var tracks: [MusicCandidate] = []
        tracks.reserveCapacity(count)

        for index in 0..<count {
            let persistentID = value(ids, at: index)
            guard !persistentID.isEmpty else { continue }

            let title = value(names, at: index)
            guard !title.isEmpty else { continue }

            let duration = Double(value(durations, at: index))
            tracks.append(
                MusicCandidate(
                    id: persistentID,
                    kind: .song,
                    source: .library,
                    title: title,
                    artist: value(artists, at: index),
                    album: value(albums, at: index),
                    durationSeconds: duration,
                    persistentID: persistentID
                )
            )
        }
        return tracks
    }

    private static func split(_ section: String) -> [String] {
        section.components(separatedBy: fieldSeparator)
    }

    private static func value(_ list: [String], at index: Int) -> String {
        guard index < list.count else { return "" }
        let raw = list[index]
        // AppleScript coerces `missing value` to the literal string below.
        if raw == "missing value" { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AppleScript

    static let enumerationScript = #"""
    set fieldSep to (ASCII character 31)
    set listSep to (ASCII character 30)
    tell application "Music"
    	set theNames to name of every track of library playlist 1
    	try
    		set theArtists to artist of every track of library playlist 1
    	on error
    		set theArtists to {}
    	end try
    	try
    		set theAlbums to album of every track of library playlist 1
    	on error
    		set theAlbums to {}
    	end try
    	try
    		set theIds to persistent ID of every track of library playlist 1
    	on error
    		set theIds to {}
    	end try
    	try
    		set theDurations to duration of every track of library playlist 1
    	on error
    		set theDurations to {}
    	end try
    	set AppleScript's text item delimiters to fieldSep
    	set namesText to theNames as string
    	set artistsText to theArtists as string
    	set albumsText to theAlbums as string
    	set idsText to theIds as string
    	set durationsText to theDurations as string
    	set AppleScript's text item delimiters to ""
    end tell
    return namesText & listSep & artistsText & listSep & albumsText & listSep & idsText & listSep & durationsText
    """#
}
