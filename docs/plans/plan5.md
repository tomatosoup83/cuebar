# Plan 5 — Catalog playback must never guess a same-title library track

Status: **implemented.** Companions: `plan.md` (MVP), `plan2.md` (rounded
corners + commands), `plan3.md` (now playing), `plan4.md` (catalog → library
resolution).

Implemented in this iteration:

- `LibraryResolver` no longer falls back to a unique same-title library song
  when the catalog artist is known and disagrees; it returns nil instead.
- A known catalog artist that disagrees is decisive; a fuzzy title match
  (`nearMatch`) now also requires an agreeing, non-empty artist.
- Only catalog **songs** resolve; a catalog album/artist never maps onto a
  same-named library song.
- `artistMatches` now compares whole tokens (`the beatles` ≈ `beatles`, but
  `muse` ≠ `museum`).
- Tests: **80** passing (was 74); verified against the real library index +
  live iTunes catalog — every wrong-artist mapping now resolves to nil while
  genuine title+artist matches still resolve.

---

## Problem

Selecting a row that is tagged **Catalog** sometimes plays a completely
different song than the one shown. Cuebar maps the catalog item onto a library
track ("catalog results that also exist in your library are played from the
library"), but the mapping is wrong.

## Root cause — the "single copy" guess in `LibraryResolver`

`Sources/CuebarCore/LibraryResolver.swift` resolves by **title only** and, when
the catalog artist does not match, falls back to returning the *one* library
song with that title:

```swift
let sameTitle = library.filter { $0.kind == .song && $0.normalizedTitle == title }
if !sameTitle.isEmpty {
    if !artist.isEmpty {
        if let exact = sameTitle.first(where: { $0.normalizedArtist == artist }) { return exact }
        if let loose = sameTitle.first(where: { artistMatches(artist, $0.normalizedArtist) }) { return loose }
        // Same title, different artist: only safe if there's one copy.
        return sameTitle.count == 1 ? sameTitle[0] : nil   // <-- the bug
    }
    ...
}
```

A unique title in *your* library says nothing about the catalog item's artist.
If your library contains **one** song whose title happens to match the catalog
song and by a different artist (a cover, remix, interpolations, a same-named
track), the resolver returns it and `MusicController.play` plays it by its
persistent ID. The result is exactly the reported symptom: you asked for the
catalog track, and a different library track starts.

`LibraryResolver` also ignores `kind`, so a **catalog album** can resolve to a
library **song** with the same name.

### Reproduced against the real library + live iTunes catalog

Built a scratch harness (all `Sources/CuebarCore` files + a `main.swift`) that
loads the real `~/Library/Application Support/Cuebar/library-index.json`, runs
`Ranking.hasStrongMatch` / `ITunesCatalogProvider` exactly like `SearchService`,
then calls `LibraryResolver.resolve` for each returned catalog row. Every
mismatch below had exactly **one** library song with that title, i.e. the
`sameTitle.count == 1` fallback fired:

| Query | Catalog row | Played instead (library) |
|---|---|---|
| `the beatles` | Yesterday — The Beatles | **Yesterday — goddard.** (`3D319333D5078091`) |
| `the beatles` | Michelle — The Beatles | **Michelle — The Singers Unlimited** |
| `michael jackson` | Chicago — Michael Jackson | **Chicago — Cookin Soul** |
| `pink floyd` | Mother — Pink Floyd | **Mother — Tyler, The Creator** |
| `frank sinatra` | That's Life — Frank Sinatra | **That's Life — Still Woozy** |
| `green day` | She — Green Day | **She — dodie** |
| `arctic monkeys` | I Want It All — Arctic Monkeys | **I Want It All — Metro Boomin, …** |
| `adele` | album 25 — Adele | **song 25 — Rod Wave** (kind ignored) |
| `radiohead` | album The Bends — Radiohead | **song The Bends — Earl Sweatshirt** (kind ignored) |

Note the trigger: the catalog is only queried when the library has **no strong
match** for what you typed, so these are reached by typing an artist name or a
slightly-off title — not by typing the exact song title.

`Ranking`/`SearchService` are not at fault; the wrong pick happens entirely in
`LibraryResolver`.

---

## Fix

Make the resolver genuinely conservative: **never** return a library track
whose artist disagrees with a known catalog artist, regardless of how many
copies of the title exist.

### `Sources/CuebarCore/LibraryResolver.swift`

1. **Drop the single-copy, wrong-artist fallback.** In the exact-title branch,
   when `artist` is non-empty:
   - return the exact-artist match, else
   - return the loose-artist match, else
   - return **nil** (do not fall back to the single copy).
   Keep returning the single copy only when the catalog **artist is empty**
   (nothing to disambiguate against); if the artist is empty and several copies
   exist, return nil.
2. **Kind-gate the resolution.** Only a catalog `.song` may resolve. A catalog
   `.album` (or `.artist`) returns nil, so an album row can never play a
   same-named song.
3. **Tighten `artistMatches`** to whole-token agreement so a short name can't
   substring-match an unrelated longer one (`muse` vs `museum`) while still
   matching real variants (`the beatles` ≈ `beatles`, `the weeknd` ≈ `weeknd`).
   Exact equality always matches.
4. **`nearMatch` requires agreement too.** Don't accept a fuzzy title match when
   the catalog artist is empty; require a non-empty, matching artist (as the
   exact-title branch does).

### `Sources/Cuebar/PaletteModel.swift` (small, optional)

`playableTrack(for:)` is fine. Only consider a clearer status message for the
catalog **album/artist** case ("Cuebar can play songs, not albums") instead of
reusing the "isn't in your Music library" wording. Can be deferred.

---

## Files

- `Sources/CuebarCore/LibraryResolver.swift` — main change (items 1–4).
- `Sources/Cuebar/PaletteModel.swift` — optional album/artist message.
- `Tests/CuebarCoreTests/LibraryResolverTests.swift` — update + add cases.
- `README.md` / `README.dev.md` — the "played from the library" wording stays
  accurate; add that a catalog-only song is *never* matched to a same-title
  track by a different artist.

## Tests

Change:

- `testSingleTitleWithUnknownArtistResolves` currently asserts the buggy
  behavior (one copy, different artist → resolves). Rewrite it to assert **nil**,
  e.g. `testSingleTitleWithDifferentKnownArtistDoesNotResolve`.

Add:

- Same title, exactly one library copy, artist disagrees → nil (the exact
  regression above).
- Real-data regression pair: catalog *Yesterday — The Beatles* vs library
  *Yesterday — goddard.* → nil.
- Catalog **album** whose title matches a library song → nil (kind gate).
- `artistMatches`: `muse` vs `museum` → no match; `the beatles` vs `beatles` →
  match; exact equality → match.
- `nearMatch` with an empty catalog artist → nil.

Keep green (no behavior change intended):

- `testExactTitleAndArtistResolves`, `testPrefersMatchingArtistAmongSameTitle`,
  `testAmbiguousTitleWithDifferentArtistDoesNotGuess`,
  `testNearTitleWithMatchingArtistResolves`, `testUnrelatedSongDoesNotResolve`,
  `testLibraryCandidatePassesThrough`, `testCaseAndDiacriticsAreIgnored`,
  `testArtistNameVariantsMatch`.

## Verification

1. `make test` — the full suite passes.
2. Re-run the scratch harness (real `library-index.json` + live catalog) over
   the queries in the table above: every catalog row that is not a genuine
   exact-title/artist library match must now resolve to **nil**, so Cuebar shows
   the "isn't in your Music library" message and leaves playback untouched.
3. Manual: type `the beatles`, arrow to *Yesterday — The Beatles* (Catalog),
   press Return → Cuebar reports it isn't in the library and the current track
   keeps playing, instead of switching to goddard.'s *Yesterday*.

## Out of scope

- Real Apple Music catalog playback (no supported macOS API without a MusicKit
  entitlement) — unchanged.
- Fuzzy-resolving catalog rows to a library copy is still supported, but only
  with a matching artist.
