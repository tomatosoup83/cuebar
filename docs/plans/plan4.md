# Plan 4 — Catalog playback correctness + editing shortcuts

Status: implementing. Companions: `plan.md` (MVP), `plan2.md` (rounded corners +
commands as results), `plan3.md` (now playing + launch state).

---

## Problems

1. **Selecting a catalog result plays the wrong track.** Picking a song from the
   Apple Music catalog makes Music keep playing whatever was already there
   instead of the selected song.
2. **⌘A doesn't select all** in the search field (and neither do the other
   standard editing shortcuts).

## Root cause 1 — catalog playback

Catalog playback relied on:

```applescript
tell application "Music" to open location "https://music.apple.com/…"
```

Two things were verified on the machine:

- Music defines its **own** `open location` command (`GURLGURL`, *"Opens an
  iTunes Store or audio stream URL"*). It opens the **store page**; it does not
  start playback.
- LaunchServices routes plain `https://music.apple.com/…` to **Safari**, not
  Music.

The net effect: Music ignores the request and its existing queue keeps playing —
which is exactly the "wrong track". Measured directly: after `open location`,
`player state`/`current track` reported the queue's track (e.g. *SAVE YOURSELF*),
never the requested song. Trying `music://`, `itms://`, `itmss://`, forcing
`open -a Music`, and even quitting Music and relaunching it *with* the URL all
failed to start the requested song.

There is no AppleScript path to play a catalog song: Music's `search` command can
only search **playlists** (`only` accepts albums/artists/composers/names/all —
no catalog), and `SystemMusicPlayer`/MusicKit are unavailable (no signing
identity or entitlement on this machine).

### Fix

- **New `LibraryResolver` (Core)**: maps a catalog item onto the user's library
  track — exact normalized title (+ artist agreement), then a near-title match
  with matching artist. Conservative: never guesses between different covers.
- `PaletteModel` resolves a catalog selection against the library index and
  plays the **library** track by persistent ID (reliable, offline).
- If the song genuinely isn't in the library, Cuebar shows a clear message and
  **does not touch playback**, so the current track is never replaced by the
  wrong song.
- `AppleScriptMusicController.play` no longer calls `open location`; it only
  plays library tracks by persistent ID.

## Root cause 2 — ⌘A

AppKit dispatches ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z through the main menu's Edit items.
Cuebar is a borderless agent app (`LSUIElement`) with **no main menu**, so nothing
ever invokes `selectAll:` on the field editor.

### Fix

The palette's local key monitor handles the standard editing shortcuts by
sending the standard selector down the responder chain
(`NSApp.sendAction(_:to:from:)`), and undo/redo through the window's undo manager.
Unhandled events still pass through, so nothing else is affected.

---

## Files

- **New** `Sources/CuebarCore/LibraryResolver.swift`
- **New** `Tests/CuebarCoreTests/LibraryResolverTests.swift`
- `Sources/CuebarCore/MusicController.swift` — play by persistent ID only; add
  `PlaybackError`
- `Sources/Cuebar/PaletteModel.swift` — library resolution + not-in-library message
- `Sources/Cuebar/PaletteWindowController.swift` — editing shortcuts; pass the
  library provider
- `Sources/Cuebar/AppDelegate.swift` — wire the library provider through

## Tests

- `LibraryResolver`: exact title + artist match; exact title, artist unknown;
  ambiguous same-title rows with mismatched artists resolve to nil; typo title
  with matching artist resolves; unrelated songs don't resolve; library items
  pass through unchanged.
- Existing **65** tests stay green.
