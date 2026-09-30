# Plan 16 — Theming (Tahoe / Album Art)

Status: **implemented.** Companions: plan.md … plan15.md.

Implemented in this iteration:

- **Core**: `ThemeID` (Tahoe / Album Art + keywords), `ThemeStore`,
  `ThemeColor` (sRGB value type + saturation/blend), `AlbumPalette`,
  `PaletteExtractor` (pure extraction from a `PixelGrid`, plus a `CGImage` bridge);
  `PaletteAction.setTheme` and a single `PaletteItem.artworkSource` accessor.
- **Shell**: `PaletteCache` (memoised extraction, mirrors `ArtworkStore`),
  `AmbientTheme` (now-playing artwork → ambient wash), `ThemeBackground`
  (the wash drawn behind the glass).
- **UI**: the ambient wash on `PaletteView` and `ToastView`, the selected-row
  accent resolved on selection change, a **Settings → Theme** dropdown, and
  **"Theme: …"** command rows injected when the typed text matches.
- Tests: **197** passing (was 178). Verified by snapshot: the wash renders, the
  Theme dropdown and `theme` rows work, the selected row takes its album's accent,
  and no-music falls back to the neutral/Tahoe look.

> Not yet verified interactively: how strongly the glass reads over the wash in
> the live app (offscreen snapshots don't capture the glass backdrop). The wash
> opacity is a one-line tweak if it needs tuning.

## Goal

Two selectable themes, chosen in Settings:

- **Tahoe** (default) — exactly today's plain Liquid Glass. No gradient.
- **Album Art** — a light, legible gradient derived from the **now-playing track's**
  album art, washing the whole panel behind the glass, **plus** a small local
  accent on the selected row.

Themes are switchable from **Settings** (a dropdown) *and* by typing — a
`theme` command row.

The ambient gradient is keyed to the **now-playing track**, not the selected row.
Per-row ambient tinting was considered and rejected: it would strobe the entire
readable surface on every arrow key, and on the default (command-only) list it
would flicker between colour and neutral for rows that have no art at all.
Selection therefore stays a *local* effect.

## Feasibility & constraints

- **Artwork is already free.** `ArtworkStore` fetches, downscales to 256 px and
  caches per album (`Sources/CuebarCore/ArtworkStore.swift`), and the now-playing
  card already requests `.nowPlaying(...)` art whenever the panel is shown. So the
  tint adds **no new AppleScript calls and no new permissions** — it reuses a
  cached thumbnail.
- **Cold albums are slow.** Library artwork is an AppleScript library scan
  (`AppleScriptArtworkProvider.swift`), tens–hundreds of ms, serialised. The tint
  must be **cache-only to render**, with a fade-in when the palette arrives, and
  must never block or re-fetch per keystroke.
- **The panel is transparent glass.** `PalettePanel` is `isOpaque = false` and
  `PaletteView` applies `.glassEffect(.regular, …)`, so glass currently samples the
  desktop. A wash gives it a deliberate backdrop — a net improvement, not just
  decoration. **Modifier order matters:** the wash must go *behind* the glass.
- **Core stays SwiftUI-free.** Palettes are plain value types in Core; the shell
  maps them to `Color`/`LinearGradient`.
- **Polling is panel-scoped.** `startNowPlayingPolling` runs only while the panel
  is visible, so the tint only needs to be live then.
- **Art can be dark / monochrome / missing.** The extractor must clamp to a
  *light* legible band and the UI must fall back to the Tahoe look.
- **Risk / fallback:** if SwiftUI glass does not sample a sibling `.background`
  layer, render the wash as its own layer behind the hosting view instead. Verify
  visually early.

## Design

### Core (testable)

- **`ThemeID`** — `.tahoe` / `.albumArt`; `String`-raw `CaseIterable`, `Codable`;
  `title` + `blurb` for the picker.
- **`ThemeStore`** — UserDefaults, mirroring `OnboardingStore` / `HotKeyStore`;
  default `.tahoe`; get/set round-trip.
- **`ThemeColor`** — `(r, g, b)` Doubles, `Sendable`, `Equatable`; HSB helpers
  (`saturation`, `brightness`, `withSaturation`, `withBrightness`, `blended`).
- **`AlbumPalette`** — `top`, `bottom`, `accent` (`ThemeColor`) + `isUsable`,
  `Equatable`.
- **`PixelGrid`** — `width`, `height`, `rgba: [UInt8]` (sRGB 8-bit) — the pure
  input the extractor consumes.
- **`PaletteExtractor`**
  - `static func palette(from grid: PixelGrid) -> AlbumPalette?` — **pure and
    deterministic**:
    1. Average the top third and bottom third → `top`, `bottom`.
    2. Build a coarse histogram (4 bits/channel); pick the most saturated,
       adequately-populated bucket → `accent` (the common colour in album art is
       usually muddy grey/brown, so use vibrancy, not frequency).
    3. **Legibility transform** — cap saturation, clamp brightness into a light
       band, blend toward the panel's neutral base, so the result is always a
       subdued *light* wash. Set `isUsable = false` for near-grey/black/white art.
  - `static func grid(from cgImage: CGImage, side: Int = 24) -> PixelGrid?` — thin
    CGContext downscale (not unit-tested).

### Shell

- **`PaletteCache`** (actor) — `palette(for: ArtworkSource) async -> AlbumPalette?`,
  memoised by `ArtworkSource.cacheKey`; wraps `ArtworkStore.shared.image(for:)` +
  `PaletteExtractor`. Also a synchronous `cached(for:)` for lookups that must not
  trigger a fetch.
- **`AmbientTheme`** (`@MainActor`, ObservableObject) — `@Published palette:
  AlbumPalette?`; input is the now-playing track. Cache-only render; kicks off a
  fetch when missing and publishes when it lands; clears when nothing is playing.
  Owned by `PaletteWindowController` alongside the poll.
- **`PaletteModel`** additions (mirroring the hotkey pattern):
  - `@Published private(set) var theme: ThemeID` (init parameter, like `hotKey`).
  - `var onThemeChange: ((ThemeID) -> Void)?` — persists via `AppDelegate`.
  - `func setTheme(_:)`.
  - the ambient palette, plus `func palette(forRowAt index:) -> AlbumPalette?`
    (cache-only, for the selected-row accent).
- **Wiring** — `AppDelegate` loads `ThemeStore` → passes the theme into
  `PaletteModel` → persists on change. `PaletteWindowController.refreshNowPlaying()`
  also updates `AmbientTheme` (same 1.5 s poll, same track-change trigger).

### Rendering

- **`ThemeBackground`** (new view) — given `theme` + `palette`:
  - `.tahoe` → `Color.clear` (no layer).
  - `.albumArt` + palette → `LinearGradient(top → bottom)` at low opacity over a
    neutral base, filling the panel.
  - `.albumArt` + no palette → neutral base only (reads as near-Tahoe, so nothing
    flashes).
- **`PaletteView`** (`:21`) — keep `.glassEffect(.regular, in: shape)`, then add
  `.background { ThemeBackground(...) }` **after** the glass so the wash sits
  behind it, then `.clipShape(shape)`. Animate
  `.animation(.easeInOut(duration: 0.5), value: palette)`.
- **`ToastView`** (`:31`) — same wash so toasts match the panel.
- **`ResultRowView`** (`:31`) — the local accent: when `.albumArt`, selected, and
  the row's own art is cached, blend that row's `accent` into the selection fill
  (or tint its icon tile). Unchanged under `.tahoe`.

### Resolution flow

1. Panel shown → now-playing poll → `AmbientTheme.update(track)`.
2. `.nowPlaying(persistentID:artist:album:title:)` → `PaletteCache.cached`:
   hit → publish; miss → publish nil, fetch, publish + fade in.
3. Track change → crossfade (~0.5 s).
4. Nothing playing / no art / `!isUsable` → palette nil → neutral base.
5. `.tahoe` → always nil; nothing computed or fetched.

## Settings & commands

- New **`themeRow`** in `SettingsView` (directly after `hotKeyRow`): a dropdown
  (`Picker` with `.menu` style) labelled **Theme**, showing the current theme and
  its blurb, offering **Tahoe** and **Album Art**. Changing it calls
  `model.setTheme(_:)` and persists immediately.
- **`theme` command row.** A new `PaletteAction.setTheme(ThemeID)` and dynamic
  rows injected the same way as "Install Update":
  - **"Theme: Tahoe"** and **"Theme: Album Art"**, each with the theme's own
    `keywords` so `theme`, `tahoe`, `album art`, `gradient`, `tint` all surface
    them; the active one shows a checkmark and "Current theme".
  - Rows only appear once the user types something matching (the empty-box list
    stays as clean as it is today), and running one keeps the palette open so the
    change is visible immediately.
  - `PaletteAction.setTheme` is handled in `PaletteModel.run`, which calls
    `setTheme` → persists via `onThemeChange` and rebuilds the rows so the
    checkmark moves.

## Accessibility & legibility

- `accessibilityReduceTransparency` / Increase Contrast → disable the wash
  (fall back to Tahoe rendering).
- `reduceMotion` → swap instantly, no crossfade.
- Keep the wash light and saturation-capped so `.primary`/`.secondary` text and
  `.selection` fills stay legible over it.
- Never derive semantic colours (success/error toast icons, progress accent) from
  artwork.
- `!isUsable` palettes use the neutral base.

## Files

- **New Core** `Sources/CuebarCore/`: `ThemeID.swift`, `ThemeStore.swift`,
  `ThemeColor.swift`, `AlbumPalette.swift`, `PaletteExtractor.swift`
- **New Shell** `Sources/Cuebar/`: `PaletteCache.swift`, `AmbientTheme.swift`,
  `ThemeBackground.swift`
- **New tests** `Tests/CuebarCoreTests/`: `PaletteExtractorTests.swift`,
  `ThemeStoreTests.swift`, `ThemeColorTests.swift`
- **Modified**: `PaletteView.swift`, `ToastView.swift`, `ToastWindowController.swift`,
  `ResultRowView.swift`, `SettingsView.swift`, `PaletteModel.swift`,
  `PaletteWindowController.swift`, `AppDelegate.swift`
- **Modified Core**: `CommandCatalog.swift` (`PaletteAction.setTheme` + the theme
  entries), `PaletteItem.swift` (a single `artworkSource` accessor, moved down
  from `ResultRowView` so rows and the theme layer agree on one definition)
- **Docs**: `README.md`, `README.dev.md`

## Tests

- `ThemeColor`: HSB round-trip; saturation/brightness clamps; blend.
- `PaletteExtractor`: solid black/white/grey → `!isUsable`; saturated red → pulled
  into the light band; two-tone grid → `top`/`bottom` differ and are ordered
  correctly; same input → same output (determinism).
- `ThemeStore`: defaults to `.tahoe`; round-trips `.albumArt`.
- `ThemeID`: every case has a title, blurb, symbol and non-empty keywords; the
  `theme` keyword surfaces both cases.
- The existing **178** stay green.

## Manual verification

1. Settings shows the Theme dropdown; defaults to Tahoe; the choice survives a
   relaunch.
2. Tahoe is pixel-identical to today.
3. Album Art + a track playing → the panel takes a light version of the cover;
   missing art → neutral; next track → gentle crossfade.
4. Arrow through results → the ambient wash does **not** change per row; only the
   selected row's accent shifts.
5. Command rows / empty box → ambient stays (from now-playing); selection accents
   neutral.
6. Nothing playing → looks like Tahoe.
7. Reduce Transparency on → no wash. Reduce Motion on → no crossfade.
8. Typing `theme` shows both theme rows with a checkmark on the active one;
   running the other switches the panel live and survives a relaunch.
9. Snapshot both themes side by side via `CUEBAR_SNAPSHOT`.

## Decisions locked with the user

1. Exactly two themes: **Tahoe** (default, plain glass) and **Album Art**.
2. Album Art = ambient whole-panel gradient from the **now-playing track's**
   artwork (stable) **plus** a local accent on the selected row.
3. Falls back to the Tahoe look when there is no music/artwork, or the art isn't
   usable.
4. Theme is chosen in **Settings** (dropdown) and persists.
5. Toasts follow the theme.
6. Semantic colours are never recoloured; Reduce Transparency / Increase Contrast
   / Reduce Motion are honoured.
7. The same choice is available from a **`theme` command row** (type `theme`),
   which switches live without closing the palette.

## Out of scope

- Per-row **ambient** tinting (rejected — strobes the whole surface per keystroke).
- A custom colour picker / arbitrary user-chosen colours.
- Blurred-artwork wash (possible third theme later).
- Theming artwork tiles, row backgrounds, or the system accent colour.
- Prefetching or downloading artwork beyond what the rows already cache.
