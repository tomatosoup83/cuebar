# Plan 17 — Less muted Album Art wash

Status: **implemented.** Companions: plan.md … plan16.md.

Implemented in this iteration:

- **Retuned `PaletteExtractor`** — now a three-step transform: borrow the cover's
  signature colour, lift to a **luma floor of 0.70**, then pull chroma into a
  **band** (0.16–0.40 wash, 0.28–0.70 accent). See the follow-up section: the
  earlier "lift toward a light tint" version measured out to grey in practice.
- **Added a glass tint** (`ThemeGlass`): under Album Art the glass itself is tinted
  with the cover's accent, which turned out to be the **main colour lever**.
- **Selected row**: the system's translucent selection material with the cover's
  colour laid *through* it (`ThemeGlass.rowTintOpacity`, default 0.55) plus a
  faint specular edge — coloured, but still glass rather than a painted slab.
- **`ThemeBackground` opacity** 0.55 → 0.30.
- Debug-only `CUEBAR_WASH_OPACITY` and `CUEBAR_GLASS_TINT` to A/B the strength,
  a `CUEBAR_DARK=1` hook to force a dark appearance, `CUEBAR_DUMP_PALETTES` to
  measure a spread of real covers, and the Album Art debug hook now resolves a
  **real** cover through the real extractor.
- **Implemented the Reduce Transparency fallback** that plan16 documented but
  never actually coded: the wash now disappears when it's on.
- **Tried and rejected `.clear` glass** (item 3) — see below.
- Tests updated to assert the new intent (colour survives, lightness floor holds,
  hue preserved, chroma band respected). 201 passing.

---

## Goal

The Album Art wash reads as grey rather than as the cover's colour. Make it
**more colourful** and **more transparent** without breaking legibility.

## Diagnosis

Four attenuations stack, so only ~10% of a cover's chroma survives:

| Stage | Effect on a saturated cover |
|---|---|
| `Tuning.saturationKeep = 0.45` | keeps 45% of the chroma |
| `blended(with: neutral, topNeutral: 0.62)` | ×0.38 → ~20% |
| `ThemeBackground.opacity(0.55)` | ×0.55 → ~11% |
| glass frosting on top | a little less again |

Two aggravating details:

1. `ThemeColor.neutral` is `(0.60, 0.60, 0.64)` — slightly **blue**, so blending
   toward it drags every hue toward blue-grey, not just down.
2. The neutral blend was doing **two** jobs: desaturating *and* lightening. So the
   muting can't be removed by simply lowering the blend — that would let dark
   covers produce dark washes, which is a real legibility regression.

Evidence this is a tuning bug, not a design limit: the selected-row **accent**
reads fine, and it uses half the blending (`accentNeutral: 0.30`).

## Why the two asks are compatible

Raising **chroma** while lowering **alpha** gives a vivid tint you can see
through, rather than a slab. Lower alpha is also *safer* for legibility: the glass
material already adapts to light/dark appearance and does the contrast work for
the text. Pushing the wash toward opaque makes it fight the material.

## Design

Replace "blend toward grey" with "lift toward a light tint of the same hue":

```
wash(c) = c.withSaturation(saturationKeep)          // cap chroma, keep hue
            .blended(with: c.blended(white, lift),  // light version, same hue
                     amount: stopAmount)
          |> luma floor: if luma < minimumLuma, blend toward white to reach it
```

- **Saturation is nearly free; darkness is not.** Hence a hard `minimumLuma`
  rather than a blend ratio that has to do both jobs.
- New tuning: `saturationKeep 0.75`, `lift 0.55`, `topAmount 0.22`,
  `bottomAmount 0.16`, `accentAmount 0.18`, `minimumLuma 0.48`.
- `ThemeBackground` opacity → **0.40**.
- Unchanged: `isUsable` still gates monochrome covers; semantic colours
  (toasts, progress accent) are never derived from artwork; the accent stays a
  separate stronger colour.

## Item 3 — tried and rejected: `.clear` glass

Album Art was switched to `.glassEffect(.clear, …)` and captured live (light
appearance). **Rejected:**

- `.clear` is documented as being "for media-rich backgrounds where content is
  bold/bright" — Cuebar's content is a dense list of 12–15 pt text, the opposite
  case.
