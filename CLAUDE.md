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
make test    # swift test  (~400 unit tests in Tests/CuebarCoreTests)
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
  SearchQuery.swift          # parses leading/trailing album/playlist/artist keyword
  LibraryResolver.swift      # catalog item → library track (title+artist only)
  LibraryAlbumIndex.swift    # groups songs into playable albums
  LibraryArtistIndex.swift   # groups songs into artists (the artist page)
  LibraryBrowse.swift        # random browse list when a scope is empty
  AlbumFacts.swift           # the extended album view's facts line
  AlbumTrackList.swift       # album running order + display numbers
  TimeFormat.swift           # m:ss durations
  Command.swift, CommandCatalog.swift, CommandExecutor.swift
  CuebarURL.swift            # cuebar:// URL → CuebarRequest
  HeadlessCommand.swift      # input → HeadlessAction + the runner (no palette)
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
  AlbumTrackRowView.swift / RowSelectionBackground.swift
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
raycast/                     # optional Raycast extension (a cuebar:// client)
```

### The palette shell (`Sources/Cuebar`)

Borderless `NSPanel` (`.nonactivatingPanel`, `canBecomeKey`) hosting SwiftUI. Because a borderless window is square, the hosting view sits in a container whose layer is rounded (`cornerRadius`, `cornerCurve = .continuous`, `masksToBounds`), and the SwiftUI content is clipped with a matching `.clipShape`; `invalidateShadow()` makes the window shadow follow the rounded shape. Glass is applied **once** to the container via `.glassEffect(...)` — never to list rows. Corner radius + panel size live in `Support/PaletteMetrics.swift` so AppKit and SwiftUI can't drift. Up/Down/Return/Escape are handled by a local key monitor so they work even while the text field has focus.

### One scroll container, many views

The results list is a single `ScrollView` across **every** presentation, so it keeps its offset when the content changes underneath it. Left alone that strands the next view: an album view opened from a scrolled album list renders *blank*, because its much shorter content sits entirely above the inherited offset, and going back leaves the previous view scrolled to wherever the next one was.

`PaletteView` therefore keeps a `savedScrollOffsets` dictionary keyed by `scrollContext` (`search`, `artist:<id>`, `album:<id>`) and restores the incoming context's offset via `.scrollPosition(_:)` on every change. Two details matter:

- The geometry callback records the offset under the **current** context only when `observedScrollContext` matches it. One callback still carries the *outgoing* view's offset right after a switch, and filing that under the incoming context would clobber the very position being restored.
- `.scrollPosition(_:)` coexists with the existing `ScrollViewReader.scrollTo` that keyboard navigation uses; the binding is only written on a context change, so selection scrolling is unaffected.

**Leaving a detail view restores its list, it does not recompute it.** `PaletteModel.captureReturnState()` snapshots `music`, `commands`, `browsePreference`, `resultsQuery` and `selectedIndex` when the artist page or album view opens, and `restoreReturnState()` puts them back. Recomputing instead re-shuffles a browse list — leaving an album view handed back a *different* random order — and arrives asynchronously, so the scroll restore would clamp against the outgoing (much shorter) content before the real one landed, dumping you at the top. Restoring `browsePreference` / `resultsQuery` also makes the view's own `onChange` for the restored field harmless: `queryChanged()` sees the browse kind or query it already holds and neither re-shuffles nor re-searches over the top. When the field was empty before *and* after — the browse case — assigning it is not even a change, so `queryChanged()` never runs.

`CUEBAR_PREVIEW_QUERY="album "` + `CUEBAR_CYCLE_TEST=40` + `CUEBAR_EXTENDED=3.4` (+ `CUEBAR_ALBUM_BACK=4.3`) reproduces both directions; swap in `artist ` + `CUEBAR_ARTIST_BACK` for the artist page.

### ⌘K actions menu

`⌘K` opens a Raycast-style actions popup for the highlighted row, rendered as an
in-panel overlay anchored to the **bottom-right** of the results area
(`ActionsMenuView`). It offers **Play/Run**, **Like/Unlike**, **Add to Playlist…**
(a submenu of the indexed user playlists, minus *Cuebar Queue*), **View Album**
(library albums only), **Open in Music**, and a red **Dismiss**, with a **“Search for actions…”** field at the bottom.

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

- `LibraryIndex` v3 fetched in one bulk Apple Event (tracks + playlists, with `album artist` / `disc number` / `track number` / `year` / `genre`). `year` and `genre` were added **without** bumping `currentVersion`: they are optional on `MusicCandidate`, so an older cache still decodes, and `loadLibrary()` re-indexes on every launch anyway — the facts simply fill in a few seconds later instead of forcing a re-index window with no library.
- Cached at `~/Library/Application Support/Cuebar/library-index.json`. Indexed once, ~0.26 s for a 6k-track library.
- Albums are grouped by `album + album artist`, ordered by disc then track. Playlists exclude system playlists (`special kind ≠ none`), empty playlists, and Cuebar's own **Cuebar Queue**.
- `SearchService` runs library first; only falls back to iTunes Search when the library has no strong (non-fuzzy) match. Catalog items are resolved back to library tracks by **title + artist** (a same-title track by a different artist is never substituted).

### The `cuebar://` URL scheme (headless commands)

