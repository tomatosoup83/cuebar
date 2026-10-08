import Foundation

/// A Cuebar command that runs without the palette window.
///
/// The inbound path for `cuebar://` URLs (see `CuebarURL`): a launcher such as
/// Raycast sends the same string you would type into the palette, and the
/// palette's own vocabulary decides what it means.
public enum HeadlessAction: Equatable, Sendable {
    case music(Command)
    /// Re-scan the Music library. The shell owns the rebuild itself (it holds
    /// the AppleScript provider and the index store); the runner calls back.
    case rebuildLibraryIndex

    /// True when the action can only resolve once the library index is loaded.
    ///
    /// Transport commands (`pause`, `next`, …) never wait, and neither does a
    /// rebuild — being unable to load the index is exactly when you want to
    /// rebuild it.
    public var needsIndexedLibrary: Bool {
        switch self {
        case .rebuildLibraryIndex:
            return false
        case .music(.play(let query)):
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .music:
            return false
        }
    }
}

/// Why a headless command could not run.
public enum HeadlessCommandError: Error, LocalizedError, Equatable, Sendable {
    case emptyInput
    /// A command that only exists in the palette window (settings, themes).
    case paletteOnly(String)
    case noMatch(String)
    case notInLibrary(String)
    case emptyAlbum(String)
    /// Artist rows are pages, not playable items.
    case artistUnsupported(String)
    case rebuildFailed
    case libraryNotReady

    public var errorDescription: String? { toast.message }
}

public extension HeadlessCommandError {
    /// The toast the shell shows. Kept here so the wording is testable and the
    /// generic playback copy (`PlaybackFeedback`) can be reused.
    var toast: Toast {
        switch self {
        case .emptyInput:
            return Toast(kind: .error, message: "Nothing for Cuebar to run")
        case .paletteOnly(let title):
            return Toast(
                kind: .error,
                message: "“\(title)” only works in the Cuebar window",
                detail: "Open Cuebar to use it."
            )
        case .noMatch(let term):
            return Toast(
                kind: .error,
                message: "No match for “\(term)”",
                detail: "Nothing in your Music library matched."
            )
        case .notInLibrary(let title):
            return PlaybackFeedback.notInLibrary(title)
        case .emptyAlbum(let title):
            return PlaybackFeedback.emptyAlbum(title)
        case .artistUnsupported(let name):
            return Toast(
                kind: .error,
                message: "“\(name)” is an artist",
                detail: "Artist pages open in the Cuebar window."
            )
        case .rebuildFailed:
            return PlaybackFeedback.indexRebuildFailed()
        case .libraryNotReady:
            return Toast(
                kind: .error,
                message: "Cuebar is still indexing your library",
                detail: "Try again in a moment."
            )
        }
    }
}

/// Turns palette-style input into a `HeadlessAction`.
///
/// Deliberately *exact* where the palette is fuzzy: the palette shows ranked
/// rows while you type, but a URL has no list to choose from, so only an exact
/// command-catalog match is treated as a command. Everything else falls through
/// to `CommandParser`, exactly as pressing Return on the palette's field does.
public enum HeadlessCommandParser {
    public static func parse(_ input: String) throws -> HeadlessAction {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeadlessCommandError.emptyInput }

        if let entry = exactCatalogEntry(for: trimmed) {
            switch entry.action {
            case .music(let command):
                return .music(command)
            case .rebuildLibraryIndex:
                return .rebuildLibraryIndex
            default:
                // settings / theme / update / follow-selection: window-only.
                throw HeadlessCommandError.paletteOnly(entry.title)
            }
        }

        guard let command = CommandParser.parse(trimmed) else {
            throw HeadlessCommandError.emptyInput
        }
        return .music(command)
    }

    /// The catalog entry whose keyword the input matches *exactly*, if any.
    ///
    /// `CommandCatalog.score` returns 1000 only for an exact keyword match, so
    /// "rebuild" is a command while "rebuilding my library" stays a song search.
    static func exactCatalogEntry(for input: String) -> CommandEntry? {
        let normalized = TextNormalizer.normalize(input)
        guard !normalized.isEmpty else { return nil }
        return CommandCatalog.all.first {
            CommandCatalog.score($0, normalizedInput: normalized) == 1000
        }
    }
}

/// What a headless command did, so the shell can show the palette's toast.
public enum HeadlessOutcome: Equatable, Sendable {
    case played(MusicCandidate)
    case playedAlbum(MusicCandidate, trackCount: Int)
    case playedPlaylist(MusicCandidate, trackCount: Int)
    case transport(Command, shuffleBefore: Bool?)
    case rebuiltLibraryIndex(LibraryIndexSummary)
}

/// A library rebuild, injected so the runner stays free of AppKit and Music.
public typealias LibraryRebuild = @Sendable () async -> LibraryIndexSummary?

