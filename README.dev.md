# Cuebar

A Spotlight/Raycast-style command palette for Apple Music on macOS.

Press **⌘⌥Space**, type a song name or a command, press **Return**.

```
play take on me     → finds and plays the song
pause / resume
next / previous
shuffle [on|off]
repeat [queue|track|off]
rebuild library index
```

Bare text (e.g. `take on me`) is treated as `play take on me`.

Commands also appear as selectable rows in the results box — including when the
box is empty, so they are discoverable. Typing the start of a command (`pau`,
`nex`, `shuffle o`) surfaces it above any song matches, and Return runs the
selected row.

With an empty box the palette shows a **home screen**: the **current Music.app
track** in a large card at the top (with a Spotify-style animated equalizer while
it plays, "Paused" with static bars otherwise), followed by a **Recently Played**
shelf, so it is useful the moment it opens. Return on the card toggles
play/pause; typing anything swaps the home screen for search results.

Built with Swift, SwiftUI, AppKit and Swift Concurrency. No LLM, no network
unless the catalog fallback is needed.

---

## Why AppleScript instead of `SystemMusicPlayer`

The original brief asked for MusicKit + `SystemMusicPlayer`. That is **not
possible on native macOS**: Apple explicitly marks `SystemMusicPlayer`
unavailable, and the compiler rejects it against the installed SDK.

```
error: 'SystemMusicPlayer' is unavailable in macOS
note: 'SystemMusicPlayer' has been explicitly marked unavailable here
      @available(macOS, unavailable)
```

The older `MPMusicPlayerController.systemMusicPlayer` is likewise
`API_UNAVAILABLE(macos)`.

What remains on macOS:

| Option | Controls Music.app? | Needs entitlement? |
|---|---|---|
| `SystemMusicPlayer` | n/a — unavailable | — |
| `ApplicationMusicPlayer` (MusicKit) | no — plays inside the app | yes (+ subscription) |
| **AppleScript → Music.app** | **yes** | no |

Cuebar drives the real Music app with AppleScript, which is the true functional
equivalent of `SystemMusicPlayer`: transport and shuffle affect system playback
and keep working after Cuebar quits. `MusicController` is a protocol, so a
MusicKit implementation can be added later behind the same surface.

---

## Requirements

- macOS 26 or later (Liquid Glass, SwiftUI `glassEffect`)
- The Music app with a populated library
- Apple Music subscription only for the catalog fallback

## Build, run, test

```sh
make app     # build + assemble build/Cuebar.app (ad-hoc signed)
make run     # build, assemble and launch
make test    # run the unit test suite
make icon    # regenerate the app icon (designs live in Scripts/make-icon.swift)
```

`Scripts/build-app.sh` runs `swift build` and packages the executable into a
proper `.app` bundle with `Resources/Info.plist` (`LSUIElement`, automation
usage strings) and `Resources/AppIcon.icns`, then ad-hoc codesigns it.

The icon is generated (not hand-drawn) by `Scripts/make-icon.swift`, which
renders a Big Sur-style rounded squircle with a gradient and a glyph. Run
`make icon` to rebuild it, or `swift Scripts/make-icon.swift preview
build/icon-previews` to render every candidate design.

The app runs as an agent (`LSUIElement`): no Dock icon, a menu-bar item with
**Open Cuebar** and **Quit**.

## First run

macOS asks once for permission to control **Music** (System Settings › Privacy
& Security › Automation). Until it is granted, playback and library indexing
report a clear error.

On first launch Cuebar shows a three-step **onboarding** inside the palette
(welcome → grant access → ready): it introduces the launch hotkey, checks the
Automation permission (with a *Grant Access* probe and an *Open System Settings*
link), then shows the library index summary. **Esc** skips it. Completion is
remembered in `UserDefaults`, and Settings has **Show Onboarding Again** to
replay it (useful because ad-hoc rebuilds can reset the Automation permission).

The library index is built on first launch (about 0.26 s for a 6k-track library)
and cached at `~/Library/Application Support/Cuebar/library-index.json`, so
later launches are instant. Use the in-app **Rebuild Library Index** command
(type `rebuild`) after adding music.

---

## How search works