Cuebar answers `cuebar://run?command=<palette input>`, so Raycast, Shortcuts, a Stream Deck or a shell script can drive it without the palette. `Resources/Info.plist` declares the scheme; `AppDelegate.application(_:open:)` receives the URL (this is the only delivery path — the `kAEGetURL` AppleEvent handler is deliberately *not* registered as well, or every command would run twice). A ready-made client lives in `raycast/`.

- **One vocabulary.** The input is exactly what you'd type into the palette, parsed by `CuebarURL` → `CuebarRequest` → `HeadlessCommandParser`. That parser accepts a `CommandCatalog` entry only on an **exact** keyword match (`CommandCatalog.score == 1000`) and otherwise defers to `CommandParser` — the palette can match fuzzily because you pick from a rendered list; a URL has no list, so `rebuilding my library` must stay a song search rather than firing `Rebuild Library Index`.
- **A `command` parameter always wins over the host**, so a mistyped host can't silently become a song search. Bare `cuebar://rebuild` and `cuebar://pause` (host-as-input, path joined by spaces) are shorthands; `cuebar://run` with nothing to run is rejected rather than searched for the word "run".
- **Search is library-only.** The palette falls back to the iTunes catalog so it can *show* unowned songs, but a catalog row can't be played — so `HeadlessCommandRunner` skips that fallback and a URL command never touches the network. Resolution mirrors `PaletteModel.executeSelection`: album → `executeAlbum` (Cuebar Queue), playlist → `executePlaylist`, song → `execute`. Artist rows are pages, not playable items, so `artist ` is the one scope that stays window-only.
- **Readiness gate.** `AppDelegate.waitForLibrary()` polls up to 8 s for `isLibraryReady`, which is set as soon as the *cached* index is installed (before the launch re-index) and again when the re-index finishes — successfully or not. Without the second release, a command arriving before a failed first index would hang until timeout instead of reporting the failure; a failed index with an empty library surfaces the real `AppleScriptError` (permission guidance) rather than "no match".
- **Feedback is Cuebar's toast**, via `PlaybackFeedback.toast(for: HeadlessOutcome)` — the same copy and the same `Command` switch the palette uses, which is why `PaletteModel.run` now delegates to `PlaybackFeedback.toast(for:shuffleBefore:selected:)` instead of owning a private copy. A launcher therefore shows nothing itself; two messages would disagree.
- Permission-wise this is the whole point: the AppleEvent to Music is sent by **Cuebar**, which already holds the Automation grant, so the launcher never needs one. Launching the app from a shell instead (as a CLI client would) would attribute the AppleEvent to the launching process and fail with `-10004`.

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

Bonuses: song +200, album 0, artist −100 (so an exact song outranks a same-named album), library +100, artist +150, album +30 — unless the kind leads its own preference, which is +200 (so `.artists` lifts artist rows out of the −100). Ties: kind → source → title → id. A leading/trailing `album`, `playlist(s)`, or `artist(s)` keyword sets a `RankPreference` (`.songs` default / `.albums` / `.playlists` / `.artists`) and is stripped from the term.

`Ranking.rankWithin` is the separate, title-only ranker behind the artist page's filter and the album view's: every track there already belongs to that artist or album, so the usual artist/album fallback would match the collection's own name and return all of it for any fragment of it.

### Scopes

