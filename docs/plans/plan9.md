# Plan 9 — Playlist search + search-scope indicator

Status: **implemented.** Companions: `plan.md` (MVP), `plan2.md` (rounded
corners + commands), `plan3.md` (now playing), `plan4.md` (catalog → library),
`plan5.md` (never play the wrong track), `plan6.md` (album playback),
`plan7.md` (feedback toasts), `plan8.md` (repeat).

Implemented in this iteration:

- **Playlist search:** `LibraryIndex` v3 + `fetchPlaylists` (one Apple Event,
  `special kind = none`, excludes `Cuebar Queue` and empties), `MusicKind.playlist`,
  `RankPreference` (replacing `preferAlbums`), `MusicController.playPlaylist`
  (plays by persistent ID, shuffle untouched) and `SearchQuery` now handling
  `album`/`playlist` on either end.
- **Scope chip:** `PaletteModel.scope` + keyword stripping, `SearchScopeChip`, and
  ⌫/Esc/click to clear.
- Tests: **136** passing (was 125). Playlist enumeration validated against the
  real library (52 playlists; system `Music` excluded).

---

## Part 1 — Search library playlists

Goal: search the user's library **playlists** the way albums work now.
`playlist <name>` and `<name> playlist` prioritise playlists; plain text stays
as-is.

### Feasibility (verified)

- `user playlist` inherits `item`, so it has a **`persistent ID`** — playlists
  can be identified unambiguously (important: your library has **two playlists
  named "Logic"**).
- `play (first user playlist whose persistent ID is "…")` **compiles** against
  Music's dictionary (`osacompile`) — so we play a playlist directly, with no
  temporary queue playlist (unlike albums).
- Bulk `count of tracks` / `first track` per playlist fail (`-1728`), but a
  single in-script `repeat` loop works (one Apple Event for all playlists).
- `special kind of every user playlist` distinguishes the system **`Music`**
  playlist (kind `Music`) from real user playlists (kind `none`) → filter on
  `special kind is none`.
- **Must exclude the app's own `Cuebar Queue`** (album playback creates it) from
  playlist search, by name/persistent ID.

### Index

- `LibraryIndex` **v2 → v3**: add `playlists: [MusicCandidate]` (forces the
  usual one-time re-index).
- `AppleScriptLibraryProvider.fetchPlaylists()` — one script that loops user
  playlists and returns, per playlist: name, persistent ID, track count, and the
  first track's persistent ID (for artwork). Filters out `special kind ≠ none`,
  `Cuebar Queue`, and empty playlists.
- `AppDelegate.refreshLibraryIndex` fetches tracks **and** playlists and saves
  both.

### Model

- `MusicKind` gains **`.playlist`**.
- Playlist candidate: `kind: .playlist`, `source: .library`,
  `id: "library:playlist:<persistentID>"`, `title` = name,
  `persistentID` = the playlist's persistent ID, `trackCount` = N,
  `artworkTrackID` = first track (or nil).
- `MusicCandidate.subtitle`: also append "N tracks" for `.playlist`.
- `LibraryResolver` is unchanged (`guard kind == .song` already means playlists
  never resolve from catalog).

### Ranking

Replace `Ranking`'s `preferAlbums: Bool` with a general

```swift
public enum RankPreference: Equatable, Sendable { case songs, albums, playlists }
```

`kindBonus`/`kindRank` become preference-driven:

- `.songs` (default): song > album > playlist > artist
- `.albums`: album > song > playlist > artist
- `.playlists`: playlist > song > album > artist

`artist` stays last; source (library before catalog) and base scoring unchanged.

### Query parsing

Generalise `SearchQuery`:

- keywords: `album` → `.albums`; `playlist` / `playlists` → `.playlists`.
- a **leading or trailing** keyword is detected only when it is **followed/
  preceded by whitespace** (so typing `album`/`playlist` alone stays a literal
  search; pressing space activates the scope — see Part 2). Trailing wins if
  both appear.
- returns `term` (may be **empty**, for the indicator) + `preference`.
- `SearchService` only searches when `term` is non-empty; empty `term` clears
  results but the chip stays.

### Playback

- `MusicController.playPlaylist(_ candidate:)`:
  `play (first user playlist whose persistent ID is "<id>")`.
- `CommandExecutor.executePlaylist(_:)`.
- `PaletteModel.executeSelection`: `kind == .playlist && source == .library` →
  play via the above; success toast `Playing playlist “X” — N tracks`.
- **Shuffle:** leave as-is for playlists (unlike albums, where we turn it off).
  Playlists are often meant to be shuffled — open to changing this.

### Artwork

- The index stores each playlist's **first track id**; `ResultRowView` reuses
  the existing `.library(persistentID:)` artwork path with it (no new
  `ArtworkSource` case) and shows a **"Playlist"** badge, falling back to the
  placeholder glyph when there's no track.

