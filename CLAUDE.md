# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Cuebar** — a Spotlight-style command palette for Apple Music on macOS. Press `⌘⌥Space`, type a song name or a command (`take on me`, `pause`, `next`, `shuffle`, `repeat`, `rebuild`, `settings`, …), Return.

- Swift 6.0, SwiftUI + AppKit, Swift Concurrency. macOS 26 (Tahoe) only — uses Liquid Glass.
- No LLM, no network unless the catalog fallback (iTunes Search API) is needed.
- AppKit agent (`LSUIElement`): no Dock icon; status-bar item with Open / Quit.
- Sources live in `Sources/CuebarCore/` (pure logic, fully unit-tested, no UI) and `Sources/Cuebar/` (AppKit/SwiftUI shell).

## Build, run, test

```sh
make app     # swift build + assemble build/Cuebar.app (ad-hoc signed)
make run     # build, assemble, launch
make test    # swift test  (~197 unit tests in Tests/CuebarCoreTests)
make icon    # regenerate Resources/AppIcon.icns (designs in Scripts/make-icon.swift)
make clean   # swift package clean + rm -rf build
```

- Build/package script: `Scripts/build-app.sh` (used by `make app`).
- `Scripts/release.sh <version>` cuts a release: bumps version, builds, zips, signs with Ed25519, pushes, creates the GitHub release.
- `Scripts/make-update-key.sh` is run once to generate the key pair; paste the public key into `Sources/CuebarCore/ReleaseVerifier.swift`'s `UpdateKey.publicKeyBase64`.

To run a single test file: `swift test --filter RankingTests` (or any other suffix in `Tests/CuebarCoreTests/`).

## Why AppleScript (not MusicKit)

`SystemMusicPlayer` is explicitly unavailable on macOS and the compiler rejects it against the installed SDK. The supported options on macOS are `ApplicationMusicPlayer` (plays *inside* the app, needs entitlement + subscription) and AppleScript against Music.app. Cuebar uses AppleScript so transport controls affect the real Music app. Everything that talks to Music goes through the `MusicController` protocol — see `Sources/CuebarCore/MusicController.swift` (`AppleScriptMusicController` is the only implementation). A future MusicKit one would slot in behind the same protocol.

## Architecture

```
Sources/CuebarCore/         # pure, testable, no UI
  MusicCandidate.swift       # result model
  TextNormalizer.swift       # folding/punctuation
  Similarity.swift           # Damerau–Levenshtein
  Ranking.swift              # deterministic scoring + RankPreference
  SearchQuery.swift          # parses leading/trailing album/playlist keyword
  LibraryResolver.swift      # catalog item → library track (title+artist only)
  LibraryAlbumIndex.swift    # groups songs into playable albums
  LibraryBrowse.swift        # random browse list when a scope is empty
  Command.swift, CommandCatalog.swift, CommandExecutor.swift
  PaletteItem.swift          # command-or-song row composer
  QuickAction.swift          # ⌘K quick-action model + filtering
  MusicController.swift       # protocol + AppleScript implementation
  AppleScriptRunner.swift     # serialized NSAppleScript → async/await
  AppleScriptLibraryProvider.swift  # bulk Apple Event reads
  LibraryIndex.swift          # disk cache (~/Library/Application Support/Cuebar/)
  SearchProviders.swift      # LibrarySearchProvider, ITunesCatalogProvider
  SearchService.swift        # library-first + debounced catalog fallback
  NowPlayingTrack.swift      # current track + shuffle/repeat parsing
  NowPlayingProgress.swift   # interpolates position between 1.5 s polls
  ArtworkStore.swift         # in-memory + on-disk album-art cache (256 px JPEGs)
  Toast.swift / ToastCenter.swift / PlaybackFeedback.swift
  UpdateChecker.swift / ReleaseVerifier.swift / SwapScript.swift
  ThemeID.swift / ThemeStore.swift / ThemeColor.swift
  AlbumPalette.swift / PaletteExtractor.swift / AmbientPaletteCoordinator.swift
  HotKeyPreference.swift / HotKeyStore.swift
  OnboardingStore.swift / WhatsNewStore.swift / WhatsNew.swift
  AppVersion.swift           # semver parse + compare
  BuildChannel.swift         # release vs. experimental, from Info.plist

Sources/Cuebar/             # AppKit/SwiftUI shell
  CuebarMain.swift           # @main; sets .accessory activation policy
  AppDelegate.swift          # hotkey, status item, palette, library lifecycle, debug envs
  HotKeyManager.swift        # Carbon-based global hotkey (no Accessibility)
  PalettePanel.swift / PaletteWindowController.swift   # NSPanel host
  PaletteView.swift           # Liquid Glass container
  PaletteModel.swift         # presentation state
  ResultRowView.swift / NowPlayingCardView.swift / SearchScopeChip.swift
  ActionsMenuView.swift      # ⌘K quick-actions popup
  SettingsView.swift         # embedded settings (hotkey, theme, updates, onboarding)
  OnboardingView.swift / WhatsNewView.swift
  ThemeBackground.swift / PaletteCache.swift / AmbientTheme.swift
  ToastView.swift / ToastPanel.swift / ToastWindowController.swift
  WaveformView.swift         # Spotify-style now-playing equalizer
  ArtworkView.swift / UpdateController.swift
  ExperimentalBadge.swift    # orange potion icon for branch builds
  Support/PaletteMetrics.swift   # single source of truth for corner radius + panel size
  Support/KeyEventTranslator.swift

Tests/CuebarCoreTests/       # swift test target
Scripts/                     # build-app.sh, run.sh, release.sh, make-icon.swift, make-update-key.sh
Resources/                   # Info.plist, generated AppIcon.icns
```

