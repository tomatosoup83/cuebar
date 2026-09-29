# Plan 13 — Browse albums/playlists in scope mode

Status: **implemented.** Companions: plan.md … plan12.md.

Implemented in this iteration:

- **`LibraryBrowse`** (Core, pure): shuffle a kind's pool and cap it; seedable
  RNG for tests.
- `MusicSearchProviding.browse` (default `[]`) + `LibrarySearchProvider.browse`;
  `SearchService.browse(_:)` publishes the shuffled rows.
- `PaletteModel`: an empty scope now browses (`browsePreference` guard so the
  keyword-strip double-trigger doesn't re-roll), hides the now-playing row, and
  resets selection. Footer shows "Random albums/playlists · type to filter".
- Tests: **152** passing (was 144). Verified with an offscreen snapshot.

---

## Goal

When a scope is active in the search box (`album ` / `playlist `) and **nothing
is typed after it**, show a browsable list of **albums** or **playlists** —
randomly ordered, so the empty scope is useful for discovery instead of showing
"No matches". Typing then filters as it does today.

## Behaviour

- **Trigger:** `scope == .albums` or `.playlists` **and** the term is empty.
- **Contents:** that kind only (albums, or playlists), drawn from the library
  index, **shuffled** and capped at the result limit (40).
- **Re-shuffle** when the user (re)enters the empty-scope state; while the list
  is on screen and untouched, it stays put (no flicker/re-roll on unrelated
  re-renders).
- **Typing** switches to the normal ranked search within the scope (existing
  behaviour); clearing the scope (`⌫`/Esc/chip) returns to plain search.
- **Indexing / empty library:** keep the current "Indexing library…" footer and
  the "No matches" empty state until there is something to browse.

## Implementation

### Core (testable)

- New **`LibraryBrowse`** — a pure helper:
  ```swift
  public enum LibraryBrowse {
      public static func items(
          albums: [MusicCandidate],
          playlists: [MusicCandidate],
          preference: RankPreference,          // .albums / .playlists
          limit: Int,
          using generator: inout some RandomNumberGenerator
      ) -> [MusicCandidate]
  }
  ```
  Picks the pool for the preference, shuffles, and truncates. Seedable RNG keeps
  the test deterministic.

### Provider / service

- `MusicSearchProviding` gains `browse(_ preference:limit:) async -> [MusicCandidate]`
  with a **default implementation returning `[]`** (so `ITunesCatalogProvider`
  and test doubles are unaffected).
- `LibrarySearchProvider.browse` builds the pool (`albumIndex.albums` or the
  `playlists` array) and calls `LibraryBrowse` with a `SystemRandomNumberGenerator`.
- `SearchService.browse(_ preference:)` — cancels any in-flight search, clears
  `currentQuery`/status, and publishes the shuffled rows through the existing
  `results` (so `PaletteModel`'s sink keeps working unchanged).

### Palette model

- `PaletteModel.queryChanged()`:
  ```
  if let term …, !term.isEmpty        -> searchService.updateQuery(…)
  else if let scope, scope != .songs  -> searchService.browse(scope)
  else                                -> searchService.clear(); music = []
  ```
- **Guard against double-trigger:** keep a small `lastBrowse: RankPreference?`;
  only re-browse when entering the empty state (we currently strip the keyword
  by rewriting `query`, which fires `queryChanged` twice — browsing twice would
  re-roll and flicker). Reset `lastBrowse` whenever the term is non-empty or the
  scope changes.
- Reset `selectedIndex` to `0` when the browse list first appears.
- **Hide the now-playing row while browsing:** `rebuildItems()` passes
  `nowPlaying: nil` to `PaletteListComposer.compose` when the browse list is
  active (the composer shows the now-playing row whenever the query is empty,
  which it is in browse mode).

### UI

- Rows are already badged **Album** / **Playlist** and show artwork, so no row
  changes are needed.
- Footer hint while browsing: *"Random albums · type to filter"* (mirrors the
  existing "Searching for … · albums first").

## Files

- **New** `Sources/CuebarCore/LibraryBrowse.swift`
- **New** `Tests/CuebarCoreTests/LibraryBrowseTests.swift`
- `Sources/CuebarCore/SearchProviders.swift` — protocol default + `browse`
- `Sources/CuebarCore/SearchService.swift` — `browse(_:)`
- `Sources/Cuebar/PaletteModel.swift` — empty-scope branch + `lastBrowse` guard
- `Sources/Cuebar/PaletteView.swift` — browse footer hint
- `README.md` / `README.dev.md`

## Tests

- `LibraryBrowse`: returns only the requested kind; respects `limit`; deterministic
  for a seeded generator; empty pool → empty.
- `LibrarySearchProvider.browse`: albums vs playlists; caps to `limit`.
- `SearchService.browse`: publishes results and clears any prior query state.
- Existing 144 tests stay green.

## Manual checks

- `album ` → a shuffled wall of albums; `playlist ` → playlists.
- Typing (`album after`) filters; deleting back to empty re-shuffles.
- `⌫`/Esc clears the scope back to normal search.

## Decisions locked with the user

1. **Random** — shuffle on each entry into the empty scope.
2. **Hide the now-playing row** while a scope is active (albums/playlists only).
3. **Cap at 40** (the result limit).
4. **Re-shuffle on each entry** (type then clear → new list).

## Out of scope

- Grouping/filtering the browse list (genre, decade, artist).
- Infinite scrolling beyond the cap.
- Browsing songs/artists the same way (could follow later).