- With `.clear` the desktop reads through the panel almost unfiltered and
  **collides with the row text**: terminal text sitting behind the panel was
  legible *through* it, directly overlapping the subtitles.
- `.regular` frosts that backdrop into oblivion; row text is crisp in both
  appearances.

Both themes therefore stay on `.regular`. More colour has to come from the wash,
not the glass.

Verified alongside: with `.regular`, **dark appearance** renders a mauve-tinted
dark glass with fully legible white text — the material carries the contrast and
the wash only contributes hue. That is why low wash alpha is the safe direction.

## Item 4 — adopted: tinting the glass

`.glassEffect(.regular.tint(accent), …)` under Album Art. A strength ladder was
captured live (tint 0 / 0.25 / 0.35 / 0.55 / 0.90):

- The tint is the **dominant colour lever**. At the same strength, tint + wash and
  tint alone are near-identical, i.e. once the glass is tinted the wash contributes
  mostly the top→bottom gradient variation rather than the colour.
- **0.35 is the chosen default** (`ThemeGlass.tintOpacity`): a clear step up from
  the muted baseline without collapsing into a flat pink slab — the panel still
  plainly reads as glass, and the desktop still shows through.
- Verified in **both** appearances: light gives a soft rose glass; dark gives a
  mauve-tinted dark glass with white text, both fully legible.
- **Tahoe is unaffected** — the tint is applied only when the Album Art theme is
  active and a usable palette exists.

## Validation

- Snapshots **cannot** show the glass composite (`cacheDisplay` skips the
  backdrop), so this specific question needs a **real** `screencapture` of the
  live panel — Screen Recording turned out to be already granted for the host
  Terminal.
- Unit tests: colour survives (chroma well above the old ~0.2), luma floor holds
  even for dark art, hue ordering preserved top vs bottom.
- Confirmed live, glass included: the wash renders as IGOR's pink, the desktop
  shows through, and text stays legible in **both** light and dark appearance.

## Follow-up — "too dark / too grey" (after the Olivia Rodrigo check)

Reported: *"you seem pretty sad for a girl so in love"* produced a harsh blue
background. Instrumented the extractor (`CUEBAR_DUMP_PALETTES`) and dumped 12
real albums. That turned the guesswork into a measurement:

```
BORN LIKE THIS       top=luma 0.48 chroma 0.04   accent=chroma 0.18
Girls Like You       top=luma 0.48 chroma 0.05   accent=chroma 0.10
Pop 2                top=luma 0.79 chroma 0.01   accent=chroma 0.17
Big Fish Theory      top=luma 0.48 chroma 0.09   accent=chroma 0.30
thank u, next        top=luma 0.63 chroma 0.05   accent=chroma 0.07
```

**Diagnosis.** The user guessed "either the background is too dark, or the
selected row colour is not light enough". The data says the first, and worse:

- Every wash stop was **pinned exactly at the luma floor of 0.48** — a mid-tone.
  The floor was acting as the value, not a floor.
- Chroma was **0.01–0.12** — the stops were essentially grey, which is why the
  panel read as a muddy blue-grey rather than a colour.

Two causes, both structural:

1. **Averaging a third of a photograph mixes hues into grey.** The top/bottom
   thirds of a photo average toward neutral almost by construction. The colour
   survived only in the accent bucket.
2. **Lifting toward white destroys chroma.** Guaranteeing a luma floor by
   blending toward white simultaneously desaturates, so a dark cover's colour was
   thrown away by the very step meant to make it legible.

**Fix.**

- Luma floor **0.48 → 0.70**: the wash should be light; the glass tint carries
  the colour.
- **Own the fact that lifting desaturates**: after lifting, pull chroma back into
  a band (`withChroma(atLeast:)` / `(atMost:)`, luma-preserving).
- **Stops borrow 45% of their colour from the accent**, so photographic covers
  stop averaging out to grey.
- `minimumChroma` 0.06 → **0.08**, so a genuinely neutral cover falls back to
  plain glass instead of a fabricated tint.

**Bug found while implementing this:** `withSaturation` clamps its factor to
0…1, so the new "put the chroma back" step was silently a no-op and the first
measurement after the rewrite still came out grey. Chroma boosting now goes
through a private `scaledChroma(_:)` that is deliberately unclamped.

