# Plan 14 — Rich now-playing card

Status: **implemented.** Companions: plan.md … plan13.md.

Implemented in this iteration:

- **`NowPlayingCardView`** — a larger card with artwork, equalizer +
  Playing/Paused, a progress bar, and clickable **play/pause · shuffle · loop**.
- **`NowPlayingProgress`** (Core, pure) interpolates the position between polls
  (frozen when paused) so the bar is smooth with no extra AppleScript.
- `NowPlayingTrack` gains `shuffleEnabled` + `repeatMode`; the now-playing script
  reads `shuffle enabled` and `song repeat`. `RepeatMode.togglingAll` backs the
  loop button (off ↔ all).
- `PaletteModel.togglePlayPause/toggleShuffle/toggleRepeat` update optimistically
  then reconcile; card controls keep the palette open.
- Footer shows **"⏎ play/pause"** when the card is selected.
- Tests: **163** passing (was 152). Verified with an offscreen snapshot.

> Loop control worth re-checking live: `song repeat` read/write wasn't re-run
> during implementation, so confirm the button changes Music's loop state.

---

## Goal

Turn the now-playing row into a **bigger card** at the top of the palette (when
the box is empty) with:

- artwork + title + artist/album;
- a **progress bar** with elapsed / total time;
- a clear **playing / paused** indicator (the animated equalizer);
- **shuffle** and **loop (repeat)** status;
- **mouse-clickable** play/pause, shuffle and loop buttons;
- while **Return still toggles play/pause** as the primary action, surfaced as a
  *"⏎ play/pause"* hint in the bottom bar.

## Feasibility

- **Position/duration** already come from `NowPlayingTrack`; the panel polls
  now-playing every 1.5 s. For a smooth bar we interpolate locally between polls
  (no extra AppleScript).
- **Shuffle state** is already readable (`MusicController.shuffleEnabled()`).
- **Loop state** needs re-adding a *read* of `song repeat`: `repeatMode()` was
  removed in plan8, and `NowPlayingTrack` doesn't carry it. The dictionary
  supports `song repeat` (`off`/`one`/`all`), and we already validated the set
  commands with `osacompile`.
- Music's AppleScript has **no separate "toggle repeat"**, so the loop button
  cycles via read → set. ⚠️ Wiring it live is the one thing to re-validate (the
  plan8 cycle "didn't behave" and was removed).
- Mouse clicks already work in the palette (`ResultRowView` uses tap gestures),
  so clickable controls just need careful gesture handling.

## Model

- **`NowPlayingTrack`** gains `shuffleEnabled: Bool` and `repeatMode: RepeatMode`;
  `parse` reads two new fields (tolerating older/short output).
- **`MusicController.nowPlayingScript`** appends `shuffle enabled` and `song repeat`.
- **`RepeatMode.togglingAll`** (off ↔ all) backs the loop button.
- New **`NowPlayingProgress`** (Core, pure): given `position`, `duration`,
  `isPlaying`, the poll timestamp and "now", returns the **interpolated,
  clamped** position — so the bar advances smoothly between 1.5 s polls and
  freezes when paused.

## Shell

- New **`NowPlayingCardView`** (replaces the `.nowPlaying` case in the list):
  - artwork ~58 pt, title (16 medium), subtitle (12 secondary);
  - **progress bar** + `m:ss` elapsed / total labels;
  - `WaveformView` (non-compact) + "Playing/Paused";
  - three controls — **play/pause**, **shuffle**, **loop** — as `.plain`
    buttons; shuffle/loop tinted with the accent when active, loop shows
    `repeat` / `repeat.1` for all/one;
  - the card keeps the normal selected-row background so Return still works.
- `PaletteView`: render `NowPlayingCardView` for the `.nowPlaying` item (rest of
  the list unchanged), and use a `TimelineView(.periodic 0.5 s)` for the bar.
- `PaletteModel`: `lastPollDate` (set in `refreshNowPlaying`), `togglePlayPause()`,
  `toggleShuffle()`, `cycleRepeat()` — each does an **optimistic** local update
  (flip `isPlaying` / shuffle / repeat) then calls the existing `CommandExecutor`
  (`.pause`/`.resume`, `.shuffle(.toggle)`, `.setRepeat`). The next poll
  reconciles.
- **Loop button = off ↔ all:** tap sets `all` when off, otherwise `off`. It
  shows **active** whenever the mode isn't `off`; if Music is in `one` (set
  elsewhere) it displays `repeat.1` and tapping turns it off.
- `PaletteMetrics`: card constants (artwork size, card height, bar height).
- **No toasts** for these controls — the card itself is the feedback.

## Keyboard / footer

- Return on the selected card toggles play/pause (unchanged behaviour; the card
  is index 0 when the box is empty).
- Footer: when the **now-playing card is selected**, show `⏎ play/pause` in place
  of `⏎ run`; otherwise `⏎ run` as today.
- Mouse: clicking the card body selects it; clicking a control runs that action
  without disturbing the selection (buttons consume the tap).

## Files

- **New** `Sources/CuebarCore/NowPlayingProgress.swift`
- **New** `Sources/Cuebar/NowPlayingCardView.swift`
- **New** `Tests/CuebarCoreTests/NowPlayingProgressTests.swift`
- `Sources/CuebarCore/NowPlayingTrack.swift` — shuffle/repeat fields + parse
- `Sources/CuebarCore/Command.swift` — re-add `RepeatMode.next`
- `Sources/CuebarCore/MusicController.swift` — richer now-playing script
- `Sources/Cuebar/PaletteModel.swift` — poll timestamp + control actions
- `Sources/Cuebar/PaletteView.swift` — card + progress TimelineView + footer hint
- `Sources/Cuebar/Support/PaletteMetrics.swift` — card metrics
- `Tests/CuebarCoreTests/NowPlayingTests.swift` — extended parse
- `README.md` / `README.dev.md`

## Tests

- `NowPlayingTrack.parse`: with and without the new shuffle/repeat fields;
  `missing value` tolerated.
- `NowPlayingProgress`: interpolation while playing; frozen when paused; clamped
  to `[0, duration]`; missing duration → no bar.
- `RepeatMode.togglingAll`: off → all; all → off; one → off.
- Existing 152 tests stay green.

## Manual / validation

1. **Re-validate loop control**: set `song repeat` from the button and confirm
   Music actually changes loop mode (the earlier cycle was removed as flaky).
2. Progress bar advances smoothly while playing and freezes when paused.
3. Shuffle/loop buttons reflect and change the real Music state.
4. Return on the card toggles play/pause; footer shows "⏎ play/pause".

## Decisions locked with the user

1. **Loop button = off ↔ all.** Tap sets repeat-all when off, otherwise off.
   (It still *displays* `repeat.1` if Music is already in repeat-one, and tapping
   then turns it off.)
2. **Footer hint is contextual** — "⏎ play/pause" only while the card is
   selected; other rows keep "⏎ run".
3. **Mouse-only** for shuffle/loop; the keyboard stays navigation + Return.

## Out of scope

- Scrubbing/seek by dragging the progress bar (read-only bar for now).
- Clicking the card body to toggle (only the button does that).
- Volume/AirPlay controls on the card.
