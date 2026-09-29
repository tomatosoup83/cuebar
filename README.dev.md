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

With an empty box the palette shows the **current Music.app track** at the top
with a Spotify-style animated 4-bar equalizer while it plays ("Paused" with
static bars otherwise), so it is useful the moment it opens. Return on that row
toggles play/pause; typing anything hides it.

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
| `CUEBAR_FORCE_PLAYING=1` | treat the current track as playing (capture the equalizer) |
| `CUEBAR_OPEN_SETTINGS=1` / `=recording` | open the Settings screen (optionally while recording) |

```sh
CUEBAR_SHOW_ON_LAUNCH=1 CUEBAR_PREVIEW_QUERY="take" \
  CUEBAR_SNAPSHOT=/tmp/panel.png ./build/Cuebar.app/Contents/MacOS/Cuebar
```

The snapshot uses offscreen AppKit rendering, so backdrop glass materials are
not captured, but layout, rows and text are.

## Tests

`make test` runs 178 unit tests covering command parsing, command matching
(including that `play take on me` matches no command), now-playing parsing
(incl. shuffle/repeat) and progress interpolation, list composition, artwork
cache keys/persistence, the launch-hotkey preference (formatting, validation,
persistence), the onboarding flag and Automation permission mapping,
version parsing/comparison, the GitHub update check + Ed25519 verification +
swap script + update preference, catalog-to-library resolution (never
substituting a same-title track by a different artist), album grouping/ordering,
scope browse lists, the `album`/`playlist` scope keywords, library parsing
(album artist/disc/track and playlists), repeat modes, toast copy and
auto-dismissal, ranking (the exact-song-over-album rule, library preference,
typo tolerance, album/playlist preference and deterministic ordering), command
execution and the library-first/catalog-fallback search flow.
