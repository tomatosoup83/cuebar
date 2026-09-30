# Plan 18 — Ambient background follows the selection (opt-in)

Status: **implemented.** Companions: plan.md … plan17.md.

Implemented in this iteration:

- **Core**: `AmbientPaletteCoordinator` (source rule + debounce + fallback, with
  injected resolution and sleep so it's testable), `RowTintPolicy` (replacing
  `PaletteItem.carriesAlbumTint`), `ThemeStore.ambientFollowsSelection`.
- **Shell**: `AmbientTheme` deleted — the coordinator replaces it;
  `PaletteWindowController` feeds it the now-playing track and the highlighted row;
  `PaletteModel` gained the option plus persistence; `SettingsView` gained the
  checkbox (hidden under Tahoe).
- **UI**: result rows carry the same translucent tint + specular edge as the
  now-playing card; the ambient crossfade is 700 ms and honours Reduce Motion.
- Tests: **220** passing (was 209), including 10 new coordinator tests.
- Verified live: with IGOR playing and Olivia's album highlighted, the option off
  gives an IGOR-pink panel with a neutral row; the option on gives an
  **Olivia-blue panel with a matching blue row**.

> Also removed a debug hook that force-set the ambient palette — it masked the
> coordinator's behaviour during verification.

## Goal

An extra checkbox for the **Album Art** theme: when it's on, the **whole panel
colour** (the ambient wash + the glass tint) follows the **highlighted row**
instead of the now-playing track, crossfading between colours as the user cycles
through results, with a short pause before each change.

The selected row keeps being tinted with its own cover's colour — as now — so the
row and the background agree.

## Why I previously advised against this

In plan17 I argued for keeping the ambient keyed to the now-playing track: a
full-surface colour change on every arrow key is the most distracting way to use
colour, and on the default screen most rows are *commands* with no artwork, so the
panel would strobe between a colour and neutral.

Those objections are real but they are all **avoidable by construction**, which is
what this plan does:

| Objection | Mitigation |
|---|---|
| Strobes on every keystroke | A **debounce**: nothing moves until the selection settles |
| Flashes to neutral on command rows | **Fallback** to the now-playing colour when the row has no art |
| Constant distraction while browsing | **Opt-in checkbox**, off by default |

So it stays out of the default experience and becomes something the user turns on
deliberately.

## Decisions to confirm

1. With the option **on**, the selected row is tinted too (so row and background
   agree). With it **off**, today's behaviour is unchanged: only the now-playing
   row is tinted.
2. Debounce **350 ms**, crossfade **700 ms** — both as constants, easy to retune.
3. When the highlighted row has **no album colour** (a command, or a
   near-monochrome cover), fall back to the now-playing colour rather than fading
   to neutral.
4. The checkbox is **hidden while Tahoe is selected** (it only means something for
   Album Art).

## Design

### Core (testable) — new `AmbientPaletteCoordinator`

The rules and the timing move into Core so they can be tested without a UI. It
replaces the shell's `AmbientTheme`.

```swift
@MainActor
public final class AmbientPaletteCoordinator: ObservableObject {
    @Published public private(set) var palette: AlbumPalette?

    public init(
        followsSelection: Bool,
        delay: Duration = .milliseconds(350),
        resolve: @escaping (ArtworkSource) async -> AlbumPalette?,
        // Injected so tests control timing instead of waiting on a real clock.
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    )

    public func setEnabled(_ enabled: Bool)         // theme == .albumArt
    public func setFollowsSelection(_ follows: Bool)
    public func update(nowPlaying: NowPlayingTrack?) // from the poll
    public func update(selection: PaletteItem?)      // the highlighted row
}
```

**Source rule** (pure, separately testable):

```
followsSelection ? (selection.artwork ?? nowPlaying.artwork)
                 : nowPlaying.artwork
```

**Fallback rule:** a resolve that yields nothing — or yields an
`AlbumPalette` with `isUsable == false` — is treated as "no colour" and falls back
to the now-playing palette. That is what stops the panel flashing neutral as the
user arrows across command rows.

**Timing rule:**

- A change that **replaces an existing colour** sleeps `delay` first, then resolves,
  then publishes. A target that changes again during the sleep **cancels** the
  pending one and restarts the wait — so holding ↓ produces no colour change at all
  until the key is released.
- The **first** colour (nothing to transition *from*) is published as soon as it
  resolves, with no delay. Otherwise the panel would visibly "fill in" 350 ms late
  on every open.
- Because the sleep happens **before** `resolve`, arrowing past rows never triggers
  artwork fetches for them — only the row settled on is resolved.

