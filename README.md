# Cuebar

A Spotlight-style command palette for Apple Music on macOS.

Press **⌘⌥Space**, type a song name or a command, hit **Return**.

Cuebar is a small, keyboard-first menu that drives the Music app. Find and play
anything in your library, skip tracks, flip shuffle, and see what's playing —
without leaving whatever you were doing.

```
⌘⌥Space  →  "take on me"  →  ⏎
```

---

## Features

- **Play anything in your library by name** — instant, fuzzy and offline.
- **Play a library album start to finish** — search the album (`after hours
  album`), Return loads its tracks in order with shuffle off.
- **Play a library playlist** — `playlist focus` (or `focus playlist`) searches
  your playlists and plays the chosen one directly.
- **Clear feedback** — a small glass toast confirms what's playing or explains
  an error (not in your library, missing Automation permission).
- **Self-updating** — checks GitHub on launch; when a signed release is newer it
  can download, verify and relaunch into it (`update`).
- **Themes** — Tahoe (plain glass) or Album Art, which tints the panel with the
  now-playing cover in a slowly drifting gradient while music plays. Pick one in Settings, or type `theme ` for a Theme filter.
- **What's New** — after an update, a short screen lists the three most important
  changes since the version you were running.
- **Apple Music catalog fallback** — when a song isn't in your library, Cuebar
  still finds it and says so, instead of silently playing the wrong track.
- **Typo tolerant** — `blinding lites` still finds *Blinding Lights*.
- **Transport commands** — `pause`, `resume`, `next`, `previous`, `shuffle`,
  `repeat`.
- **Home screen** — open Cuebar and the current track shows up at the top in a
  large card with glowing artwork, a progress bar, and clickable play/pause,
  shuffle and repeat (**Return** toggles play/pause), followed by your **Recently
  Played** songs.
- **Album artwork**, cached on disk so it appears instantly, even offline.
- **Configurable global hotkey**, recorded from an embedded settings screen.
- **Keyboard-first Liquid Glass UI** — no Dock icon, no clutter.

## Requirements

- macOS 26 (Tahoe) or later
- The Music app with something in your library
- An Apple Music subscription only if you want catalog fallback

## Install

Cuebar is built from source (it isn't notarised):

```sh
git clone <your-repo-url> cuebar
cd cuebar
make run
```

`make run` compiles the app, assembles `build/Cuebar.app`, and launches it. On
first launch, Cuebar shows a short **onboarding** (welcome → grant access →
ready). On first use, macOS asks once for permission to control **Music** (System
Settings › Privacy & Security › Automation).

## Usage

Press **⌘⌥Space** from anywhere, then type:

| Input | What happens |
|---|---|
| `take on me` | Plays the best match (the song, if one shares the name) |
| `take on me album` | Prioritises the matching **album**; plays it start to finish |
| `focus playlist` · `playlist focus` | Prioritises your **playlists**; plays the chosen one |
| `play take on me` | The same, explicit |
| `pause` / `resume` | Pause / resume playback |
| `next` / `previous` | Skip tracks |
| `shuffle` · `shuffle on` · `shuffle off` | Toggle or set shuffle |
| `repeat queue` · `repeat track` · `repeat off` | Repeat the queue, the track, or nothing |
| `rebuild` · `reindex` | Re-scan your Music library and toast the result |
| `settings` | Open Cuebar's settings |

Typing `album` or `playlist` plus a space turns it into a scope chip in the
search box (e.g. `[ Playlist › ]`) — the field then searches only that term in
scope. With the scope active and nothing typed, Cuebar shows a **random
selection of albums/playlists to browse**; type to filter. **⌫** on an empty
field, **Esc**, or clicking the chip clears it.

`↑` / `↓` move through results, `Return` runs the selected row, `Esc` closes the
palette. The search field supports the usual editing shortcuts (`⌘A`, `⌘C`,
`⌘V`, `⌘X`, `⌘Z`).

## Settings

Settings live **inside the same panel** — open them with **⌘,** or by typing
`settings`. There are two options:

**Launch Hotkey**

- click the shortcut (or press **Return**) to record a new one
- the combination must include ⌘, ⌥ or ⌃
- if another app already owns it, Cuebar says so and keeps the previous one
- **Reset** restores ⌘⌥Space
- changes apply immediately and persist across launches

**Show Onboarding Again** — replay the first-run tour.

## How it works

- A global hotkey opens a borderless, Liquid Glass panel hosting SwiftUI.
- Your library is indexed once at launch through AppleScript and cached to disk,
  so searching is instant and works offline.
- Results are ranked deterministically: exact titles first, library before
  catalog, songs before albums, with fuzzy matching for typos. Ending the query
  with `album` (or `playlist`) flips that — the chosen kind first — and the
  keyword isn't searched.
- Library albums are grouped from their tracks (album + album artist, ordered by
  disc then track). Playing one loads a reusable **Cuebar Queue** playlist in
  Music with shuffle off, so it runs start to finish.
- Library playlists are indexed too (by persistent ID, so duplicate names are
  safe) and played directly; shuffle is left as-is. Cuebar's own queue playlist
  and Music's system playlists are excluded.
- Catalog results that also exist in your library are played from the library.
  A catalog item is only mapped onto a library track when the **title and
  artist** agree; a same-title track by a different artist is never substituted.
  Songs that exist **only** in Apple Music are shown with a note rather than
  played, because macOS gives third-party apps no supported way to start catalog
  playback without a MusicKit entitlement (see below).
- Playback is driven by AppleScript, so transport controls affect the real,
  system-wide Music player.
- Outcomes are reported by a small borderless **toast** anchored below the
  palette: playback/transport confirmations and errors (including the Automation
  permission guidance), announced to VoiceOver and dismissed automatically.

### Why AppleScript instead of MusicKit?

The API you'd normally use to control the Music app, `SystemMusicPlayer`, is
explicitly unavailable on macOS:

```
error: 'SystemMusicPlayer' is unavailable in macOS
note: 'SystemMusicPlayer' has been explicitly marked unavailable here
      @available(macOS, unavailable)
```

That leaves `ApplicationMusicPlayer` (which plays audio *inside* the app rather
than in Music, and needs a MusicKit entitlement) or AppleScript. Cuebar uses
AppleScript so that play/pause/skip affect the actual Music app. Playback sits
behind a `MusicController` protocol, so a MusicKit implementation could be added
later without touching the rest of the app.

## Privacy

Cuebar runs entirely on your Mac. Your library, playback state and artwork are
read locally from the Music app. The only network requests are to Apple's public
iTunes Search API, and only when a song isn't found in your library. Nothing is
sent anywhere else and nothing is collected.

## Project layout

```
Sources/CuebarCore/   # search, ranking, Music/AppleScript control, caches (no UI)
Sources/Cuebar/       # AppKit + SwiftUI shell: hotkey, panel, settings
Tests/                # unit tests (swift test)
Scripts/              # build + icon generation
Resources/            # Info.plist, generated app icon
```

## Development

```sh
make app     # build + assemble build/Cuebar.app
make run     # build, assemble and launch
make test    # run the unit tests
make icon    # regenerate the app icon
```

See [README.dev.md](README.dev.md) for architecture notes, debug helpers and the
full test inventory.

## License

No license has been chosen yet; all rights are reserved by the author.