---

## Part 2 — Search-scope indicator in the box

When `album`/`playlist` is typed **plus a space**, show a chip in the search
field: `[ Album › ]` / `[ Playlist › ]`, matching the result badges.

### Recommended behaviour (strip into a scope token)

- A new `SearchScope` (`album` / `playlist` with label, SF Symbol, keyword).
- `PaletteModel` gains `@Published var searchText` and
  `@Published private(set) var scope: SearchScope?`.
- The `TextField` binds to `searchText`; `onChange` detects a keyword, moves it
  into `scope`, and rewrites `searchText` to the remainder. The field then shows
  **only the name**, with the chip at the leading edge — no duplicated word.
- Effective query for search = `scope` preference + `searchText` term.
- Clearing: **⌫ on an empty field** and **Esc** (Esc clears scope first, then
  closes) remove the scope; the chip also has a click target. Re-typing the
  keyword restores it.
- Placeholder and the footer hint adapt ("Playlist name…", "Searching for “x” ·
  playlists first").

### Visual

Chip after the magnifier: capsule, `quaternary` background, secondary text, a
leading SF Symbol (`rectangle.stack` for album, `music.note.list` for playlist)
and a trailing `chevron.right` — deliberately the same language as
`ResultRowView`'s badges so the scope reads as "this is a filter".

_Fallback if rewriting the field proves janky:_ keep the text as typed and show
the chip without stripping (duplicates the keyword) — noted in case, not
preferred.

---

## Files

**Core**
- `Sources/CuebarCore/MusicCandidate.swift` — `MusicKind.playlist`, subtitle
- `Sources/CuebarCore/LibraryIndex.swift` — v3 + `playlists`
- `Sources/CuebarCore/AppleScriptLibraryProvider.swift` — `fetchPlaylists`
- `Sources/CuebarCore/SearchProviders.swift` — playlists in the library pool
- `Sources/CuebarCore/SearchService.swift` — `RankPreference`
- `Sources/CuebarCore/SearchQuery.swift` — keyword set + empty-term scope
- `Sources/CuebarCore/Ranking.swift` — `RankPreference`
- `Sources/CuebarCore/MusicController.swift` — `playPlaylist`
- `Sources/CuebarCore/CommandExecutor.swift` — `executePlaylist`
- `Sources/CuebarCore/PlaybackFeedback.swift` — playlist toast
- `Sources/CuebarCore/ArtworkStore.swift` — `.playlist` source
- `Sources/CuebarCore/AppleScriptArtworkProvider.swift` — playlist artwork
- `Sources/Cuebar/AppDelegate.swift` — fetch + store playlists

**Shell**
- `Sources/Cuebar/PaletteModel.swift` — `searchText`/`scope`, playlist branch
- `Sources/Cuebar/PaletteView.swift` — scope chip, placeholder/footer
- `Sources/Cuebar/ResultRowView.swift` — Playlist badge + art
- **New** `Sources/Cuebar/SearchScopeChip.swift`

**Tests**
- `Tests/CuebarCoreTests/AppleScriptLibraryProviderTests.swift` — playlist parse
- `Tests/CuebarCoreTests/SearchQueryTests.swift` — playlist keyword, empty term,
  keyword-without-space stays literal
- `Tests/CuebarCoreTests/RankingTests.swift` — playlist preference ordering
- `Tests/CuebarCoreTests/CommandExecutorTests.swift` — `playPlaylist`
- `Tests/CuebarCoreTests/ToastTests.swift` — playlist copy
- `Tests/CuebarCoreTests/Mocks.swift` — `playPlaylist`

**Docs**: `README.md`, `README.dev.md`.

## Verification

1. `make test` green; existing 125 tests plus the new ones.
2. `osacompile` the playlist-by-id play script (already done) and the artwork
   script.
3. Live enumeration probe: fetch playlists, confirm `Cuebar Queue` and the
   system `Music` playlist are excluded and counts look right.
4. Manual: `playlist focus`, `focus playlist`, `album …`, plain search, and the
   chip appearing/clearing with space/⌫/Esc.

## Decisions locked with the user

1. **Prioritise, not filter.** `album`/`playlist` sorts that kind to the top but
   other kinds still appear below — consistent with `album` today. (No strict
   "only this kind" mode.)
2. **Scope chip strips the keyword.** The keyword moves into the chip and the
   field shows just the name; ⌫ on an empty field, Esc, or clicking the chip
   clears the scope. (The non-stripping fallback is not used.)
3. **Playlist shuffle: leave as-is.** Playing a playlist does not change
   Music's shuffle setting (unlike album playback).

## Out of scope

- Creating/editing playlists, or playing a playlist from the catalog.
- Per-playlist track ordering/queue editing.
- Showing playlists on the empty state (browse-all).