**Re-measured (12 albums):** all stops now sit at luma 0.70–0.94 with chroma
0.16–0.40 (accent 0.28–0.54); 9 of 12 are themed, 3 near-monochrome covers fall
back to plain glass — including one whose chroma was exactly 0.00.

**Verified visually**, glass included: Olivia Rodrigo is now a *light* sky blue
rather than a mid-tone grey-blue, IGOR still reads as soft pink, and dark
appearance stays legible in both.

## Follow-up — the selected row (glass, not a slab)

Ask: make the selected row **more colourful** while staying readable, still
contrasting the background, and keeping the glass aesthetic.

**First attempt, rejected on looks.** The row was filled with the cover's colour
at full strength — saturated, darkened to luma 0.44, foregrounds derived from that
fill via WCAG luminance so readability was guaranteed by construction (worst case
~4.58:1). It measured well, but an opaque saturated block reads as a painted list
item, not as glass. The user's call: *"it ruins the aesthetic"*.

**Final approach — the original structure, just stronger.** The row keeps the
system's translucent `.selection` material and the cover's colour is laid *through*
it at `ThemeGlass.rowTintOpacity` (default **0.55**, up from the original 0.28),
with a faint specular top edge. The panel's glass still shows through, which is
what keeps it reading as glass.

Because the tint is translucent, the text goes back to the **appearance-adaptive
system colours** (`.primary` / `.secondary` / `.quaternary`) instead of a derived
foreground: they resolve dark over a light panel and light over a dark one, so
they stay correct in both. **That is the trade** — the exact contrast guarantee is
only achievable with an opaque fill, and the aesthetic needs translucency.

The colour still comes from `AlbumPalette.selection`, and the relative-colour
guarantee still holds: the wash is *chroma-capped* at 0.40 while the row tint is
*floored* at 0.45, so the selected row is always the more colourful element
(asserted in a test).

The WCAG helpers (`relativeLuminance`, `contrastRatio`, `contrastingForeground`)
were removed once unused rather than left as dead code — they are the right tool
if an opaque variant ever returns.

Verified live at tint 0.35 / 0.55 / 0.75 in light, and 0.55 in dark: 0.55 is the
balance point — clearly coloured, still plainly glass. 0.75 is one number away if
more colour is wanted.

## Follow-up — where the tint applies

Ask: *"i want it to mainly affect the now playing row on the default screen."*

The row tint is gated by `PaletteItem.carriesAlbumTint`, which is true for the
now-playing row only:

- **Default screen** (empty box) → the now-playing card is index 0 and selected, so
  the album colour lands on it — the hero of that screen, and the one place it
  belongs.
- **Search results** → ordinary rows keep the neutral system `.selection`, so
  arrowing through them no longer flashes colour row after row.
- **Browse mode** → the now-playing row is omitted entirely, so nothing is tinted.
- **Nothing playing** → nothing is tinted; the panel is just the wash.

The panel-wide **wash is unaffected** — it still comes from the now-playing track
on every screen, so the theme is still visible everywhere; only the strong row
treatment is focused. That is why the ask is met *"mainly"* rather than
exclusively.

Covered by `PaletteItemTintPolicyTests` (6 tests): which row kinds carry the tint;
that the default screen's only tinted row is the default selection; that search
results and browse mode carry none; that nothing is tinted with no track; and that
the tinted row shares its artwork with the ambient wash, so the card and the
backdrop can never disagree.

Added `CUEBAR_FAKE_NOWPLAYING=1` — a debug hook that renders the card with a
forced palette so it can be verified without Music loaded.

## Risks

- The wash is lighter now, so the **glass tint** carries most of the colour; if a
  cover's accent is unusually loud the tint can still read strong. One number
  (`ThemeGlass.tintOpacity`) tunes it.
- ~25% of albums fall back to plain glass. That is deliberate (near-monochrome
  covers look muddy when tinted) but means the theme visibly "does nothing" for
  those covers. `Tuning.minimumChroma` is the dial if that feels like too many.
- `labelColor` is a fixed dynamic colour, so a *dark* wash would break contrast in
  light appearance. The 0.70 luma floor exists to prevent exactly that, and
  Reduce Transparency drops the wash entirely.