### Core — `RowTintPolicy`

`PaletteItem.carriesAlbumTint` becomes a policy that knows about the option, so
the "selected row matches the background" requirement is expressed once:

```swift
public enum RowTintPolicy {
    /// Whether the row may carry the album tint when it is the selected row.
    /// The now-playing row always may; with `followsSelection`, any row may.
    public static func allowsTint(for item: PaletteItem, followsSelection: Bool) -> Bool
}
```

Commands still resolve to no palette, so they stay untinted either way.

### Core — `ThemeStore`

Adds `ambientFollowsSelection: Bool`, default **false**, alongside `theme`. One
store for both theme options.

### Shell

- `PaletteWindowController` owns the coordinator, constructed with
  `resolve: { await PaletteCache.shared.palette(for: $0) }` and
  `followsSelection:` from the store. It feeds it from the existing 1.5 s poll
  (`update(nowPlaying:)`) and on every selection change (`update(selection:)`),
  and sinks its `palette` into `model.setAmbientPalette(_:)` as today.
- `PaletteModel` gains `ambientFollowsSelection` (published, for Settings) and
  `setFollowsSelection(_:)`, which persists through a new
  `onAmbientFollowsSelectionChange` callback — mirroring `onThemeChange`.
  It also reports selection changes to the coordinator.
- `AppDelegate` loads the flag from `ThemeStore` and persists changes.

### View

`PaletteView` already crossfades on `ambientPalette`
(`.animation(.easeInOut(duration: 0.5), value:)`); the duration goes to **0.7 s** so
a full-panel hue change reads as a deliberate fade rather than a jump. Honour
`accessibilityReduceMotion`: swap instantly when it's on (matching how the toasts
behave).

The row tint follows `RowTintPolicy.allowsTint(for:followsSelection:)` in
`PaletteView.row(index:item:)`, replacing the direct `carriesAlbumTint` check.

### Settings

Beside the existing Theme dropdown, and only while Album Art is selected:

```
☑ Follow the highlighted row
   Tint the whole panel with the cover you're on
```

A `Toggle` with `.toggleStyle(.checkbox)` — a real macOS checkbox, as asked.

## Behaviour table

| Scene | Option off (default) | Option on |
|---|---|---|
| Default screen, now-playing card selected | panel + row coloured from the current track | same (the card *is* the selection) |
| Arrowing through search results | panel stays on the track's colour; rows neutral | panel crossfades to each settled row's cover; the settled row is tinted to match |
| Holding ↓ / ↑ | nothing changes | nothing changes (debounced) |
| Landing on a command row | panel unchanged | falls back to the now-playing colour |
| Nothing playing | neutral | neutral |
| Tahoe | plain glass | n/a (checkbox hidden) |

## Tests

`AmbientPaletteCoordinatorTests` (Core, `@MainActor`, injected `sleep` so nothing
waits on a real clock):

- Option **off** → the now-playing source drives the palette; selection changes
  don't affect it.
- Option **on** → the selected row's source drives it.
- Option on + a **command** row (no artwork) → falls back to the now-playing
  palette.
- Option on + an `isUsable == false` palette (grey cover) → falls back to the
  now-playing palette.
- Option on + nothing playing + a command row → `nil` (panel neutral).
- **Debounce:** two selection changes in quick succession publish only the last,
  and the first is never resolved.
