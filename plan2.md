# Cuebar — Plan 2: Fully Rounded Panel + Commands in Results

Status: **implemented.** Companion to `plan.md` (which covers the original MVP
build).

Implemented in this iteration:
- Rounded window: hosting view wrapped in a layer-rounded container
  (`PaletteMetrics.cornerRadius`), matching SwiftUI `.clipShape`, and
  `invalidateShadow()`; `.fullSizeContentView` removed from the panel.
- Commands as results: `CommandCatalog` + `PaletteItem`, command matches above
  songs, all commands listed when the box is empty, Return runs the selected row.
- Tests: 36 passing (9 new command-catalog tests + composition test).
- Pending: on-screen confirmation that all four corners are fully rounded
  (offscreen snapshots cannot capture the window silhouette).

---

## Scope

Two changes to the existing app:

- **A. Fully rounded window.** Remove the square window silhouette that is
  visible at the panel corners (clearly at the bottom; faintly but visibly at
  the top-left and top-right too, as a more transparent square border).
- **B. Commands as results.** `pause`, `resume`, `next`, `previous`, `shuffle`
  (and variants) must appear as selectable rows in the results box, including
  when the search box is empty. Non-song commands therefore still show up.

Decisions locked with the user:

- Empty search box → the results box lists **all** commands.
- Command matches are listed **above** song results.
- The three command-input shortcuts remain: `play take on me` is a song search,
  `play` alone resumes, bare text is an implicit play.

---

## A. Fully rounded window

### Diagnosis (decoded pixel-by-pixel from `corner radius.png`)

The screenshot is 1336×858 px = the 660×420 pt panel at 2× scale plus a ~4 pt
shadow margin.

- **Top-left / top-right:** the glass curves inward over ~48 px → a correct
  ~24 pt rounded corner. **However**, a faint square edge/border is visible
  beyond the curve — the square window silhouette, rendered more transparently.
- **Bottom-left / bottom-right:** the panel edge runs **straight down to the
  bottom** with no curve → the square window edge is clearly visible and
  transparent.

**Root cause:** a borderless `NSPanel` is a *square* window. `.glassEffect`
rounds the SwiftUI shape drawn inside it, but nothing rounds the window's own
content/shadow silhouette. The square window edge (and the shadow computed from
it) therefore shows through at every corner; it is most visible at the bottom and
fainter/more transparent at the top.

### Fix — remove the square silhouette on all four corners

1. **`Sources/Cuebar/PalettePanel.swift`**
   - Remove `.fullSizeContentView` from the style mask. It is intended for
     titled windows and is unnecessary here; it can skew content-vs-frame
     geometry. Keep `.borderless` and `.nonactivatingPanel`.
   - Keep `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = true`.

2. **`Sources/Cuebar/PaletteWindowController.swift`**
   - Wrap the `NSHostingView` in a plain container `NSView` and pin the hosting
     view to the container's four edges (Auto Layout constraints).
   - Round the container's layer so the **window content itself** is rounded:
     ```swift
     container.wantsLayer = true
     container.layer?.cornerRadius = PaletteMetrics.cornerRadius
     container.layer?.cornerCurve = .continuous
     container.layer?.masksToBounds = true
     panel.contentView = container
     ```
   - After `show()` (and after any resize), call `panel.invalidateShadow()` so
     the window shadow is recomputed from the rounded opaque shape rather than
     the square window frame.
   - **Fallback only if a faint square edge persists** (documented, not applied
     by default because it touches AppKit internals): also round the window's
     frame view (`panel.contentView?.superview`), or set `hasShadow = false` and
     draw an `NSShadow` under the rounded container.

3. **`Sources/Cuebar/PaletteView.swift`**
   - Add a matching clip immediately after the glass so the glass and the
     container share one curve:
     ```swift
     .glassEffect(.regular, in: .rect(cornerRadius: PaletteMetrics.cornerRadius,
                                      style: .continuous))
     .clipShape(RoundedRectangle(cornerRadius: PaletteMetrics.cornerRadius,
                                 style: .continuous))
     ```
   - Ensure the root draws no opaque background outside that shape.

4. **Single source of truth for the radius.** Add
   `PaletteMetrics.cornerRadius = 24` and use it from both the AppKit container
   and the SwiftUI view so the two can never drift.

### Why this removes the top square border too

The faint top corners come from the same square window silhouette, not from the
glass. Masking the window's content to a 24 pt continuous rounded rect removes
the square silhouette on **all four** corners, and invalidating the shadow makes
the shadow follow the same curve.

---

## B. Commands as results

### Command catalog (new, in `CuebarCore`)

