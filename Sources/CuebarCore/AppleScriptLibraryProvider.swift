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

    /// Fetches the user's playlists (excluding system playlists and Cuebar's
    /// own album queue).
    public func fetchPlaylists() async throws -> [MusicCandidate] {
        let raw = try await runner.string(Self.playlistScript)
        return Self.parsePlaylists(raw)
    }

    /// Reads when each library track was last played, in one bulk Apple Event.
    ///
    /// Returns nothing when Music isn't running, so opening the palette never
    /// launches it.
    public func fetchPlayedDates() async throws -> [PlayedEntry] {
        guard AppleScriptMusicController.isMusicRunning else { return [] }
        let raw = try await runner.string(Self.playedDatesScript)
        return RecentlyPlayed.parse(raw)
    }

    // MARK: - Parsing

    static let listSeparator = "\u{1e}"   // ASCII record separator
    static let fieldSeparator = "\u{1f}"  // ASCII unit separator

    static func parse(_ raw: String) -> [MusicCandidate] {
        // The script joins ten property lists with the record separator.
        var sections = raw.components(separatedBy: listSeparator)
        while sections.count < 10 { sections.append("") }

        let names = split(sections[0])
        let artists = split(sections[1])
        let albums = split(sections[2])
        let ids = split(sections[3])
        let durations = split(sections[4])
        let albumArtists = split(sections[5])
        let discNumbers = split(sections[6])
        let trackNumbers = split(sections[7])
        let years = split(sections[8])
        let genres = split(sections[9])

        let count = names.count
        var tracks: [MusicCandidate] = []
        tracks.reserveCapacity(count)

        for index in 0..<count {
            let persistentID = value(ids, at: index)
            guard !persistentID.isEmpty else { continue }

            let title = value(names, at: index)
            guard !title.isEmpty else { continue }

            let duration = Double(value(durations, at: index))
            let albumArtist = value(albumArtists, at: index)
            tracks.append(
                MusicCandidate(
                    id: persistentID,
                    kind: .song,
                    source: .library,
                    title: title,
                    artist: value(artists, at: index),
                    album: value(albums, at: index),
                    durationSeconds: duration,
                    persistentID: persistentID,
                    albumArtist: albumArtist.isEmpty ? nil : albumArtist,
                    discNumber: Int(value(discNumbers, at: index)),
                    trackNumber: Int(value(trackNumbers, at: index)),
                    year: Int(value(years, at: index)),
                    genre: genres.isEmpty ? nil : nonEmpty(value(genres, at: index))
                )
            )
        }
        return tracks
    }

    private static func split(_ section: String) -> [String] {
        section.components(separatedBy: fieldSeparator)
    }

    /// `nil` for an empty field, so optional metadata round-trips as absent
    /// rather than as `""`.
    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    // MARK: - Playlists

    /// Parses one `name⟨US⟩id⟨US⟩count⟨US⟩firstTrackId⟨RS⟩` record per playlist.
    static func parsePlaylists(_ raw: String) -> [MusicCandidate] {
        var playlists: [MusicCandidate] = []

        for record in raw.components(separatedBy: listSeparator) where !record.isEmpty {
            let parts = record.components(separatedBy: fieldSeparator)
            guard parts.count >= 4 else { continue }

            let name = value(parts, at: 0)
            let persistentID = value(parts, at: 1)
            guard !name.isEmpty, !persistentID.isEmpty else { continue }
            guard name != AppleScriptMusicController.albumQueuePlaylistName else { continue }

            let trackCount = Int(value(parts, at: 2)) ?? 0
            guard trackCount > 0 else { continue }

            let firstTrackID = value(parts, at: 3)
            playlists.append(
                MusicCandidate(
                    id: "library:playlist:\(persistentID)",
                    kind: .playlist,
                    source: .library,
                    title: name,
                    artist: "",
                    album: "",
                    persistentID: persistentID,
                    trackCount: trackCount,
                    artworkTrackID: firstTrackID.isEmpty ? nil : firstTrackID
                )
            )
        }
        return playlists
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
    	try
    		set theAlbumArtists to album artist of every track of library playlist 1
    	on error
    		set theAlbumArtists to {}
    	end try
    	try
    		set theDiscNumbers to disc number of every track of library playlist 1
    	on error
    		set theDiscNumbers to {}
    	end try
    	try
    		set theTrackNumbers to track number of every track of library playlist 1
    	on error
    		set theTrackNumbers to {}
    	end try
    	try
    		set theYears to year of every track of library playlist 1
    	on error
    		set theYears to {}
    	end try
    	try
    		set theGenres to genre of every track of library playlist 1
    	on error
    		set theGenres to {}
    	end try
    	set AppleScript's text item delimiters to fieldSep
    	set namesText to theNames as string
    	set artistsText to theArtists as string
    	set albumsText to theAlbums as string
    	set idsText to theIds as string
    	set durationsText to theDurations as string
    	set albumArtistsText to theAlbumArtists as string
    	set discNumbersText to theDiscNumbers as string
    	set trackNumbersText to theTrackNumbers as string
    	set yearsText to theYears as string
    	set genresText to theGenres as string
    	set AppleScript's text item delimiters to ""
    end tell
    return namesText & listSep & artistsText & listSep & albumsText & listSep & idsText & listSep & durationsText & listSep & albumArtistsText & listSep & discNumbersText & listSep & trackNumbersText & listSep & yearsText & listSep & genresText
    """#

    /// Emits `id⟨US⟩secondsAgo⟨RS⟩` for every track that has been played.
    ///
    /// The two property lists are fetched in bulk; the loop runs locally (outside
    /// the `tell`), through a script object so list access stays O(1). Ages are
    /// relative to `current date`, which keeps the output locale-independent.
    static let playedDatesScript = #"""
    set fieldSep to (ASCII character 31)
    set listSep to (ASCII character 30)
    tell application "Music"
    	set theIds to persistent ID of every track of library playlist 1
    	try
    		set theDates to played date of every track of library playlist 1
    	on error
    		set theDates to {}
    	end try
    end tell
    set nowDate to current date
    script o
    	property ids : {}
    	property ds : {}
    	property out : {}
    end script
    set o's ids to theIds
    set o's ds to theDates
    set n to count of o's ds
    if (count of o's ids) < n then set n to count of o's ids
    repeat with i from 1 to n
    	set d to item i of o's ds
    	if class of d is date then
    		set end of o's out to (item i of o's ids) & fieldSep & (((nowDate - d) as integer) as string)
    	end if
    end repeat
    set AppleScript's text item delimiters to listSep
    set outText to (o's out) as string
    set AppleScript's text item delimiters to ""
    return outText
    """#

    static let playlistScript = #"""
    set fieldSep to (ASCII character 31)
    set listSep to (ASCII character 30)
    set out to ""
    tell application "Music"
    	repeat with p in user playlists
    		try
    			set pKind to (special kind of p as string)
    		on error
    			set pKind to ""
    		end try
    		if pKind is "none" then
    			try
    				set pName to name of p
    				set pID to persistent ID of p
    				set pCount to (count of tracks of p)
    				set firstID to ""
    				if pCount > 0 then
    					try
    						set firstID to persistent ID of track 1 of p
    					on error
    						set firstID to ""
    					end try
    				end if
    				set out to out & pName & fieldSep & pID & fieldSep & (pCount as string) & fieldSep & firstID & listSep
    			end try
    		end if
    	end repeat
    end tell
    return out
    """#
}
