# Plan 6 — Search and play library albums start to finish

Status: **implemented.** Companions: `plan.md` (MVP), `plan2.md` (rounded
corners + commands), `plan3.md` (now playing), `plan4.md` (catalog → library),
`plan5.md` (never play the wrong track).

Implemented in this iteration:

- Library index **v2** fetches `album artist`, `disc number`, `track number` in
  the same bulk Apple Event.
- **`LibraryAlbumIndex`** groups songs into playable albums (album + album
  artist, disc/track order); `LibrarySearchProvider` ranks songs + albums.
- **`MusicController.playAlbum`** loads a reusable **Cuebar Queue** playlist in
  album order with shuffle off and plays it. `PaletteModel` plays a selected
  library album start to finish.
- **`SearchQuery`** + `Ranking(preferAlbums:)`: `take on me` keeps the song
  first, `take on me album` prioritises the album. The keyword never reaches the
  catalog request, and the "strong match" catalog-fallback check is songs-only.
- Tests: **107** passing (was 80). The album AppleScript compiles against
  Music's dictionary (`osacompile`), verified without executing it.
- Decisions: shuffle off for album playback; one persistent `Cuebar Queue`
  playlist, reused.

---

## Is it possible?

**Yes.** Music.app's scripting dictionary (`/System/Applications/Music.app/
Contents/Resources/com.apple.Music.sdef`) has **no album object** — albums are
only track metadata. So an album is not something we can hand to AppleScript
directly; we synthesize it from its library tracks and play them as a queue.

Confirmed from the dictionary:

- **Classes:** `… track, library playlist, user playlist, folder playlist …` —
  **no `album` class.**
- **Track properties:** `album`, `album artist`, `disc number`, `track number`,
  `track count`, `disc count` — everything needed to group and order an album.
- **`play`**: `direct-parameter type="specifier"` (*"item to play"*). A
  `playlist` inherits `item`, so a user playlist is a valid thing to play.
- **`make`** (`new user playlist`), **`duplicate … to <playlist>`**,
  **`delete every track of <playlist>`** available. Note `add` takes *files*
  only, so it can't add existing library tracks — `duplicate` is the tool.
- There is **no queue / "play next" command**, so we can't push an album onto
  the current queue directly.

### The approach

Play the album through a dedicated, reusable **user playlist**:

1. Ensure a playlist named **`Cuebar Queue`** exists (`make new user playlist`).
2. Clear it (`delete every track of` it) — this only removes playlist entries,
   never the underlying library files.
3. `duplicate` the album's tracks into it **in album order** (disc, track no.),
   one lookup per persistent ID.
4. `play` the playlist.

Because Music's play queue becomes that playlist, playback runs start to finish
and `next`/`previous` follow album order. This drives the real Music app and
survives Cuebar quitting — same guarantees as today's single-track playback.

---

## What we need to add

### 1. Fetch album metadata while indexing

`AppleScriptLibraryProvider.enumerationScript` currently joins 5 property lists
(names, artists, albums, ids, durations). Add three more bulk lists in the same
single Apple Event: **album artist**, **disc number**, **track number**.
`parse(_:)` reads three more sections (tolerating missing trailing sections).

### 2. Group tracks into albums

New **`Sources/CuebarCore/LibraryAlbumIndex.swift`** (pure, testable). Given the
library songs it produces:

- **Group key:** `normalizedAlbum + "|" + normalized(albumArtist, else artist)`
  so compilations ("Various Artists") stay one album.
- **Album row:** a `MusicCandidate` with `kind == .album`, `source == .library`,
  deterministic `id` (`library:album:<sha256(key) prefix>`), `title` = album,
  `artist` = album artist, `trackCount`, summed `durationSeconds`, and a
  representative track id for artwork.
- **Ordering:** sort each album's tracks by `(discNumber ?? 1, trackNumber ?? 0,
  title)`.
- Skip songs whose normalized album is empty (can't name/play an album).
- Expose `albums: [MusicCandidate]` and `tracks(forAlbumID:) -> [MusicCandidate]?`.

### 3. Model fields (`MusicCandidate`)

Add optional, defaulted fields (Swift's synthesized `Codable` decodes missing
optional keys as `nil`, so this is backward compatible):

- `albumArtist: String?`
- `discNumber: Int?`
- `trackNumber: Int?`
- `trackCount: Int?`
- `artworkTrackID: String?` (album rows: which track to pull album art from)

`AppleScriptLibraryProvider.parse` fills the first three for songs; the album
index fills the rest.

### 4. Surface albums in search

`LibrarySearchProvider`:

- `setIndex` builds a `LibraryAlbumIndex`.
- `search` ranks **songs + albums** together (existing `Ranking` already ranks
  `.album` below `.song`, and library higher than catalog — the exact-song
  rule is already unit-tested).
- `snapshot()` stays **songs only**, so `LibraryResolver` (plan5) is unchanged
  and catalog albums still don't resolve onto a song.
- Add `tracks(forAlbumID:)`.

`SearchService`: keep `Ranking.hasStrongMatch` over **songs only** for the
catalog-fallback decision, so adding albums never suppresses the catalog for a
song query.

### 5. Playback

`MusicController` protocol gains:

```swift
func playAlbum(_ tracks: [MusicCandidate]) async throws
```

`AppleScriptMusicController` implements it with a **pure, testable script
builder** (`albumQueueScript(trackIDs:)`) that emits the
make/clear/duplicate/play steps above with escaped IDs, plus (decision below)
`set shuffle enabled to false` so the album really plays start to finish.

`CommandExecutor` gains `executeAlbum(_ tracks:)`; `PaletteModel.executeSelection`
branches on `candidate.kind == .album && candidate.source == .library`, looks up
the ordered tracks, and plays them (or shows a clear message if the album is
empty). The `Command` enum (transport verbs) is left untouched.

### 6. UI

- `ResultRowView` badge: show **"Album"** for library `.album` rows (still
  "Library"/"Catalog" otherwise); artwork uses
  `candidate.persistentID ?? candidate.artworkTrackID`.
- `MusicCandidate.subtitle`: for albums append `"· N tracks"`.

### 7. Index version

Bump `LibraryIndex.currentVersion` **1 → 2** so the first launch after the
update re-indexes (a few seconds) and populates album artist/disc/track.

---

## Album-first queries (`<name> album`)

Requirement:

- A bare song name — even when it equals an album name — keeps the **song
  first**. (Already true: `Ranking` gives songs `+200` over albums.)
- Only when the input ends with the word **`album`** is the **album**
  prioritised.

### Design

A new pure, testable Core type **`SearchQuery`**
(`Sources/CuebarCore/SearchQuery.swift`):

```swift
public struct SearchQuery: Equatable, Sendable {
    public let term: String        // what to actually search for
    public let prefersAlbums: Bool // "… album" was typed
    public static func parse(_ raw: String) -> SearchQuery
}
```

Parsing rules:

- A trailing (or leading) standalone `album` token — matched after
  normalization, so casing/punctuation don't matter — is stripped and sets
  `prefersAlbums = true`.
- It only strips when at least one other token remains, so typing `album`
  alone still searches the literal word.
- Anything else is returned unchanged (`prefersAlbums = false`).

`Ranking.rank(_:query:preferAlbums:limit:)` gains a `preferAlbums` flag
(default `false`). When true it **inverts the kind ordering only**:

- `kindBonus`: album `+200` / song `0` (instead of song `+200` / album `0`),
- the deterministic kind tie-break puts album before song.

Exact/base scoring, source preference (library before catalog) and artist
bonuses are unchanged, so `take on me album` lists matching **albums first,
then songs**, while `take on me` still lists the **song first**.

`SearchService.updateQuery` parses the raw input **once** and threads it:

- `term` goes to both providers, so the trailing word never reaches the iTunes
  request,
- `prefersAlbums` is passed to every `Ranking.rank` call (library stage and the
  merged library+catalog stage).

`hasStrongMatch` and the catalog-fallback decision stay term-based, so this
never changes *whether* the catalog is consulted. The footer label shows the
parsed `term`.

### Edge case

A song whose title literally ends in "album" (e.g. *The Album*) is affected by
the keyword. Optional safeguard for later: if `prefersAlbums` produces no album
result, retry the literal input. Not included in v1.

| Input | `term` | First result |
|---|---|---|
| `take on me` | `take on me` | song |
| `take on me album` | `take on me` | album |
| `ALBUM take on me` | `take on me` | album |
| `album` | `album` | literal search |

---

## Files

- **New** `Sources/CuebarCore/LibraryAlbumIndex.swift`
- **New** `Sources/CuebarCore/SearchQuery.swift`
- **New** `Tests/CuebarCoreTests/LibraryAlbumIndexTests.swift`
- **New** `Tests/CuebarCoreTests/SearchQueryTests.swift`
- **New** `Tests/CuebarCoreTests/AppleScriptLibraryProviderTests.swift`
- `Sources/CuebarCore/MusicCandidate.swift` — optional album fields + subtitle
- `Sources/CuebarCore/AppleScriptLibraryProvider.swift` — 3 more property lists
- `Sources/CuebarCore/SearchProviders.swift` — albums in `LibrarySearchProvider`
- `Sources/CuebarCore/Ranking.swift` — `preferAlbums` flag
- `Sources/CuebarCore/SearchService.swift` — parse `SearchQuery`, thread
  `prefersAlbums`, strong-match over songs only
- `Sources/CuebarCore/LibraryIndex.swift` — version bump
- `Sources/CuebarCore/MusicController.swift` — `playAlbum` + script builder
- `Sources/CuebarCore/CommandExecutor.swift` — `executeAlbum`
- `Sources/Cuebar/PaletteModel.swift` — album selection branch + footer term
- `Sources/Cuebar/ResultRowView.swift` — album badge + artwork id
- `Tests/CuebarCoreTests/Mocks.swift` — `MockMusicController.playAlbum`
- `README.md` / `README.dev.md` — document album playback and `… album`

## Tests

- `LibraryAlbumIndex`: groups same album/album-artist; keeps compilations
  together; orders by disc then track; excludes empty-album tracks; track count
  and duration; deterministic id; `tracks(forAlbumID:)`.
- `AppleScriptLibraryProvider.parse`: new sections parsed; missing trailing
  sections tolerated; `missing value` → nil ints.
- `LibrarySearchProvider`: returns album rows + songs; `snapshot()` excludes
  albums; `tracks(forAlbumID:)` ordering.
- `Ranking`: library song outranks a same-titled library album by default; the
  same pair with `preferAlbums` reverses (album first); tie-break is
  deterministic.
- `SearchQuery.parse`: trailing and leading `album`, casing/punctuation,
  `album` alone stays literal, multi-word terms, empty input.
- `SearchService`: with a library song + album of the same name, `take on me`
  lists the song first and `take on me album` lists the album first.
- `AppleScriptMusicController.albumQueueScript`: IDs in order, quoted/escaped,
  includes clear + play, includes shuffle-off when enabled.
- `CommandExecutor.executeAlbum` with `MockMusicController`.
- Keep plan5 resolver tests green.
- Validate the raw AppleScript against Music.app on the machine once (create,
  fill, play, inspect, then remove the probe playlist) — like plan4 did.

## Decisions locked with the user

1. **Shuffle: off.** Playing an album disables Music's shuffle so it truly runs
   start to finish. (`set shuffle enabled to false` as part of `playAlbum`.)
2. **Queue playlist: keep and reuse one.** A single clearly-named user playlist
   **`Cuebar Queue`** persists in the Music library and is cleared before each
   album is loaded. No folder, no post-playback deletion (which could stop
   playback).

## Out of scope

- Catalog-only albums stay unplayable (no entitlement) — unchanged.
- Mapping a *catalog* album onto a *library* album (by title + album artist)
  could be a follow-up, but catalog albums are shown with the "not in library"
  message for now.
- Playlist/folder playback (same mechanism could extend to it later).
