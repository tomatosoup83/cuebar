# Cuebar — Plan 3: Now Playing row + commands shown on launch

Status: implementing. Companions: `plan.md` (MVP), `plan2.md` (rounded corners +
commands as results).

---

## Problems

1. **Empty box on launch.** Opening the palette shows a blank list with
   "No matches". Typing something and deleting it then shows the command menu.
   - Cause: `PaletteModel.reset()` clears `items`, and the view only recomputes
     from `.onChange(of: model.query)`. On open `query` is already `""`, so no
     change fires and `items` stays empty.
2. **No indication of what's playing.** The palette does not surface the current
   Music.app track.

## Goals

- Populate the empty state on launch exactly as it appears after deleting text:
  all commands, plus the current track.
- Show the **currently loaded track** (playing *or* paused) as a selectable row
  at the top, only when the search box is empty.
- Indicate playback with an **animated SF Symbol waveform**.
- **Return** on that row toggles play/pause.
- The row disappears as soon as anything is typed.

---

## Design

### `NowPlayingTrack` (new, `CuebarCore`)

```
state: playing | paused | stopped
title, artist, album
persistentID, position, duration
```

`NowPlayingTrack.parse(_:)` decodes one unit-separator-delimited AppleScript
string and returns `nil` when there is no current track. Pure and testable.

### AppleScript (validated on the user's machine)

```applescript
tell application "Music"
    set sep to (ASCII character 31)
    set theState to (player state as string)
    try
        set t to current track
    on error
        return ""
    end try
    set theID  to ""
    set thePos to ""
    set theDur to ""
    try
        set theID to persistent ID of t
    end try
    try
        set thePos to player position as string
    end try
    try
        set theDur to duration of t as string
    end try
    return theState & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & theID & sep & thePos & sep & theDur
end tell
```

Reading `current track` regardless of state is what lets paused/stopped tracks
show too.

### `MusicController.nowPlaying()`

New protocol requirement. The AppleScript implementation first checks
`NSWorkspace` for `com.apple.Music` so opening the palette never *launches*
Music, then runs the script and parses it. Returns `nil` when unavailable.

### Composition

`PaletteListComposer.compose(query:nowPlaying:commands:music:)`:

- query empty → `[nowPlaying?, commands…]`
- query non-empty → `[command matches…, song results…]` (no now-playing row)

### Launch fix

`PaletteWindowController.show()` calls `model.reset()` then `model.queryChanged()`,
so the empty state is populated on open exactly like after deleting text.

### Polling

While the panel is visible, a task refreshes now-playing every ~1.5 s (cheap; the
AppleScript call is skipped entirely when Music isn't running). Cancelled on hide.

### Row UI

- Icon: a Spotify-style **4-bar equalizer** inside the rounded tile —
  `TimelineView(.animation)` drives a phase-shifted sine so the bars form a
  travelling wave while playing; a fixed pattern is shown while paused/stopped,
  and the whole thing is gated by `accessibilityReduceMotion`.
- Title + `artist · album`, and a **"Now Playing"** / **"Paused"** badge.
- Return → `.pause` when playing, `.resume` when paused (via `CommandExecutor`).

> The indicator started as an SF Symbol `waveform` with
> `.symbolEffect(.variableColor.iterative)` and was replaced with the custom
> equalizer at the user's request (`Sources/Cuebar/WaveformView.swift`).

### Small tweak

Relabel the Resume command entry to **"Play / Resume"** so typing `play` surfaces
something labelled `Play`.

---

## Files

- **New** `Sources/CuebarCore/NowPlayingTrack.swift`
- `Sources/CuebarCore/MusicController.swift` — `nowPlaying()` + script + NSWorkspace guard
- `Sources/CuebarCore/PaletteItem.swift` — `.nowPlaying` case + composer signature
- `Sources/CuebarCore/CommandCatalog.swift` — Resume → "Play / Resume"
- `Sources/Cuebar/PaletteModel.swift` — now-playing state, `refreshNowPlaying()`, Return action
- `Sources/Cuebar/PaletteWindowController.swift` — populate on show, poll start/stop
- `Sources/Cuebar/ResultRowView.swift` — now-playing row + animated waveform
- **New** `Tests/CuebarCoreTests/NowPlayingTests.swift`
- `Tests/CuebarCoreTests/Mocks.swift` — `MockMusicController.nowPlaying()`
- `Tests/CuebarCoreTests/CommandCatalogTests.swift` — composer signature update

---

## Tests

- `NowPlayingTrack.parse`: playing with all fields; paused; stopped; empty; a
  state-only string; short/malformed input.
- Composer: now-playing first when the query is empty; absent when non-empty;
  commands precede songs.
- `MockMusicController.nowPlaying()`.
- Existing 36 tests stay green.