| Title | Subtitle | Symbol | `Command` | Keywords |
|---|---|---|---|---|
| Pause | Pause playback | `pause.fill` | `.pause` | `pause` |
| Resume | Resume playback | `play.fill` | `.resume` | `resume`, `play` |
| Next Track | Skip to next track | `forward.fill` | `.next` | `next`, `skip`, `forward` |
| Previous Track | Previous track | `backward.fill` | `.previous` | `previous`, `prev`, `back` |
| Toggle Shuffle | Turn shuffle on or off | `shuffle` | `.shuffle(.toggle)` | `shuffle` |
| Shuffle On | Enable shuffle | `shuffle` | `.shuffle(.on)` | `shuffle on` |
| Shuffle Off | Disable shuffle | `shuffle` | `.shuffle(.off)` | `shuffle off` |

### Matching rules

Normalize the input (existing `TextNormalizer`), then score each keyword:

- keyword **equals** input → 1000
- keyword **has the input as a prefix** → 850 (input non-empty)
- **fuzzy** (single-token input, Damerau–Levenshtein similarity ≥ 0.60) →
  `ratio × 500`

Take the best score per entry, sort descending then by title. Because the match
is directional (input must be a prefix *of* the keyword), `play take on me` does
**not** match the `play` keyword and stays a clean song search, while:

- `pau` → Pause
- `nex` → Next Track
- `shuffle o` → Shuffle On
- `pase` → Pause (fuzzy)

### Composition and execution

- New `PaletteItem` enum: `.command(CommandEntry)` / `.music(MusicCandidate)`,
  with a stable `id` for list identity and selection.
- Command matches are listed **first**, then the existing ranked song results.
  `Ranking`, `SearchService`, `LibrarySearchProvider` and `ITunesCatalogProvider`
  are unchanged.
- Empty input → all commands listed (replaces the static hint text). Songs fill
  in as the user types.
- `PaletteModel.executeSelection()` acts on the **selected item**, not a re-parse
  of the query (this also fixes the current case where typing `pau` + Return
  falls through to a song search):
  - selected `.command(entry)` → `executor.execute(entry.command, selected: nil)`
  - selected `.music(candidate)` → `executor.execute(.play(query: candidate.title),
    selected: candidate)`

### UI

- `ResultRowView` generalized to render both item kinds:
  - command → SF Symbol tile + **Command** badge
  - song → artwork + **Library**/**Catalog** badge
- Selection highlight and the `↑`/`↓`/`Return`/`Esc` handling are unchanged.

---

## Files to change

- `Sources/Cuebar/PaletteWindowController.swift` — rounded container view, pins, `invalidateShadow()`
- `Sources/Cuebar/PalettePanel.swift` — drop `.fullSizeContentView`
- `Sources/Cuebar/PaletteView.swift` — clip shape, render `PaletteItem`, command rows, empty state
- `Sources/Cuebar/PaletteModel.swift` — `[PaletteItem]`, selection, execute-selected
- `Sources/Cuebar/ResultRowView.swift` — both item kinds
- **New** `Sources/Cuebar/Support/PaletteMetrics.swift` — shared corner radius
- **New** `Sources/CuebarCore/CommandCatalog.swift` — entries + matching
- **New** `Sources/CuebarCore/PaletteItem.swift` — item enum
- **New** `Tests/CuebarCoreTests/CommandCatalogTests.swift` — matching tests

---

## Tests and verification

### Automated
- New `CommandCatalogTests`: `pau` → Pause; `nex` → Next Track; `shuffle o` →
  Shuffle On; `shuffle` → Toggle Shuffle first; fuzzy `pase` → Pause;
  `play take on me` → **no** command match; empty input → all entries.
- New composition test: command matches precede song results.
- All 27 existing tests must remain green (`swift test`).

### Manual / visual
- `swift build` warning-free.
- DEBUG snapshot with `CUEBAR_PREVIEW_QUERY="pause"` and with an empty query to
  confirm command rows render and are selectable.
- **Corners:** offscreen snapshots cannot capture the window silhouette, and the
  terminal lacks Screen Recording permission, so a **fresh on-screen screenshot
  from the user is required** to confirm all four corners are fully rounded.
  Add a DEBUG log of `panel.frame`, `contentRect(forFrameRect:)` and
  `hostingView.frame` to rule out a size mismatch if it persists.
- Manual smoke: `pause` / `resume` / `next` / `previous` / `shuffle` still act on
  the real Music app; `play <song>` still plays the selected song.

---

## Risks / notes

- Rounding the window frame view is a fallback only; it reaches into AppKit
  internals and is avoided unless the container mask alone proves insufficient.
- Liquid Glass may render differently when the app is inactive; the container
  mask guarantees the silhouette is rounded regardless of glass behaviour.
- No changes to the playback engine, ranking, or search providers.