Typing `album ` / `playlist ` / `artist ` / `theme ` + space turns the keyword into a scope chip in the search box; `PaletteModel.scope` holds the `RankPreference?` or `SearchScope`. `⌫` on an empty field, Esc, or clicking the chip clears it. With a scope active and an empty term, Cuebar publishes a **random browse list** of that kind (`LibraryBrowse`). `theme` is its own `SearchScope` (not a `RankPreference`) because theme selection isn't a music ranking.

`album ` and `playlist ` only *reorder* results (songs still appear). `artist ` is a hard **filter** — artist rows are destinations, not playable items — so it searches `LibrarySearchProvider.searchArtists` directly rather than ranking the whole library first, where thousands of song matches would crowd every artist out of the result limit. Artist rows also appear in a plain search (their title *is* the artist), which is how the page is reachable without the scope.

Because the artist scope computes its rows **locally**, its empty-term sample is rebuilt whenever one isn't already up *or* `music` is empty — not on the bare `browsePreference != .artists` guard the album/playlist path uses. `searchService.clear()` at the top of the branch empties `music` through the results sink, and promoting the keyword clears the field programmatically, so the view's own `onChange` runs the branch a second time: with the bare guard it skipped the refill and the palette sat blank until the next keystroke. (`album ` / `playlist ` are unaffected — their rows arrive asynchronously from `searchService.browse`, which nothing wipes.)

### The artist page

⏎ on an artist row opens the artist's page: a **shuffled sample** of their songs until something is typed, then matches from `Ranking.rankWithin` (`PaletteModel.artistFocus` / `artistTracks` / `artistIsBrowsing`). It is deliberately *not* a `PaletteScreen` — the page keeps the search field, so it lives inside the search screen as one more piece of in-field state and reuses the existing field, focus token, list and footer. `PaletteModel.openArtist` remembers the search it was opened from; Esc, `⌫` on an empty field, or clicking the chip restores it, and the page never promotes a keyword into a scope while it is open. Like a scope, it is cleared by `reset()` when the palette reopens.

The chip stays the plain `Artist ›` `SearchScopeChip` (tooltip overridden to "Back to search"); the artist's name goes in a **status bar** between two separators below the field — `Searching for songs from <artist>` — so the field itself keeps the same height as every other screen. That bar uses an explicit `Color.primary.opacity(0.05)` tint rather than `.quaternary`, which composites against the backdrop and renders as an opaque white strip there. `openArtist` fills the list **directly** via `artistShowSample()` instead of routing through `queryChanged()`: the songs must be on screen the instant the page opens, not one round trip later, and the view's own `onChange` for the cleared field then finds the sample already up. `artistQueryChanged`'s empty-field path rebuilds the sample whenever it isn't already showing *or* `music` is empty, so an empty field can never leave the page blank while the artist has songs.

Artists are derived from the library by `LibraryArtistIndex`, exactly as albums are by `LibraryAlbumIndex`: grouped by **album artist** (falling back to the track artist), so compilations stay under "Various Artists" rather than scattering into each performer's page. Feature credits (`Drake feat. …`) are deliberately *not* split — the tag is taken at face value.

### The extended album view

**⌘⏎** on a library album row — or **View Album** in the ⌘K menu, which shows the `⌘↩` hint — opens the album's own view: cover, a facts line, and the tracks in their **original running order** (`PaletteModel.albumFocus` / `albumTracks` / `albumFacts`). It is the artist page's pattern again, for the same reasons: in-field state rather than a `PaletteScreen`, so it reuses the field, focus token, list and footer; `openAlbumView` fills the list **directly** rather than routing through `queryChanged()`, and Esc / `⌫` on an empty field / the chip restores the search it was opened from. Typing filters the track list through `Ranking.rankWithin`, which is title-only for the same reason it is on the artist page — the album's name is on every track, so the usual fallback would match all of them.

`AlbumFacts` builds the one line under the title — `2007 · Alternative · 10 tracks · 42 min` — dropping any part it doesn't have rather than leaving a gap, so a sparsely tagged album still reads as a sentence. `AlbumTrackList` supplies the numbers beside each row (`1`, or `1-3` on a multi-disc album, which is what makes the running order legible in a palette where every other list is ranked or shuffled). Rows use `AlbumTrackRowView`, not `ResultRowView`: every row is the same album, so a repeated cover and a "Library" badge would both be noise, while the duration is what you actually want. `RowSelectionBackground` is shared by both row types so their selection treatment can't drift.