1. **Library first.** The cached index is searched locally and results appear
   immediately.
2. **Catalog fallback.** The public iTunes Search API is only queried when the
   library has no *strong* (non-fuzzy) match. Strong matches are exact, prefix,
   token-in-order and substring matches.
3. **Ranking** (`Sources/CuebarCore/Ranking.swift`) is deterministic:

   | Signal | Base score |
   |---|---|
   | title == query | 1000 |
   | title starts with query | 850 |
   | all query tokens match in order | 700 |
   | title contains query | 600 |
   | fuzzy (Damerau–Levenshtein ≥ 0.60) | `ratio × 500` |
   | artist contains query | 500 |
   | album contains query | 400 |

   Plus bonuses: **song +200 / album 0 / artist −100** (this guarantees an exact
   song title outranks an album with the same name), **library +100**, artist
   +150, album +30. Ties break on kind, then source, then title, then id.

   A leading or trailing keyword — **`album`** or **`playlist`/`playlists`**
   (`SearchQuery`) — is stripped from the term and sets a `RankPreference`
   (`.songs` default / `.albums` / `.playlists`) that puts that kind first. So
   `take on me` returns the song first, `take on me album` the album first. The
   keyword must be separated by whitespace (typing `album` alone stays literal);
   the catalog-fallback "strong match" check only considers songs.

   With a scope active and an **empty term**, Cuebar publishes a **random browse
   list** of that kind (`LibraryBrowse`: shuffle + cap at the result limit),
   hiding the now-playing row. Typing switches back to ranked search.

Typo tolerance is included: `blinding lites` resolves to *Blinding Lights*.

## Album playback

Music's scripting dictionary has **no album object** and no queue command, so
albums are synthesized and played through a reusable playlist:

- `LibraryAlbumIndex` groups library songs by `album + album artist`, ordered by
  disc then track, producing one `MusicCandidate` (kind `.album`) per album and
  an id → ordered-tracks map. Songs with no album are skipped.
- The index (v2) fetches `album artist`, `disc number` and `track number` in the
  same bulk Apple Event as the rest of the library.
- Selecting an album calls `MusicController.playAlbum`, which builds a script
  (`AppleScriptMusicController.albumQueueScript`) that ensures a user playlist
  named **Cuebar Queue**, clears it, `duplicate`s the album's tracks in order,
  sets `shuffle enabled` to false, and plays it. The queue is reused next time.

## Playlists

Library playlists are indexed alongside tracks (`LibraryIndex` v3):

- `AppleScriptLibraryProvider.fetchPlaylists()` loops `user playlists` in one
  Apple Event, keeping only `special kind = none` (which drops Music's system
  playlists) and returning each name, persistent ID, track count and first
  track id (for artwork).
- Cuebar's own **Cuebar Queue** and empty playlists are excluded.
- Selecting a playlist plays it **directly** —
  `play (first user playlist whose persistent ID is …)` — so duplicate names are
  safe and no temporary playlist is created. Shuffle is left as-is.
- Playlists surface with a **"Playlist"** badge; the `playlist`/`playlists`
  keyword prioritises them.

## Search scope chip

Typing `album`/`playlist` plus a space moves the keyword into a **scope chip**
in the search box (`SearchScopeChip`), so the field then shows only the name.
`PaletteModel.scope` holds a `RankPreference?`; ⌫ on an empty field, Esc, or
clicking the chip clears it (`clearScope()`), and command rows are suppressed
while a scope is active.

## Home screen (recently played)

An empty palette shows the now-playing card followed by a **Recently Played**
shelf of the last 8 library songs, each with a compact "how long ago" label
(`5m ago`, `Yesterday`, `2w ago`). Return plays the song.

- `AppleScriptLibraryProvider.fetchPlayedDates()` reads `persistent ID` and
  `played date` of every track in two bulk Apple Events (~0.2 s for 6k tracks),
  then loops locally — outside the `tell`, through a script object so list access
  stays O(1) — emitting each played track's age relative to `current date`, which
  keeps the output locale-independent. It returns nothing when Music isn't
  running, so opening the palette never launches it.