### The palette shell (`Sources/Cuebar`)

Borderless `NSPanel` (`.nonactivatingPanel`, `canBecomeKey`) hosting SwiftUI. Because a borderless window is square, the hosting view sits in a container whose layer is rounded (`cornerRadius`, `cornerCurve = .continuous`, `masksToBounds`), and the SwiftUI content is clipped with a matching `.clipShape`; `invalidateShadow()` makes the window shadow follow the rounded shape. Glass is applied **once** to the container via `.glassEffect(...)` — never to list rows. Corner radius + panel size live in `Support/PaletteMetrics.swift` so AppKit and SwiftUI can't drift. Up/Down/Return/Escape are handled by a local key monitor so they work even while the text field has focus.

### ⌘K actions menu

`⌘K` opens a Raycast-style actions popup for the highlighted row, rendered as an
in-panel overlay anchored to the **bottom-right** of the results area
(`ActionsMenuView`). It offers **Play/Run**, **Like/Unlike**, **Add to Playlist…**
(a submenu of the indexed user playlists, minus *Cuebar Queue*), **Open in Music**,
and a red **Dismiss**, with a **“Search for actions…”** field at the bottom.

- The model lives in `PaletteModel` (`actionsMenu` state, `runQuickAction`); the
  contextual rows and their filtering are pure and unit-tested in
  `CuebarCore/QuickAction.swift`.
- Actions go through new `MusicController` methods (`isLoved`, `setLoved`,
  `addToPlaylist`, `revealInMusic`, `openInMusic`) with testable AppleScript
  builders. `loved` is read once when the menu opens.
- Keys: `↑↓` move, `⏎` runs, `esc` backs out of the submenu/closes, `⌘K` closes;
  everything else types into the actions filter. The local key monitor owns these
  while the menu is open; the main search field is hit-testing-disabled and a
  full-area tap-catcher dismisses on outside click.

The footer shows `⌘, settings │ ⌘K actions` (the actions hint is always present),
followed by the orange potion badge on experimental builds.

### Library indexing + search

- `LibraryIndex` v3 fetched in one bulk Apple Event (tracks + playlists, with `album artist` / `disc number` / `track number`).
- Cached at `~/Library/Application Support/Cuebar/library-index.json`. Indexed once, ~0.26 s for a 6k-track library.
- Albums are grouped by `album + album artist`, ordered by disc then track. Playlists exclude system playlists (`special kind ≠ none`), empty playlists, and Cuebar's own **Cuebar Queue**.
- `SearchService` runs library first; only falls back to iTunes Search when the library has no strong (non-fuzzy) match. Catalog items are resolved back to library tracks by **title + artist** (a same-title track by a different artist is never substituted).

