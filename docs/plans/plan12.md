# Plan 12 — First-run onboarding screen

Status: **implemented.** Companion backlog: `docs/FUTURE_FEATURES.md`.

Implemented in this iteration:

- **`OnboardingStore`** (Core) remembers completion in `UserDefaults`.
- **`MusicController.checkAutomationPermission()`** probes access (first call
  raises the TCC prompt); `permissionGranted(from:)` maps `-1743` → not granted.
- **`OnboardingView`** — a 3-step wizard (Welcome → Permission → Ready) inside
  the palette; hotkey shown read-only, live permission status with *Grant
  Access* + *Open System Settings*, index summary, step dots.
- **`PaletteScreen.onboarding`** + `PaletteModel` step/state/methods;
  `PaletteWindowController.showOnboarding()`; Return/→ advance, ← back,
  **Esc = skip-and-complete**.
- **`AppDelegate`** shows it on first launch; **Settings → "Show Onboarding
  Again"** replays it; `CUEBAR_ONBOARD=1` debug hook.
- Tests: **144** passing (was 138).

---

## Goal

The first time someone launches Cuebar, show a short onboarding **inside the
palette panel** (same Liquid Glass window, no new windowing) that explains what
it is, how to open it, and how to grant the Music Automation permission — then
never show it again.

## Flow (3 steps)

1. **Welcome** — app icon, one-line pitch ("A command palette for Apple Music"),
   and the launch hotkey shown as a chip (`hotKey.displayString`, e.g.
   `⌘⌥Space`) with the hint *"press this anywhere"*.
2. **Permission** — live **Automation** status:
   - *Granted* → a green check.
   - *Not granted* → a **Grant Access** button that runs a probe (which raises
     the macOS TCC prompt) plus an **Open System Settings** button
     (`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`).
   - Skippable — Cuebar still works for search until permission is given.
3. **Ready** — library index status: an indexing spinner while it builds, then
   *"6,355 tracks · 52 playlists"*; **Start searching** completes onboarding and
   drops into the normal empty search state (so the user can immediately type).

Navigation: **Return / →** advance, **←** back, **Esc** = *Skip* (completes, so
the user is never trapped). Buttons mirror those keys.

## Trigger & persistence

- **`OnboardingStore`** (Core): `hasCompleted` flag in `UserDefaults`
  (`"hasCompletedOnboarding"`), mirroring `HotKeyStore`.
- **`AppDelegate`**: on launch, if `!store.hasCompleted` →
  `paletteController.showOnboarding()` instead of waiting for the hotkey.
- Completing (or skipping) sets the flag.
- Re-runnable via a Settings row **"Show onboarding again"** (nice for
  re-granting after an ad-hoc rebuild resets TCC — which happens).

## Permission detection

New `MusicController.checkAutomationPermission() async -> Bool`:

- run a trivial script (`tell application "Music" to get version`);
- return **false** when the error is `AppleScriptError.isPermissionDenied`
  (`-1743`), **true** otherwise (including "Music not running");
- the *first* call also raises the system prompt, so the button doubles as the
  grant trigger. The pure `error → Bool` mapping is unit-tested.

## Screen wiring

- Add `case onboarding` to `PaletteScreen` (`Sources/Cuebar/PaletteModel.swift`).
- `PaletteView` renders a new **`OnboardingView`** when
  `model.screen == .onboarding` (alongside the existing settings/search switch).
- `PaletteModel` gains onboarding state (`step`, permission status, index
  counts) and methods (`advanceOnboarding`, `goBackOnboarding`,
  `completeOnboarding`, `grantPermission`, `openAutomationSettings`).
- `PaletteWindowController` gains `showOnboarding()` (same show path, but sets
  the screen) and wires the settings deep link.
- The panel still hides on resign-key (unchanged); onboarding reappears next
  launch until completed.

## Files

- **New** `Sources/CuebarCore/OnboardingStore.swift`
- **New** `Sources/Cuebar/OnboardingView.swift`
- **New** `Tests/CuebarCoreTests/OnboardingTests.swift`
- `Sources/CuebarCore/MusicController.swift` — `checkAutomationPermission()`
- `Sources/Cuebar/PaletteModel.swift` — `.onboarding` screen + state/methods
- `Sources/Cuebar/PaletteView.swift` — render onboarding
- `Sources/Cuebar/PaletteWindowController.swift` — `showOnboarding()`, links
- `Sources/Cuebar/AppDelegate.swift` — first-run trigger + store
- `Sources/Cuebar/SettingsView.swift` — "Show onboarding again" (optional)
- `Sources/CuebarCore/…`/`Mocks.swift` — permission probe stub for tests
- `README.md` / `README.dev.md`

## Tests

- `OnboardingStore`: defaults to not-completed; completes; round-trips.
- `checkAutomationPermission` mapping: `-1743` → false; other errors → true.
- (Shell glue — the view/window — is manual, consistent with the rest.)

## Manual checks

- Fresh install (or reset the flag / `CUEBAR_ONBOARD=1`): onboarding shows once.
- Grant flow raises the TCC prompt; status flips to granted.
- Esc skips and doesn't show again; Return walks through the three steps.
- Index step shows counts once indexing finishes.

## Decisions locked with the user

1. **Three-step wizard** (Welcome → Permission → Ready); Return/→ advances,
   ← back.
2. **Esc = Skip**, which marks onboarding complete (never traps the user).
3. **Add a "Show onboarding again" row** in Settings so it can be re-run (useful
   when an ad-hoc rebuild resets the Automation permission).
4. **Welcome shows the hotkey read-only**; changing it stays in Settings.

## Out of scope

- A tour of every command.
- Windows/notifications prompting.