- **First colour is not delayed**; a *subsequent* change *is* (asserted through the
  injected `sleep`, so it's deterministic rather than timing-flaky).
- Disabling the theme clears the palette.

`RowTintPolicyTests` (replacing the existing `PaletteItemTintPolicyTests` body,
which keeps its default-screen/search/browse/no-track coverage):

- Now-playing is allowed with the option off *and* on.
- Command / song / album / playlist rows are refused with it off.
- Any row is allowed with it on (and still resolves to no palette for commands).

`ThemeStoreTests`: the new flag defaults to false and round-trips.

## Manual verification

1. Album Art on, checkbox off → identical to today.
2. Checkbox on, type a query, arrow slowly → the whole panel crossfades to each
   settled row's cover, ~350 ms after stopping, over ~0.7 s, and the selected row
   matches the background.
3. **Hold ↓** → no colour change at all until released. This is the acceptance test
   for the whole feature.
4. Arrow onto a command row → the panel keeps the now-playing colour, no flash to
   neutral.
5. Nothing playing → neutral, no crash.
6. Reduce Motion on → colours swap instantly, no fade.
7. Relaunch → the checkbox state persists.
8. Watch for the glass tint **popping** while the wash crossfades (see Risks).

## Follow-up — the reported bugs

User report: *"the change of colour between options are too unreliable and slow,
sometimes it changes and sometimes it doesnt. also for grey/black albums it
reverts back to the now-playing colour."*

**Three causes, all mine:**

1. **The fallback.** The old `if resolved.isUsable` branch replaced any
   unresolvable row colour with the now-playing track's — that was decision #3
   below, and it was wrong. It also masked every failure mode (grey cover, command
   row, missing artwork, failed AppleScript lookup) behind one colour, so several
   different rows resolved to the *same* palette, `setAmbientPalette` short-circuited
   on equality, and nothing changed at all.
2. **The debounce restarted on every change**, and re-checked cancellation after
   resolution too. Arrow presses closer together than 350 ms chained into one long
   wait, so changes arrived late — or, with (1) supplying an identical colour,
   appeared not to arrive.
3. **The colour rode on the glass tint**, which is a `Glass` material value and is
   not animatable — the risk flagged in this plan's Risks section. Only the
   0.30-opacity wash faded.

**Fixes (all three decisions from the user):**

- **No fallback.** Whatever the cover gives is what the panel shows; a colourless
  cover is used as-is. A row with *no artwork at all* (a command) still keeps the
  track's colour, so arrowing the default screen doesn't blank the panel.
- **Leading delay.** The pause starts when a burst begins and is *not* restarted;
  while the user keeps moving, a running loop keeps applying the newest target, so
  the colour always lands on the row they stop on.
- **The wash carries the colour while following** (glass untinted in that mode,
  wash raised to `followWashOpacity` = 0.62), so every change crossfades.

**Dark covers.** A *colourless* cover that is also dark now produces a **dark**
panel: its stops are pulled down to `darkPanelLuma` (0.22) instead of lifted to
0.70, and the panel's content switches to light-on-dark via
`.environment(\.colorScheme, .dark)`.

Two things this needed that the first attempt got wrong:

- **Colourless *and* dark**, both. "Dark" alone would have flipped IGOR — black,
  but carrying a strong pink — to a dark panel, losing the coloured treatment it
  already had.
- **Darkness measured from the distribution, not the mean.** A black sleeve with
  large white type averages to mid grey, which is exactly how a black cover ended
  up as a near-white panel. `PaletteExtractor.lowerQuantileBrightness` takes the
  35th-percentile per-pixel brightness instead.

**Verified live:** the untinted, wash-carried crossfade on a bright cover (IGOR
pink panel, row tinted); and, by forcing the dark path with a debug knob, a dark
plum glass with white text that is fully legible.

**Not verified end-to-end:** no genuinely black cover turned up in the library —
the one cover assumed to be black (`SUGAR HONEY ICE TEA`) measures *light*
(quantile 0.71), so my reading of its 36 px thumbnail was simply wrong. The
decision is unit-tested (`testBlackSleeveWithWhiteTypeReadsAsDark`) and the
rendering is confirmed, but the two together on a real black sleeve are not.

**New risk this introduces:** the light/dark content flip is instantaneous, so
arrowing across a threshold-crossing cover will flip the text scheme rather than
fade it. Whether that reads as intentional or jarring needs a real black cover to
judge.

## Follow-up 2 — the reliability bug, and softening the dark change

User report (priority): *"if i cycle too fast and then suddenly stop then it doesnt
change the colour right away and thats when colour change becomes unreliable. from
then if i start cycling slowly again it mistakes colour of one album with another."*

### Root cause: an off-by-one, taken from a `@Published` sink

The coordinator was fed the highlighted row from a Combine sink:

```swift
model.$items.combineLatest(model.$selectedIndex)
    .sink { _, _ in coordinator.update(selection: self.model.selectedItem) }
```

**`@Published` fires in `willSet`**, so `selectedItem` was read *before* the index
had been written — the coordinator learned about the **previous** row. Hence the
panel lagged exactly one album: on stopping there is no further change, so it never
caught up ("doesn't change right away"), and while cycling it paired a row with its
neighbour's colour ("mistakes colour of one album for another"). The row tint was
never affected because it is resolved from inside the model, *after* the write —
which is exactly why the row and the panel disagreed.

Fixed by removing the sink entirely: `PaletteModel` now calls
`onSelectionChange?(selectedItem)` from `selectionChanged()`, after the value is
set.

Reproduced and verified with a scripted burst (`CUEBAR_CYCLE_TEST=<stepMs>`, 10
steps) that asserts the published palette matches the selected row:

| step | before | after |
|---|---|---|
| 20 ms | `match=false` | **`match=true`** |
| 80 ms | `match=false` | **`match=true`** |
| 300 ms | `match=false` | **`match=true`** |

### Secondary fix: don't queue behind a stale resolve

Timing instrumentation showed why a single wrong row could stall everything:

```
resolve album:michael jackson|xscape deluxe     0.00s   (cached)
resolve album:georgia gibbs|georgia gibbs       2.52s   (uncached)
```

An **uncached** album takes ~2.5 s, because `AppleScriptArtworkProvider` scans the
whole library (`some track of library playlist 1 whose persistent ID is …` — 6384
tracks here). Cached albums are instant, which is also why the behaviour felt
*intermittent*.

The loop used to resolve targets serially, so a 2.5 s miss blocked whatever came
after it. Now every selection change **cancels and restarts** the loop, so the
newest target is resolved immediately; the abandoned fetch keeps running inside
`PaletteCache` (shared with the row's artwork) so nothing is wasted. The pause also
became leading-per-burst, so a burst never restarts it but never strobes either.

**Follow-up worth doing separately:** making that lookup O(1) would remove a 2.5 s
stall that affects row artwork too, not just the theme. Music's numeric `track id`
is an indexed lookup where `persistent ID` is not, so caching the numeric id in the
library index would likely fix it.

### Softening the light↔dark change

*"its too big of a change from a light album to a dark album… make it not so
dramatic."*

Two things made it dramatic: the lightness swing (0.70 → 0.22) **and** the
light/dark content flip, which is `.environment(\.colorScheme, …)` — not
animatable, so the text snapped while the wash faded.

The flip cannot be animated, so the fix was to remove the need for it:
`darkPanelLuma` **0.22 → 0.44**, and the colour-scheme switch is gone. Dark covers
now read as clearly darker in the *same* scheme, and the whole change is carried by
the wash's crossfade. `AlbumPalette.isDark` was removed with it, being unused.

**Cost:** the panel no longer goes truly black for a black cover — it goes
distinctly darker. Getting both (true black *and* a smooth transition) needs the
text colours derived from the wash and animated, rather than a scheme flip; that is
a larger change across the palette, row and card views.

Verified on *eternal sunshine deluxe: brighter days ahead*: `top=luma 0.44` with
legible dark text, versus `0.70` for a light cover.

## Risks

1. **The glass tint may not animate.** `.glassEffect(.regular.tint(…))` takes a
   `Glass` value, and material properties generally aren't animatable — so the
   panel's tint could *snap* while the wash crossfades, which would look worse than
   either alone. This is the main unknown and the first thing to check. If it
   snaps, the options are: drop the glass tint while this option is on (let the
   wash carry the colour), or accept it.
2. **Extra artwork fetches.** Only the settled row resolves, so arrowing is cheap —
   but a settled row on a cold album triggers an AppleScript lookup. The row icon
   already fetches the same artwork, so it piggybacks on `ArtworkStore`'s cache and
   in-flight de-duplication; the debounce means it happens at most once per pause.
3. **Still busier than the default.** That is inherent; the checkbox is what keeps
   it opt-in.
4. Toasts follow the ambient palette (`themeProvider`), so they will fade too. That
   is probably desirable, but it is a side effect worth expecting.

## Files

- **New Core** `AmbientPaletteCoordinator.swift`, `RowTintPolicy.swift`
- **Modified Core** `ThemeStore.swift` (+flag), `PaletteItem.swift` (drop
  `carriesAlbumTint` in favour of the policy)
- **Deleted shell** `AmbientTheme.swift` (folded into the coordinator)
- **Modified shell** `PaletteModel.swift`, `PaletteWindowController.swift`,
  `PaletteView.swift`, `SettingsView.swift`, `AppDelegate.swift`
- **New tests** `AmbientPaletteCoordinatorTests.swift`; **modified**
  `ThemeTests.swift` (tint policy), `ThemeStoreTests`
- **Docs** `README.dev.md`, this file

## Decisions locked with the user

1. With the option **on**, the highlighted row is tinted too — the same treatment
   as the now-playing card — so the row and the background agree. With it **off**,
   behaviour is unchanged.
2. Debounce **350 ms**, crossfade **700 ms**.
3. A row with no album colour (a command, or a near-monochrome cover) **falls back
   to the now-playing colour** rather than fading the panel to neutral.
4. The checkbox is **hidden while Tahoe is selected**.

## Out of scope

- Following the **hovered** row (mouse) — selection only.
- Animated *hue rotation* between colours (we crossfade between two palettes
  rather than interpolating gradient stops in a colour space).
- Per-row ambient tinting on the Tahoe theme.
- A `theme` command row for the checkbox (Settings only for now).
