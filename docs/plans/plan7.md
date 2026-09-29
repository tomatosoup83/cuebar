# Plan 7 — Notification toast system

Status: **implemented.** Companions: `plan.md` (MVP), `plan2.md` (rounded
corners + commands), `plan3.md` (now playing), `plan4.md` (catalog → library),
`plan5.md` (never play the wrong track), `plan6.md` (album playback).

Implemented in this iteration:

- Core `Toast` (+ per-kind duration), `PlaybackFeedback` (song/album/transport
  copy and error mapping), and `ToastCenter` (current toast + injectable
  auto-dismiss).
- Shell `ToastView` / `ToastPanel` / `ToastWindowController`: a borderless,
  click-through, glass toast anchored below the palette (above if no room,
  top-centre when the palette is gone), fade-animated (respects Reduce Motion)
  and announced to VoiceOver.
- `PaletteModel.onToast` reports song/album success, transport commands, and
  every error (incl. the not-in-library early return and thrown errors) before
  `onClose`, so anchoring works. `MusicController.shuffleEnabled()` makes the
  toggle toast report the resulting state.
- Tests: **121** passing (was 107).

---

## Problem

Cuebar gives no transient feedback for playback outcomes:

- **Success is silent.** `PaletteModel.run` starts playback and immediately
  calls `onClose?()` — the palette just disappears. `playAlbum` does the same.
- **Errors are invisible when results exist.** Failures set `statusMessage`, but
  `PaletteView` only renders it inside `emptyState`
  (`Sources/Cuebar/PaletteView.swift:94`), which is shown only when
  `model.items.isEmpty`. Selecting a row that fails ("isn’t in your library",
  "has no playable tracks", an AppleScript/permission error) therefore shows
  **nothing** — the palette stays open and looks like a no-op.

## Goal

A small, transient **toast** that announces:

- **Playback success** — `Playing “Take On Me” — a-ha`, `Playing album “After Hours” — 14 tracks`.
- **Playback errors** — not in library, empty album, AppleScript failures (with
  the permission guidance `AppleScriptError` already provides), `noSelection`.
- **Transport commands** — `Paused`, `Resumed`, `Next track`, `Previous track`,
  `Shuffle on` / `Shuffle off`.

It must work whether or not the palette is still open (success closes it today),
respect Reduce Motion, be click-through, and read well to VoiceOver.

---

## Approach

An **in-app, Liquid-Glass toast in its own borderless panel**, anchored to the
palette. A separate window is required because the palette hides on success; the
toast outlives it briefly.

Rejected alternatives:

- *macOS Notification Center (`UNUserNotificationCenter`)* — needs the user to
  grant notification permission, appears in Notification Center history, and a
  toast for "playing a song you just asked for" is noisy. Could be added later
  behind the same `ToastCenter` as an extra sink.
- *Inline overlay inside the palette* — dies with the palette on success and
  can't show anything once it closes.

### Layering

`ToastPanel` is a second `NSPanel` in the same style as `PalettePanel`
(`Sources/Cuebar/PalettePanel.swift`): borderless, `.nonactivatingPanel`,
`backgroundColor = .clear`, `isOpaque = false`, `level = .floating`,
`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`.
Additionally: `ignoresMouseEvents = true` (click-through) and
`hidesOnDeactivate = false`.

### Placement

Anchored to the palette's frame (captured **before** `onClose` hides it):

- default: just **below** the panel, horizontally centred, 12 pt gap;
- if that would fall off-screen, place **above** the panel instead;
- if there is no palette frame (palette already hidden), **top-centre** of the
  active screen with a small margin;
- always clamped to the screen's `visibleFrame` (reuse the screen-selection
  logic style from `PaletteWindowController.positionOnActiveScreen`).

### Timing & stacking

- Success: ~**2.0 s**; error: ~**4.0 s** (permission errors a touch longer, so
  the guidance can be read).
- **One at a time**; a newer toast replaces the current one and resets the
  timer (no stacking, no queue for v1).
- Fade in/out (`alphaValue` via `NSAnimationContext`, ~0.12–0.18 s, matching the
  palette). Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  by skipping any movement (fade only).
- `NSAccessibility.post(element: ..., notification: .announcementRequested)`
  with the message so VoiceOver announces it.

---

## Components

### Core (testable) — `Sources/CuebarCore/`

- **`Toast.swift`** — the model:
  ```swift
  public struct Toast: Identifiable, Equatable, Sendable {
      public enum Kind: Equatable, Sendable { case success, error }
      public let id: UUID
      public let kind: Kind
      public let message: String
      public let detail: String?
      public var duration: TimeInterval { ... }   // by kind, overridable
  }
  ```
- **`PlaybackFeedback.swift`** — pure copy builders so wording is centralized and
  unit-tested:
  - `playing(_ candidate:)` → `Playing “<title>” — <artist>`
  - `playingAlbum(_ album:, trackCount:)` → `Playing album “<title>” — N tracks`
  - `notInLibrary(_ title:)`, `emptyAlbum(_ title:)`
  - `failure(_ error: Error)` → uses `LocalizedError.errorDescription`
    (covers `PlaybackError` and `AppleScriptError`, including the
    permission-denied guidance), falling back to `localizedDescription`.
  - transport: `paused()`, `resumed()`, `nextTrack()`, `previousTrack()`,
    `shuffle(_ enabled: Bool)` → `Shuffle on` / `Shuffle off`.
- **`ToastCenter.swift`** — `@MainActor final class ToastCenter: ObservableObject`
  with `@Published private(set) var current: Toast?`, `show(_:)`, `dismiss()`,
  and injectable durations + a `dismissDelay` closure (default `Task.sleep`) so
  auto-dismiss is testable without real waiting.

