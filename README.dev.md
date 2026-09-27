# Cuebar

A Spotlight/Raycast-style command palette for Apple Music on macOS.

Press **⌘⌥Space**, type a song name or a command, press **Return**.

```
play take on me     → finds and plays the song
pause / resume
next / previous
shuffle [on|off]
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
**Open Cuebar**, **Rebuild Library Index** and **Quit**.

## First run

macOS asks once for permission to control **Music** (System Settings › Privacy
& Security › Automation). Until it is granted, playback and library indexing
report a clear error.

The library index is built on first launch (about 0.26 s for a 6k-track library)
and cached at `~/Library/Application Support/Cuebar/library-index.json`, so
later launches are instant. Use **Rebuild Library Index** from the menu-bar item
after adding music.

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

Typo tolerance is included: `blinding lites` resolves to *Blinding Lights*.

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
  Ranking.swift              # deterministic scoring
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
  ArtworkView.swift          # rounded album-art tile
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

`make test` runs 65 unit tests covering command parsing, command matching
(including that `play take on me` matches no command), now-playing parsing and
list composition, artwork cache keys/persistence, the launch-hotkey preference
(formatting, validation, persistence), ranking (the exact-song-over-album rule,
library preference, typo tolerance and deterministic ordering), command
execution and the library-first/catalog-fallback search flow.