- **Music's `played date` is unreliable** — streamed and partly played tracks are
  often never stamped, so the newest plays can be days stale. The shelf therefore
  also uses `PlayHistory`: `AppDelegate` listens for Music's
  `com.apple.Music.playerInfo` distributed notification (fired on every track
  change, whether or not Cuebar started it and whether or not the palette is open)
  and logs each track that starts playing to
  `~/Library/Application Support/Cuebar/play-history.json` (200 tracks, one entry
  per track at its latest play). The notification's `PersistentID` is a 64-bit
  integer; formatted as 16 upper-case hex digits it equals the ID AppleScript and
  the library index use. The two sources are merged by age and the newest play
  wins. Tracks that were already playing when Cuebar launched are logged on the
  first poll. Only library tracks can appear (catalog-only plays can't be played
  from here).
- `RecentlyPlayed` (Core, pure) parses that, resolves ids against the index
  (dropping deleted tracks and non-songs), de-duplicates, sorts newest-first with a
  deterministic tie-break, leaves out the track that is playing (it has the card)
  and formats the relative label.
- The fetch runs after the first now-playing poll on every open, and again when
  the track changes. The shelf is kept between openings, so it paints on the first
  frame; it is also re-resolved when an index refresh finishes, because the dates
  can arrive before the index on first launch.