/// Runs Cuebar commands without the palette: resolve a query against the
/// library index, then drive Music through the shared `CommandExecutor`.
///
/// Search is **library-only**. The palette falls back to the iTunes catalog so
/// it can show results for songs the user doesn't own, but a catalog row can't
/// be played — every play path ends in a library track. Skipping the fallback
/// keeps a URL command off the network entirely.
public final class HeadlessCommandRunner: Sendable {
    private let library: LibrarySearchProvider
    private let musicController: MusicController
    private let executor: CommandExecutor
    private let rebuild: LibraryRebuild
    private let resultLimit: Int

    public init(
        library: LibrarySearchProvider,
        musicController: MusicController,
        rebuild: @escaping LibraryRebuild = { nil },
        resultLimit: Int = 40
    ) {
        self.library = library
        self.musicController = musicController
        self.executor = CommandExecutor(controller: musicController)
        self.rebuild = rebuild
        self.resultLimit = resultLimit
    }

    public func run(_ action: HeadlessAction) async throws -> HeadlessOutcome {
        switch action {
        case .rebuildLibraryIndex:
            guard let summary = await rebuild() else {
                throw HeadlessCommandError.rebuildFailed
            }
            return .rebuiltLibraryIndex(summary)
        case .music(let command):
            return try await run(command)
        }
    }

    private func run(_ command: Command) async throws -> HeadlessOutcome {
        if case .play(let term) = command,
           !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await play(matching: term)
        }

        // Matches the palette: a shuffle toggle reports the value it landed on,
        // read back before the change.
        var shuffleBefore: Bool?
        if case .shuffle(.toggle) = command {
            shuffleBefore = try? await musicController.shuffleEnabled()
        }
        try await executor.execute(command, selected: nil)
        return .transport(command, shuffleBefore: shuffleBefore)
    }

    /// Resolves a palette search term to the row the palette would have played.
    private func play(matching term: String) async throws -> HeadlessOutcome {
        let query = SearchQuery.parse(term)
        if case .themes = query.scope {
            throw HeadlessCommandError.paletteOnly("Theme")
        }

        let rows = library.search(query, limit: resultLimit)
        guard let top = rows.first else {
            throw HeadlessCommandError.noMatch(query.term)
        }

        switch top.kind {
        case .artist:
            throw HeadlessCommandError.artistUnsupported(top.title)

        case .album:
            // A library album plays start to finish, in running order.
            guard let tracks = library.tracks(forAlbumID: top.id), !tracks.isEmpty else {
                throw HeadlessCommandError.emptyAlbum(top.title)
            }
            try await executor.executeAlbum(tracks)
            return .playedAlbum(top, trackCount: tracks.count)

        case .playlist:
            try await executor.executePlaylist(top)
            return .playedPlaylist(top, trackCount: top.trackCount ?? 0)

        case .song:
            // Everything in the search pool comes from the library index, so a
            // catalog row can't appear here — and a song outside the library
            // couldn't be played by persistent ID anyway.
            guard top.source == .library else {
                throw HeadlessCommandError.notInLibrary(top.title)
            }
            try await executor.execute(.play(query: top.title), selected: top)
            return .played(top)
        }
    }
}

public extension PlaybackFeedback {
    /// The toast for a headless outcome — the same copy the palette shows.
    static func toast(for outcome: HeadlessOutcome) -> Toast {
        switch outcome {
        case .played(let candidate):
            return playing(candidate)
        case .playedAlbum(let album, let trackCount):
            return playingAlbum(album, trackCount: trackCount)
        case .playedPlaylist(let playlist, let trackCount):
            return playingPlaylist(playlist, trackCount: trackCount)
        case .transport(let command, let shuffleBefore):
            return toast(for: command, shuffleBefore: shuffleBefore, selected: nil)
        case .rebuiltLibraryIndex(let summary):
            return indexRebuilt(summary)
        }
    }

    /// Toast copy for a completed transport command.
    ///
    /// - Parameters:
    ///   - shuffleBefore: the shuffle value read *before* a toggle, when known.
    ///   - selected: the row the command ran against, for the "Playing …" line.
    static func toast(
        for command: Command,
        shuffleBefore: Bool?,
        selected: MusicCandidate?
    ) -> Toast {
        switch command {
        case .play(let term):
            if !term.isEmpty, let selected { return playing(selected) }
            return resumed()
        case .pause:
            return paused()
        case .resume:
            return resumed()
        case .next:
            return nextTrack()
        case .previous:
            return previousTrack()
        case .shuffle(let action):
            switch action {
            case .on: return shuffle(true)
            case .off: return shuffle(false)
            case .toggle:
                if let shuffleBefore { return shuffle(!shuffleBefore) }
                return shuffleToggled()
            }
        case .setRepeat(let mode):
            return repeatMode(mode)
        }
    }
}