### Shell (AppKit + SwiftUI) — `Sources/Cuebar/`

- **`ToastView.swift`** — SwiftUI: glass capsule/rounded rect
  (`.glassEffect(.regular, in:)`, matching `PaletteMetrics.cornerRadius`-style
  rounding), an SF Symbol (`checkmark.circle.fill` / `exclamationmark.triangle
  .fill`), the message, and optional `detail` in secondary text. Fixed max width
  (~420 pt) with intrinsic height.
- **`ToastPanel.swift`** — the click-through `NSPanel` described above.
- **`ToastWindowController.swift`** — owns the panel + `NSHostingView`, observes
  `ToastCenter.$current` (Combine, like `PaletteModel` does for
  `SearchService`), sizes to the content's fitting size, positions the panel,
  orders it front, and animates in/out.
- **`Support/PaletteMetrics.swift`** — add toast constants (max width, gap,
  padding) so AppKit and SwiftUI can't drift.

### Wiring

- **`PaletteModel`** — add `var onToast: ((Toast) -> Void)?` and emit:
  - **song success** (in `executeSelection` / `run`): `PlaybackFeedback.playing(playable)`;
  - **bare `play` / now-playing row** (pause/resume toggles): `paused()` / `resumed()`;
  - **album success** (`playAlbum`): `PlaybackFeedback.playingAlbum(album, trackCount:)`;
  - **transport success** (`.pause`, `.resume`, `.next`, `.previous`,
    `.shuffle`): `paused()` / `resumed()` / `nextTrack()` / `previousTrack()` /
    `shuffle(_:)`. For `shuffle(.toggle)` we don’t know the resulting value, so
    read it first via a new `MusicController.shuffleEnabled()` and toast the
    inverse; fall back to `Shuffle toggled` if the read fails. `.on`/`.off`
    toast directly.
  - **early-return errors**: not-in-library branch → `notInLibrary`; empty-album
    branch → `emptyAlbum` (still keep `statusMessage` for the empty state);
  - **thrown errors** (both `run` catch and `playAlbum` catch):
    `PlaybackFeedback.failure(error)`.
  - Emit the toast **before** `onClose?()` so the controller can capture the
    palette frame for anchoring.
- **`PaletteWindowController`** — create one `ToastCenter` +
  `ToastWindowController`, set `model.onToast` to show anchored to `panel.frame`,
  and expose the toast controller to `AppDelegate` if we want it app-lifetime
  (it already is, via the controller).
- **`AppDelegate`** — no change needed if the `PaletteWindowController` owns it;
  the controller lives for the app's lifetime.

---

## Files

- **New** `Sources/CuebarCore/Toast.swift`
- **New** `Sources/CuebarCore/PlaybackFeedback.swift`
- **New** `Sources/CuebarCore/ToastCenter.swift`
- **New** `Tests/CuebarCoreTests/ToastTests.swift`
- **New** `Sources/Cuebar/ToastView.swift`
- **New** `Sources/Cuebar/ToastPanel.swift`
- **New** `Sources/Cuebar/ToastWindowController.swift`
- `Sources/Cuebar/PaletteModel.swift` — `onToast` + emissions
- `Sources/Cuebar/PaletteWindowController.swift` — own/wire the toast controller
- `Sources/CuebarCore/MusicController.swift` — `shuffleEnabled()` (for accurate
  toggle feedback)
- `Tests/CuebarCoreTests/Mocks.swift` — `MockMusicController.shuffleEnabled()`
- `Sources/Cuebar/Support/PaletteMetrics.swift` — toast constants
- `README.md` / `README.dev.md` — document the feedback

## Tests

- `PlaybackFeedback`: song/album wording; every transport message
  (`paused`, `resumed`, `nextTrack`, `previousTrack`, `shuffle(on/off)`);
  not-in-library/empty-album wording; error mapping for `PlaybackError` and
  `AppleScriptError` (incl. permission guidance).
- `Toast`: `Kind` → duration; identity/equality.
- `ToastCenter`: `show` publishes `current`; a newer `show` replaces it; the
  auto-dismiss task clears `current`; `dismiss()` clears immediately (inject a
  tiny delay / a manual `dismissDelay` closure).
- `MockMusicController.shuffleEnabled()` returns the configured value and
  records the call.
- Shell (`ToastPanel`/`ToastView`/`ToastWindowController`) is AppKit glue, not
  unit-tested (consistent with the rest of the shell).
- Manual checks (see below).

## Manual verification

1. Play an in-library song → success toast appears (palette closes).
2. Catalog-only song → error toast "isn’t in your Music library", palette stays
   open.
3. Album (`<name> album`) → "Playing album … — N tracks".
4. `pause` / `resume` / `next` / `previous` / `shuffle` → matching toast
   (`shuffle` reports the resulting state).
5. Deny Automation permission (or rename nothing) → permission guidance toast.
6. Reduce Motion on → toast fades without movement; VoiceOver announces it.
7. Toast is click-through; can join full-screen spaces.

## Decisions locked with the user

1. **Delivery: in-app glass toast** in its own borderless floating panel — no
   system permission, matches Cuebar’s look, survives the palette closing.
2. **Scope: playback/album success, every error, *and* transport commands**
   (`pause`, `resume`, `next`, `previous`, `shuffle`).
3. Durations/stacking: 2 s success / 4 s error, one-at-a-time replace
   (recommended defaults, implemented as-is unless told otherwise).

## Out of scope

- A toast history/log or Notification Center integration.
- Sound effects.
- Toasting background events (e.g. a track change) — this is feedback for
  actions Cuebar performed.
