# Plan 8 — Repeat commands

Status: **implemented.** Companions: `plan.md` (MVP), `plan2.md` (rounded
corners + commands), `plan3.md` (now playing), `plan4.md` (catalog → library),
`plan5.md` (never play the wrong track), `plan6.md` (album playback),
`plan7.md` (feedback toasts).

---

## Goal

Add repeat controls to the command palette:

- **`repeat queue`** — repeat the whole queue (`song repeat` = `all`).
- **`repeat track`** — repeat the current track (`song repeat` = `one`).
- **`repeat off`** — stop repeating.

## Feasibility

Music's scripting dictionary exposes `song repeat` (`eRpt`: `off` / `one` /
`all`), writable via AppleScript, so this is fully controllable — unlike
Automix. Verified with `osacompile` for all three set forms.

## Implementation

- **`Command`** (`Sources/CuebarCore/Command.swift`): added `RepeatMode`
  (`off`/`all`/`one`) and `case setRepeat(RepeatMode)`. `CommandParser` maps
  `repeat queue` (aliases all, playlist) / `repeat track` (aliases one, song) /
  `repeat off` (alias none); a bare `repeat` parses to nil, so it just surfaces
  the three rows instead of searching.
- **`CommandCatalog`**: three rows — `repeat.queue`, `repeat.track`,
  `repeat.off`.
- **`MusicController`**: `setRepeat(_:)` (`set song repeat to off|all|one`).
- **`CommandExecutor`**: applies `setRepeat`.
- **`PlaybackFeedback`**: `repeatMode(_:)` → "Repeat off / queue / track".
- Tests + `MockMusicController.setRepeat`.

## Tests

- `CommandParser`: every repeat spelling/alias, case-insensitive; bare `repeat`
  → nil.
- `CommandCatalog`: bare `repeat` surfaces exactly the three rows; `repeat
  queue`/`track`/`off` → the exact rows.
- `CommandExecutor`: `setRepeat` calls.
- `PlaybackFeedback`: repeat copy.

`make test`: **125** passing.

## History

An earlier revision added a bare `repeat` *cycle* (off → queue → track → off)
using a read of Music's current repeat mode. It didn't behave as expected in
practice, so it was **removed**; only the three explicit commands remain, and
the `repeatMode()` read-back method is gone.

## Out of scope

- A persistent Cuebar default for repeat mode.
- Reflecting Music's repeat state in the UI (no repeat indicator on the
  now-playing row yet).