**Row identity must change with the presentation.** The album view renders `.music` rows with a *different view type* (`AlbumTrackRowView`), so `PaletteView.rowIdentity(for:)` namespaces them (`albumTrack:<PaletteItem.id>`) and both the `.id()` and the `scrollTo` target use it. Keyed on `PaletteItem.id` alone the identity does not change when the view opens or closes, and the lazy list **reuses whatever row was already on screen** for that track: a cover-art search row stranded inside the album view, or a numbered track row left behind in the search list after leaving. Only the album view is affected — the artist page renders `.music` rows with the same view type as search, so its identity can stay as it is. `CUEBAR_SELECT_ALBUM` + `CUEBAR_EXTENDED` + `CUEBAR_ALBUM_BACK` (values are delays) reproduce both directions.

There is deliberately **no description**. Music.app has no album object, so nothing to read; the tracks' own `description` tag is empty in practice (0 of 6425 tracks here) and `comment` holds video credits rather than prose; the iTunes Search API returns no description for albums; and editorial prose only exists behind a MusicKit developer token, which an open-source app can't ship. Hence the facts line, which is derived from tags that are actually present — year on 99.8% of albums here, genre on 99.6%.

### Theming

Three modes, chosen in Settings or by typing `theme`: **Tahoe** (plain Liquid Glass), **Album Art** (gradient derived from now-playing artwork behind the glass, accent on selected row), and **Album Art v2** (the same treatment, but the stops come from median-cut clusters rather than a single histogram bucket — an opt-in A/B). **Album Art is the default**, shipped with follow-the-highlighted-row **on**; `ThemeStore.applyAlbumArtDefaultIfNeeded()` runs once at launch to move upgraders onto both, recording `appliedAlbumArtDefault` so a later choice is never overridden. `PaletteExtractor` downsamples cached artwork to 24×24 and picks three raw base colours, then runs them through a shared legibility transform: it lifts each stop to a **luma floor of 0.70** so a dark cover can't darken the panel, and clamps chroma (0.16–0.40 wash / 0.28–0.70 accent). The `.classic` algorithm averages the top/bottom thirds and takes the most saturated 4-bit histogram bucket for the accent; `.clustered` runs deterministic median-cut quantization into `clusterBudget` (8) clusters, feeds the upper/lower clusters into the top/bottom stops (keeping the vertical gradient) and the most vivid cluster into the accent. Album Art v2 adds a **Global Colours** option (`ThemeStore.globalClusteredColours`, off by default): with `ClusterLayout.global` every cluster feeds both stops, so the wash is a flat pywal-style colour with no gradient. Below a chroma-confidence floor → plain glass. `ThemeID.isAlbumArt` covers both variants; `ThemeID.paletteStyle(globalClusteredColours:)` maps a theme + option to a `PaletteStyle` (algorithm + `ClusterLayout`). **Follow the highlighted row** is a separate toggle (350 ms pause + 700 ms crossfade; logic in `AmbientPaletteCoordinator`, unit-tested with injected resolution and sleep; Reduce Motion swaps instantly). `PaletteCache` mirrors `ArtworkStore` — synchronous first-frame lookup + async, de-duplicated extraction — keyed by artwork **and** `PaletteStyle` so the themes and options don't clobber each other. Reduce Transparency falls back to Tahoe rendering; Reduce Motion drops the crossfade.

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
- **Launch the app with `open -a build/Cuebar.app`, never by executing the binary from a terminal.** TCC attributes an AppleEvent to the *responsible* process: run `./build/Cuebar.app/Contents/MacOS/Cuebar` and the requesting process is the shell, which has no grant, so every Music call fails with `-10004` ("privilege violation") even though Cuebar itself is allowed. Launched via LaunchServices, Cuebar is its own responsible process and the grant applies. `osascript` from a shell is likewise denied.
- `open --env VAR=value` is **not** forwarded to the app, so a Music-touching debug run cannot take its flag from the environment. Have the probe read a file (or write its result to one) instead.
- Hotkey is recorded in-app (Settings → Launch Hotkey, or `⌘,`); the combo must include ⌘, ⌥, or ⌃. Stored via `HotKeyStore` (`UserDefaults`), registered with Carbon — no Accessibility permission needed.
- `Scripts/build-app.sh` ad-hoc codesigns the bundle so Automation permission is scoped to the running build.

