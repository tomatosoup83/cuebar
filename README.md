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

- **Play anything by name** — your library first, the Apple Music catalog as a
  fallback.
- **Typo tolerant** — `blinding lites` still finds *Blinding Lights*.
- **Transport commands** — `pause`, `resume`, `next`, `previous`, `shuffle`.
- **Now playing** — the current track shows up at the top with an animated
  equalizer; **Return** toggles playback.
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
first use, macOS asks once for permission to control **Music** (System Settings ›
Privacy & Security › Automation).

## Usage

Press **⌘⌥Space** from anywhere, then type:

| Input | What happens |
|---|---|
| `take on me` | Plays the best match |
| `play take on me` | The same, explicit |
| `pause` / `resume` | Pause / resume playback |
| `next` / `previous` | Skip tracks |
| `shuffle` · `shuffle on` · `shuffle off` | Toggle or set shuffle |
| `settings` | Open Cuebar's settings |

`↑` / `↓` move through results, `Return` runs the selected row, `Esc` closes the
palette.

## Settings

Settings live **inside the same panel** — open them with **⌘,** or by typing
`settings`. There's currently one option, **Launch Hotkey**:

- click the shortcut (or press **Return**) to record a new one
- the combination must include ⌘, ⌥ or ⌃
- if another app already owns it, Cuebar says so and keeps the previous one
- **Reset** restores ⌘⌥Space
- changes apply immediately and persist across launches

## How it works

- A global hotkey opens a borderless, Liquid Glass panel hosting SwiftUI.
- Your library is indexed once at launch through AppleScript and cached to disk,
  so searching is instant and works offline.
- Results are ranked deterministically: exact titles first, library before
  catalog, songs before albums, with fuzzy matching for typos.
- Playback is driven by AppleScript, so transport controls affect the real,
  system-wide Music player.

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