### Album playback

Music has no album object and no queue command, so album playback goes through a reusable user playlist named **Cuebar Queue** (see `AppleScriptMusicController.albumQueueScript`): clear it, `duplicate` the tracks in order, disable shuffle, play it. Library playlists are played directly via `play (first user playlist whose persistent ID is …)` — duplicate names are safe and no temp playlist is created.

### Ranking

Deterministic, in `Sources/CuebarCore/Ranking.swift`:

| Signal | Base score |
|---|---|
| title == query | 1000 |
| title starts with query | 850 |
| all query tokens match in order | 700 |
| title contains query | 600 |
| fuzzy (Damerau–Levenshtein ≥ 0.60) | `ratio × 500` |
| artist contains query | 500 |
| album contains query | 400 |

Bonuses: song +200, album 0, artist −100 (so an exact song outranks a same-named album), library +100, artist +150, album +30. Ties: kind → source → title → id. A leading/trailing `album` or `playlist(s)` keyword sets a `RankPreference` (`.songs` default / `.albums` / `.playlists`) and is stripped from the term.

### Scopes

Typing `album ` / `playlist ` / `theme ` + space turns the keyword into a scope chip in the search box; `PaletteModel.scope` holds the `RankPreference?` or `SearchScope`. `⌫` on an empty field, Esc, or clicking the chip clears it. With a scope active and an empty term, Cuebar publishes a **random browse list** of that kind (`LibraryBrowse`). `theme` is its own `SearchScope` (not a `RankPreference`) because theme selection isn't a music ranking.

### Theming

Two modes, chosen in Settings or by typing `theme`: **Tahoe** (plain Liquid Glass) and **Album Art** (gradient derived from now-playing artwork behind the glass, accent on selected row). `PaletteExtractor` downsamples cached artwork to 24×24, averages top/bottom thirds for the two gradient stops, picks the most saturated bucket for the accent, lifts each stop to a **luma floor of 0.70** so a dark cover can't darken the panel, and clamps chroma (0.16–0.40 wash / 0.28–0.70 accent). Below a chroma-confidence floor → plain glass. **Follow the highlighted row** is a separate toggle (350 ms pause + 700 ms crossfade; logic in `AmbientPaletteCoordinator`, unit-tested with injected resolution and sleep; Reduce Motion swaps instantly). `PaletteCache` mirrors `ArtworkStore` — synchronous first-frame lookup + async, de-duplicated extraction. Reduce Transparency falls back to Tahoe rendering; Reduce Motion drops the crossfade.

### Toasts

`ToastCenter` (`@MainActor`) holds `current` and auto-dismisses (injectable timing for tests). Success = 2 s, error = 4 s. Only one toast at a time; a newer one replaces it. `ToastWindowController` observes `$current`, sizes the panel to SwiftUI content, animates fade (under Reduce Motion) and posts an Accessibility announcement. `PaletteModel` emits toasts through `onToast` **before** `onClose` so the panel frame is still available for anchoring. Anchored below the palette, above when there's no room, top-centre when the palette is hidden (success closes it).

### Build channel

`Scripts/build-app.sh` stamps `CuebarBuildChannel` into the bundle's Info.plist:
`experimental` when the current git branch is `experimental`/`exp*`, otherwise
`release` (override with `CUEBAR_BUILD_CHANNEL`; `Scripts/release.sh` forces
`release`). `BuildChannel.current()` reads it (`CuebarCore/BuildChannel.swift`,
unit-tested) and `ExperimentalBadge` renders an orange potion icon in the bottom
right of the palette footer — next to the `⌘,` / `⌘K` hints and on the Settings
screen — only for experimental builds.

### Updates