- With a shelf, the home screen drops the transport commands (they duplicate the
  card's controls) — `PaletteListComposer.homeCommands` keeps only an available
  update. With no shelf (nothing played yet, Music not running) every command
  shows, as before. Rows are `PaletteItem.recent`, under a "Recently Played"
  section header.

## Now-playing card

The current track renders as a larger card (`NowPlayingCardView`) at the top of
an empty palette: artwork, an animated equalizer with Playing/Paused, a progress
bar, and clickable **play/pause / shuffle / repeat** buttons. Return on the card
still toggles play/pause, and the footer then reads **"⏎ play/pause"**.

- Position/duration come from the now-playing script, which now also reads
  `shuffle enabled` and `song repeat`. `NowPlayingProgress` interpolates the
  position between the 1.5 s polls (frozen when paused), so the bar is smooth
  without extra AppleScript.
- Controls update the card optimistically, then reconcile on the next poll.
  Repeat is a simple **off ↔ all** toggle (it shows `repeat.1` if Music is in
  repeat-one).
- Card controls don't close the palette; Return on an ordinary command row still
  does.
- **Artwork glow**: a blurred, saturated copy of the cover sits behind the
  artwork, added as light (`plusLighter`) so it still reads when the cover matches
  It breathes on a slow ~4 s cycle while playing and dims when paused;
  Reduce Motion holds it still. The results list is a `ScrollView`, which would
  clip the glow at the search box, so the list uses `scrollClipDisabled()` with a
  mask that reaches 44 pt above it — and shrinks to nothing within a few points of
  scrolling, so rows never bleed over the field.

## Updates

Cuebar checks GitHub for a newer release — automatically on launch (when
enabled) and on demand via the `update` command or **Settings → Software Update**.

- `UpdateChecker` reads `repos/tomatosoup83/cuebar/releases/latest` and compares
  the tag with `AppVersion.current()`.
- When newer, a toast fires and an **"Install Update (x.y.z)"** command row is
  injected; Return, or the Settings *Install* button, downloads `Cuebar.zip`.
- `ReleaseVerifier` checks the download against the **Ed25519** public key baked
  into `ReleaseVerifier.UpdateKey`, using the `Cuebar.zip.sig` asset. Unsigned or
  mismatched archives are refused.
- `UpdateController` then runs `SwapScript` detached: it waits for Cuebar to
  quit, swaps the bundle (with a backup + rollback on failure), strips
  `com.apple.quarantine`, and relaunches.

**Releasing:** `Scripts/release.sh <version>` bumps the version, builds, packages
`Cuebar.zip`, signs it to `Cuebar.zip.sig`, commits/pushes and creates the GitHub
release. One-time setup: `Scripts/make-update-key.sh` generates the key pair and
prints the public key to paste into `UpdateKey.publicKeyBase64` (keep the private
key secret).

## Theming

Three themes, chosen in **Settings → Theme** or by typing `theme`:

- **Album Art** (default) — a light gradient derived from album art washes the
  panel *behind* the glass, and the selected row carries a small accent in its
  own album's colour.
- **Album Art v2** — the same treatment, but the palette is built from
  median-cut clusters instead of a single histogram bucket. An opt-in A/B for
  covers where the classic extraction collapses several hues into one accent.
- **Tahoe** — plain Liquid Glass, unchanged.

By default the ambient gradient **follows the highlighted row** rather than the
now-playing track, fading from album to album as you move. Turn the option off to
key it to the now-playing track instead; following needs the 350 ms pause below,
because per-row tinting with no pause would strobe the whole surface on every
arrow key.

Upgrading from an earlier release moves you onto this new default **once** (Album
Art + follow the highlighted row); after that, your choice — including going back
to Tahoe — is kept.

- The wash is a **drifting mesh** (`AmbientMesh`, a 3×3 `MeshGradient`): corners
  pinned, edge midpoints sliding along their edges and the centre wandering on a
  slow Lissajous path (unrelated 14–22 s periods, so it never visibly loops). The
  light top/bottom stops sit on the outside with the cover's accent drifting
  through the middle. It only moves while music plays; `DriftClock` advances time
  only while drifting, so pausing freezes the shape in place and resuming carries
  on. A cover change crossfades whole meshes (one per palette). Reduce Motion
  keeps it still.
- `PaletteExtractor` (Core, pure + deterministic) downsamples the cached 256 px
  artwork to a 24×24 grid and picks three raw base colours, then runs them
  through a shared legibility transform. Two algorithms choose the base colours:
  **classic** averages the top/bottom thirds for the two gradient stops and picks
  the most *saturated* 4-bit histogram bucket for the accent; **clustered** runs
  deterministic median-cut quantization into `clusterBudget` (8) clusters, feeds
  the upper/lower clusters into the top/bottom stops (keeping the vertical
  gradient) and the most vivid cluster into the accent. Either way each stop
  borrows 45% of its colour from that signature colour (averaging a third of a
  *photograph* mixes hues into grey), is lifted to a **luma floor of 0.70** so a
  dark cover can't darken the panel, then has its chroma pulled into a band
  (0.16–0.40 for the wash, 0.28–0.70 for the accent) so it is never muddy or
  garish. Artwork below a chroma confidence floor falls back to plain glass.
- **Global Colours** (Album Art v2 only, **off by default**) — turns off the
  gradient: with `ClusterLayout.global` every cluster is mixed into one colour
  used for both stops, a pywal-style flat wash. Set it in Settings or via the
  `theme ` scope's "Global Colours" row; stored in
  `ThemeStore.globalClusteredColours` and folded into the `PaletteStyle`
  (algorithm + `ClusterLayout`) that keys the palette cache.
- The wash strength is `ThemeBackground.washOpacity` (default **0.36**) and the
  glass tint is `ThemeGlass.tintOpacity` (default **0.35**) — the tint is the main
  colour lever. Both are overridable at launch with `CUEBAR_WASH_OPACITY` /
  `CUEBAR_GLASS_TINT` for quick A/B.
- Type `theme ` (with a space) for a **Theme scope**, exactly like `album ` /
  `playlist `: the field shows a chip and the list holds only the theme options —
  Tahoe, Album Art, Album Art v2, and the follow-the-highlighted-row toggle.
  `SearchScope` is its own type rather than a `RankPreference`, because a theme
  scope is not a music ranking; only the music scopes map back to one.
- **Settings is keyboard-navigable** like the results list: ↑/↓ move between rows
  (the row list comes from `SettingsRow.visibleRows(theme:)`, so hiding the follow
  row can never leave the highlight dangling) and ⏎ runs the highlighted row's
  primary action. The Theme dropdown is a real `NSMenu` popped up at the row, so it
  keeps native arrow-key and Return handling inside a non-activating panel — the
  key monitor stands down while it tracks.
- The **now-playing row** carries the album tint: it keeps the system's translucent
  selection material and lays the cover's colour through it
  (`ThemeGlass.rowTintOpacity`, default **0.55**) — far more colourful than the
  original 0.28 tint while still reading as glass. Text keeps the
  appearance-adaptive system colours.
  Which rows qualify is `RowTintPolicy` — the now-playing row always, and any row
  when the option below is on.
- **Follow the Highlighted Row** (Settings → Theme, Album Art themes only; **on by
  default**): the whole panel colour follows the highlighted row instead of the
  now-playing track, with
  a **350 ms pause** before each change and a **700 ms crossfade**. The pause is
  *leading* — it is not restarted while the user keeps moving, so the colour always
  lands on the row they stop on, and while following, the **wash carries the
  colour** (the glass is untinted) so every change can actually crossfade. Rules
  and timing live in `AmbientPaletteCoordinator`, unit-tested with injected
  resolution and sleep; Reduce Motion swaps instantly.
- A **colourless cover is used as-is** — it is never replaced by the playing
  track's colour. If that cover is also **dark**, the panel switches to a dark
  scheme (`darkPanelLuma`, light-on-dark content); darkness is measured from the
  brightness *distribution*, because a black sleeve with large white type averages
  to mid grey.
- `PaletteCache` (shell) mirrors `ArtworkStore`: a synchronous lookup for the
  first frame plus an async, de-duplicated extraction keyed by album. It adds **no**
  new AppleScript traffic — the row icons already fetch the same artwork.
- `AmbientTheme` resolves the now-playing palette and is only active under Album
  Art; it keeps the previous colour until the next one is ready, so the panel
  never flashes while art loads.
- Reduce Transparency falls back to the Tahoe rendering, and Reduce Motion drops
  the crossfade.

## Feedback (toasts)

Playback outcomes are reported by a small borderless `ToastPanel` (click-through,
never key) anchored below the palette — or above it when there's no room, and
top-centre when the palette is already hidden (success closes it).

- `Toast` (Core) is the model; `Toast.Kind` sets the duration (2 s success,
  4 s error). `PlaybackFeedback` (Core) builds the copy for song/album playback,
  transport commands, and errors (via `LocalizedError.errorDescription`, so
  `PlaybackError` and `AppleScriptError` — including the permission guidance —
  come through unchanged).
- `ToastCenter` (Core, `@MainActor`) holds `current` and auto-dismisses it; the
  delay is injectable so it is unit-testable. Only one toast shows at a time; a
  newer one replaces it.
- `ToastWindowController` observes `ToastCenter.$current`, sizes the panel to the
  SwiftUI content, animates it (fade only under Reduce Motion) and posts an
  Accessibility announcement.
- **The window never resizes.** The panel is a fixed transparent canvas
  (`PaletteMetrics.toastCanvasSize`); the toast changes size *inside* it. A resize
  used to be visible — and worse, `animationBehavior = .utilityWindow` animated the
  resize, so the previous message was scaled and smeared into the new one for a few
  frames. `animationBehavior = .none` plus a fixed canvas removes both.
- The toast hugs its text: `ToastPresentation.width` is the detached
  `NSHostingView.fittingSize` width (capped at `toastMaxWidth`), so a short message
  keeps a small toast and a long one grows to the cap and wraps. The content is
  driven by an observed `ToastPresentation` instead of swapping `rootView` —
  replacing the root view makes AppKit cross-dissolve the old and new views — and
  the swap runs inside a `CATransaction` with actions disabled. The result is a
  single-frame change with no ghosting.
- The toast hugs the canvas edge nearest the palette (top when it is below, bottom
  when above), so the panel is positioned from that edge and the toast's height
  never enters the maths. It draws its own shadow (the window's shadow is off,
  since a transparent canvas would cast a rectangle), so the panel needs no rounded
  layer mask.
- `PaletteModel` emits toasts through `onToast` before `onClose`, so the panel
  frame is still available for anchoring. `shuffle` toggles read
  `MusicController.shuffleEnabled()` first so the toast reports the new state.

## Album artwork

Library artwork comes from Music.app itself (`raw data of artwork 1 of <track>`),
so it works offline and also for the currently playing track. Catalog results use
their iTunes artwork URL. Every image is cached by `ArtworkStore`:

- in memory (`NSCache`) **and** on disk at
  `~/Library/Application Support/Cuebar/artwork/`
- downscaled to a 256 px JPEG (~20–25 KB each)
- keyed by album (`artist + album`), so one fetch covers a whole album and every
  later display is instant, including after a relaunch

Art is fetched when a row first appears (so it is eager for visible rows, lazy
otherwise) and is always clipped to the rounded tile.

## Settings

Settings is an **embedded screen inside the palette** (like Raycast) — the same
glass panel, no separate window. Open it by typing `settings`, `preferences` or
`hotkey`, or with **⌘,**.

It currently has one entry, **Launch Hotkey**:

- Click the combo (or press **Return**) to record — the next key combination is
  captured and must include ⌘, ⌥ or ⌃.
- If another app already owns the shortcut, Cuebar says so and keeps the old one.
- **Reset** restores the default ⌘⌥Space.
- Changes apply immediately and persist in `UserDefaults`.

## Architecture

```
Sources/CuebarCore/          # testable, no UI
  MusicCandidate.swift       # result model (+ normalized fields)
  TextNormalizer.swift       # folding/punctuation normalization
  Similarity.swift           # Damerau–Levenshtein
  Ranking.swift              # deterministic scoring (+ RankPreference)
  SearchQuery.swift          # parses an optional leading/trailing album/playlist scope
  LibraryResolver.swift      # maps a catalog item onto a library track (title + artist only)
  LibraryAlbumIndex.swift    # groups library songs into playable albums
  LibraryBrowse.swift        # random album/playlist list for empty scopes
  RecentlyPlayed.swift       # played-date parsing + the home screen's recent shelf
  PlayHistory.swift          # Music playerInfo events + persisted log of plays
  Toast.swift                # transient feedback model (+ per-kind duration)
  PlaybackFeedback.swift     # toast copy for playback outcomes
  ToastCenter.swift          # current toast + auto-dismiss (injectable timing)
  NowPlayingProgress.swift   # interpolated progress position between polls
  AppVersion.swift           # semver parse + compare
  UpdateInfo.swift           # release model + check result
  UpdateChecker.swift        # GitHub releases/latest client
  ReleaseVerifier.swift      # Ed25519 verification + embedded public key
  SwapScript.swift           # pure builder for the bundle swap script
  UpdatePreferenceStore.swift# auto-check flag (UserDefaults)
  UpdateFeedback.swift       # update toasts
  OnboardingStore.swift      # first-run completion flag (UserDefaults)
  ThemeID.swift              # Tahoe / Album Art / Album Art v2
  ThemeStore.swift           # chosen theme + options (UserDefaults)
  ThemeColor.swift           # sRGB value type + saturation/blend helpers
  AlbumPalette.swift         # top/bottom/accent stops + usability
  PaletteExtractor.swift     # artwork pixels -> legible palette (classic + clustered, pure)
  Command.swift              # Command + CommandParser
  CommandCatalog.swift       # command entries + typed matching
  CommandExecutor.swift      # applies commands to a MusicController
  PaletteItem.swift          # command-or-song result item + composer
  MusicController.swift      # protocol + AppleScript implementation
  AppleScriptRunner.swift    # serialized NSAppleScript → async/await
  NowPlayingTrack.swift      # current track model + script parsing
  ArtworkStore.swift         # disk + memory album-art cache
  AppleScriptArtworkProvider.swift
  HotKeyPreference.swift     # launch-hotkey model + modifier formatting
  HotKeyStore.swift          # hotkey persistence (UserDefaults)
  SearchProviders.swift      # LibrarySearchProvider, ITunesCatalogProvider
  SearchService.swift        # library-first orchestration, debounced catalog
  LibraryIndex.swift         # disk cache
  AppleScriptLibraryProvider.swift

Sources/Cuebar/              # AppKit/SwiftUI shell
  CuebarMain.swift           # agent-app entry point
  AppDelegate.swift          # hotkey, status item, library index lifecycle
  HotKeyManager.swift        # Carbon ⌘⌥Space (no Accessibility permission)
  PalettePanel.swift         # borderless non-activating NSPanel
  PaletteWindowController.swift
  PaletteModel.swift         # presentation state
  PaletteView.swift          # Liquid Glass container
  ResultRowView.swift
  NowPlayingCardView.swift   # large now-playing card (progress + controls)
  UpdateController.swift     # check / download / verify / swap / relaunch
  PaletteCache.swift         # extracts + memoises album palettes
  AmbientTheme.swift         # now-playing artwork -> ambient wash
  ThemeBackground.swift      # the wash drawn behind the glass
  SearchScopeChip.swift      # in-field album/playlist scope chip
  OnboardingView.swift       # first-run wizard
  ArtworkView.swift          # rounded album-art tile
  ToastView.swift            # toast content (glass)
  ToastPanel.swift           # borderless click-through toast panel
  ToastWindowController.swift# anchors + animates the toast
  WaveformView.swift         # Spotify-style now-playing equalizer
  SettingsView.swift         # embedded settings screen
  KeyHint.swift              # footer key hints
  Support/PaletteMetrics.swift  # shared corner radius + panel size
  Support/KeyEventTranslator.swift
```

The palette is a borderless `NSPanel` (`.nonactivatingPanel`, `canBecomeKey`)
hosting SwiftUI. Because a borderless window is square, the hosting view sits in
a container whose layer is rounded (`cornerRadius`, `cornerCurve = .continuous`,
`masksToBounds`), and the SwiftUI content is clipped with a matching
`.clipShape`; `invalidateShadow()` makes the window shadow follow the rounded
shape. Glass is applied once to the container via `.glassEffect(...)` — never to
list rows, per Apple's guidance. The corner radius and panel size live in
`PaletteMetrics` so AppKit and SwiftUI can't drift. Up/Down/Return/Escape are
handled by a local key monitor so they work even while the text field has focus.

## Development helpers (`#if DEBUG` only)

| Variable | Effect |
|---|---|
| `CUEBAR_SHOW_ON_LAUNCH=1` | open the palette on launch |
| `CUEBAR_PREVIEW_QUERY="hey jude"` | pre-fill a query |
| `CUEBAR_SNAPSHOT=/tmp/panel.png` | render the panel to PNG and quit |
| `CUEBAR_SNAPSHOT_DELAY=4` | seconds to wait before the snapshot (default 1.2) |
| `CUEBAR_TOAST_TEST=1` | fire a long then a short toast (`CUEBAR_TOAST_LONG`, `CUEBAR_TOAST_SHORT`, `CUEBAR_TOAST_GAP`) |
| `CUEBAR_FORCE_PLAYING=1` | treat the current track as playing (capture the equalizer) |
| `CUEBAR_OPEN_SETTINGS=1` / `=recording` | open the Settings screen (optionally while recording) |

```sh
CUEBAR_SHOW_ON_LAUNCH=1 CUEBAR_PREVIEW_QUERY="take" \
  CUEBAR_SNAPSHOT=/tmp/panel.png ./build/Cuebar.app/Contents/MacOS/Cuebar
```

The snapshot uses offscreen AppKit rendering, so backdrop glass materials are
not captured, but layout, rows and text are.

## Tests

`make test` runs the full suite (~300 unit tests) covering the play history log
(notification parsing, persistence, merging with Music's dates), the recently
played shelf (parsing, ordering, exclusions, relative labels, home composition),
command parsing, command matching (including that `play take on me` matches no
command), now-playing parsing (incl. shuffle/repeat) and progress interpolation,
list composition, artwork cache keys/persistence, the launch-hotkey preference
(formatting, validation, persistence), the onboarding flag and Automation
permission mapping,
version parsing/comparison, the GitHub update check + Ed25519 verification +
swap script + update preference, the theme palette (colour clamping, legibility
transform, colourless-artwork fallback, determinism, and both the classic and
median-cut-clustered algorithms) and the theme preference, catalog-to-library
resolution (never
substituting a same-title track by a different artist), album grouping/ordering,
scope browse lists, the `album`/`playlist` scope keywords, library parsing
(album artist/disc/track and playlists), repeat modes, toast copy and
auto-dismissal, ranking (the exact-song-over-album rule, library preference,
typo tolerance, album/playlist preference and deterministic ordering), command
execution and the library-first/catalog-fallback search flow.