## Debug helpers (`#if DEBUG` only)

Read from `ProcessInfo.processInfo.environment` in `AppDelegate`:

| Variable | Effect |
|---|---|
| `CUEBAR_SHOW_ON_LAUNCH=1` | open the palette on launch |
| `CUEBAR_PREVIEW_QUERY="hey jude"` | pre-fill a query |
| `CUEBAR_TYPE_QUERY=1` | type `CUEBAR_PREVIEW_QUERY` keystroke by keystroke across runloop turns, so the view's `onChange` fires between them (how scope-promotion bugs are reproduced) |
| `CUEBAR_SNAPSHOT=/tmp/panel.png` | render the panel to PNG, then quit |
| `CUEBAR_FORCE_PLAYING=1` | treat current track as playing (capture equalizer) |
| `CUEBAR_OPEN_SETTINGS=1` / `=recording` / `=onboarding` | open that screen |
| `CUEBAR_OPEN_ACTIONS=1` / `=playlists` | open the ⌘K actions menu / its playlist submenu |
| `CUEBAR_OPEN_ARTIST="Radiohead"` | open that artist's page — types the query keystroke by keystroke, then ⏎ (`CUEBAR_PREVIEW_QUERY` becomes the page's filter) |
| `CUEBAR_ARTIST_BACK=4.3` | leave the artist page (value = delay in seconds, default 1.0) |
| `CUEBAR_OPEN_ALBUM="SWAG II"` | open the extended album view for a matching album, via the real scope → row → ⌘⏎ path (`CUEBAR_PREVIEW_QUERY` becomes the view's filter) |
| `CUEBAR_SELECT_ALBUM=3.2` | highlight the nearest library album row (value = delay in seconds, default 0.8) |
| `CUEBAR_EXTENDED=3.4` | press ⌘⏎ on the highlighted row without changing the query (value = delay in seconds, default 1.0) |
| `CUEBAR_ALBUM_BACK=4.3` | leave the album view (value = delay in seconds, default 1.6) |
| `CUEBAR_THEME=albumart` / `albumartv2` / `tahoe` | start in that theme |
| `CUEBAR_WASH_OPACITY=0.30` / `CUEBAR_GLASS_TINT=0.35` / `CUEBAR_ROW_TINT=0.55` | override theme defaults |
| `CUEBAR_DARK=1` / `CUEBAR_DARK_COVER=1` | force dark appearance / dark cover path |
| `CUEBAR_FAKE_NOWPLAYING=1` | inject a fake now-playing track |
| `CUEBAR_FOLLOW_SELECTION=1` / `=0` | override follow-highlighted-row |
| `CUEBAR_GLOBAL_COLOURS=1` / `=0` | override the Album Art v2 global-colours option |
| `CUEBAR_DUMP_PALETTES=N` | log first N album palettes, classic / clustered / global |
| `CUEBAR_CYCLE_TEST=ms` | cycle through N rows at `ms` per step |
| `CUEBAR_ONBOARD=1` | re-show onboarding |

Example:

```sh
CUEBAR_SHOW_ON_LAUNCH=1 CUEBAR_PREVIEW_QUERY="take" \
  CUEBAR_SNAPSHOT=/tmp/panel.png ./build/Cuebar.app/Contents/MacOS/Cuebar
```

The snapshot uses offscreen AppKit rendering, so backdrop glass materials are not captured — layout, rows and text are. This direct-execution form is fine for pure layout work (it renders from the cached index), but it has **no Music access** — see the responsible-process note above. Anything that needs live Music data must be launched with `open` and must not depend on environment variables.

## Conventions

- All non-UI logic belongs in `CuebarCore` and must be unit-testable. UI shells (`Cuebar/`) wire it together.
- `MusicController` is the only thing that talks to Music.app — AppleScript always goes through `AppleScriptRunner` (serialized, async/await). Never hand-roll an `NSAppleScript` in feature code.
- Errors raised by playback / AppleScript are `LocalizedError` and surface via `PlaybackFeedback` so toast copy is uniform.
- Search scoring and ranking live in `Ranking.swift` and `Similarity.swift`; don't inline matching inside views.
- Strings that touch AppleScript must go through `AppleScriptMusicController.escape(_:)`.
- Theme palette extraction is pure (`PaletteExtractor`); the shell (`PaletteCache` / `AmbientTheme`) handles caching and timing.