- `UpdateChecker` reads `repos/tomatosoup83/cuebar/releases/latest` and compares the tag with `AppVersion.current()`.
- On a newer release: a toast fires and an **"Install Update (x.y.z)"** command row is injected.
- `ReleaseVerifier` checks the download against an **Ed25519** public key baked into `ReleaseVerifier.UpdateKey`, using the `Cuebar.zip.sig` asset. Unsigned or mismatched archives are refused.
- `UpdateController` runs `SwapScript` detached: waits for Cuebar to quit, swaps the bundle (backup + rollback on failure), strips `com.apple.quarantine`, relaunches.

## Permissions and runtime notes

- macOS asks once for **Automation** access to control Music (System Settings › Privacy & Security › Automation). Until granted, playback and library indexing fail with a clear error (`PlaybackError` / `AppleScriptError` flow through `LocalizedError.errorDescription`).
- First launch shows a 3-step onboarding (welcome → grant access → ready); **Esc** skips. Completion stored in `UserDefaults` via `OnboardingStore`; replay from Settings → "Show Onboarding Again".
- Ad-hoc rebuilds can reset the Automation permission, hence the replay path.
- Hotkey is recorded in-app (Settings → Launch Hotkey, or `⌘,`); the combo must include ⌘, ⌥, or ⌃. Stored via `HotKeyStore` (`UserDefaults`), registered with Carbon — no Accessibility permission needed.
- `Scripts/build-app.sh` ad-hoc codesigns the bundle so Automation permission is scoped to the running build.

## Debug helpers (`#if DEBUG` only)

Read from `ProcessInfo.processInfo.environment` in `AppDelegate`:

| Variable | Effect |
|---|---|
| `CUEBAR_SHOW_ON_LAUNCH=1` | open the palette on launch |
| `CUEBAR_PREVIEW_QUERY="hey jude"` | pre-fill a query |
| `CUEBAR_SNAPSHOT=/tmp/panel.png` | render the panel to PNG, then quit |
| `CUEBAR_FORCE_PLAYING=1` | treat current track as playing (capture equalizer) |
| `CUEBAR_OPEN_SETTINGS=1` / `=recording` / `=onboarding` | open that screen |
| `CUEBAR_OPEN_ACTIONS=1` / `=playlists` | open the ⌘K actions menu / its playlist submenu |
| `CUEBAR_THEME=albumart` / `tahoe` | start in that theme |
| `CUEBAR_WASH_OPACITY=0.30` / `CUEBAR_GLASS_TINT=0.35` / `CUEBAR_ROW_TINT=0.55` | override theme defaults |
| `CUEBAR_DARK=1` / `CUEBAR_DARK_COVER=1` | force dark appearance / dark cover path |
| `CUEBAR_FAKE_NOWPLAYING=1` | inject a fake now-playing track |
| `CUEBAR_FOLLOW_SELECTION=1` / `=0` | override follow-highlighted-row |
| `CUEBAR_DUMP_PALETTES=N` | log first N extracted palettes |
| `CUEBAR_CYCLE_TEST=ms` | cycle through N rows at `ms` per step |
| `CUEBAR_ONBOARD=1` | re-show onboarding |

Example:

```sh
CUEBAR_SHOW_ON_LAUNCH=1 CUEBAR_PREVIEW_QUERY="take" \
  CUEBAR_SNAPSHOT=/tmp/panel.png ./build/Cuebar.app/Contents/MacOS/Cuebar
```

The snapshot uses offscreen AppKit rendering, so backdrop glass materials are not captured — layout, rows and text are.

## Conventions

- All non-UI logic belongs in `CuebarCore` and must be unit-testable. UI shells (`Cuebar/`) wire it together.
- `MusicController` is the only thing that talks to Music.app — AppleScript always goes through `AppleScriptRunner` (serialized, async/await). Never hand-roll an `NSAppleScript` in feature code.
- Errors raised by playback / AppleScript are `LocalizedError` and surface via `PlaybackFeedback` so toast copy is uniform.
- Search scoring and ranking live in `Ranking.swift` and `Similarity.swift`; don't inline matching inside views.
- Strings that touch AppleScript must go through `AppleScriptMusicController.escape(_:)`.
- Theme palette extraction is pure (`PaletteExtractor`); the shell (`PaletteCache` / `AmbientTheme`) handles caching and timing.