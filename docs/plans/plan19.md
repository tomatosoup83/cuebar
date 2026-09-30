# Plan 19 — `theme` scope, What's New, and the 0.6.0 release

Status: **implemented.** Companions: plan.md … plan18.md.

Implemented in this iteration:

- **Core**: `SearchScope` (albums / playlists / themes, with `rankPreference`),
  `SettingsRow.visibleRows(theme:)`, `ThemeScopeMenu`, `WhatsNew` +
  `WhatsNewStore`; `SearchQuery` now carries a `scope`; `CommandEntry` gained a
  `badge`; `PaletteAction.setFollowsSelection`.
- **Shell**: a Theme scope (chip + three options), a keyboard-navigable Settings
  with an `NSMenu` dropdown, and a What's New screen shown once per version.
- **Release**: `Scripts/release.sh` now prefers `docs/releases/<version>.md` for the
  GitHub release notes, so the release page says what the app says.
- Tests: **245** passing (was 224). Verified live: the Theme chip and options, the
  What's New screen, and the Settings layout with its selected row and new
  `↑↓ navigate · ⏎ select · esc back` footer.

## Goal

1. **`theme` as a real scope.** Typing `theme ` (with a space) makes the search box
   show a **chip**, exactly like `album ` / `playlist `, and lists **only** the
   theme options.
2. **"Follow the Highlighted Row"** becomes one of those options as well as staying
   in Settings.
3. **A What's New screen** showing the three most important changes since the last
   release.
4. **The Settings page becomes keyboard-navigable** like the results list, including
   the dropdowns.
5. **Bump to 0.6.0 and push everything to GitHub**, with the same three highlights
   in the release notes.

## Design

### 1. `theme` as a scope

Today a scope is a `RankPreference` (`albums` / `playlists`), which is a *music
ranking* — a theme scope is not. So the field filter is split out from the ranking:

**New Core `SearchScope`:**

```swift
/// The in-field filter shown as a chip in the search box.
public enum SearchScope: Equatable, CaseIterable, Sendable {
    case albums
    case playlists
    case themes

    /// Music scopes rank and browse; `themes` filters app options instead.
    public var rankPreference: RankPreference? { … }

    public var keyword: String   { "album" / "playlist" / "theme" }
    public var title: String     { "Album" / "Playlist" / "Theme" }
    public var symbolName: String
}
```

**`SearchQuery`** keeps `term` and swaps `preference: RankPreference` for
`scope: SearchScope?`, exposing `preference` as a derived convenience so
`SearchService` is untouched. `parse` gains `theme` / `themes` as keywords, so
`theme `, `theme art` and `art theme` all work by the existing rules (a bare word
with no space stays a literal search; the trailing keyword wins).

**`PaletteModel`**: `scope` becomes `SearchScope?`. When the scope is `.themes` we
set `commands = themeScopeEntries(for: term)`, `music = []`, `nowPlaying = nil` and
clear the search service — so the existing list composer does the rest and no music
search runs. `rebuildItems` is unchanged.

**The three options** (badge shown on the right, mirroring the "Album"/"Playlist"
badges):

| Row | Subtitle | Badge |
|---|---|---|
| Theme: Tahoe | "Plain Liquid Glass" (or "Current theme") | Theme |
| Theme: Album Art | "Tinted with the album cover" (or "Current theme") | Theme |
| Follow the Highlighted Row | "On"/"Off" · "Tint the panel with the cover you're on" | Option |

Running a theme row keeps the palette open (as today). Running the option row
**toggles it** and stays open.

For labels, `CommandEntry` gains `badge: String = "Command"` so these rows can say
"Theme" / "Option" instead of "Command".

**Bare `theme` (no space)** keeps today's behaviour: the two theme rows appear as
ordinary results, which is how the scope is discovered in the first place.

### 2. Settings

The **Follow the Highlighted Row** checkbox already exists under Theme — unchanged.
The theme scope is the second way in.

### 3. What's New

**Core**

```swift
public struct WhatsNewEntry: Equatable, Sendable {
    public let symbolName: String
    public let title: String
    public let detail: String
}

public enum WhatsNew {
    /// Curated highlights, newest first. Content lives in code: it is offline,
    /// deterministic and unit-testable, and the screen links to the release.
    public static let notes: [Note]      // Note { version: String, entries: [WhatsNewEntry] }
    public static func highlights(for version: String) -> [WhatsNewEntry]
}
```

Exactly **three** entries for `0.6.0`, which are this release's real changes:

1. **Themes** — Tahoe, or Album Art with the panel tinted from the cover.
2. **Follow the Highlighted Row** — the panel colour follows what you highlight.
3. **`theme` scope** — type `theme ` to switch themes without leaving the keyboard.

**Store** — `WhatsNewStore` (UserDefaults, mirroring `OnboardingStore`):
`lastSeenVersion: String?`, `markSeen(_:)`.

**Screen** — a fourth `PaletteScreen.whatsNew` plus `WhatsNewView`, styled like
`OnboardingView` (badge, title, three rows, footer) with a **"See it on GitHub"**
button opening the release page via `NSWorkspace`, and Esc / Return to dismiss.

**When it shows** — on launch, if a note exists for the running version and
`lastSeenVersion` differs. It runs *after* onboarding if both would trigger, and
marks itself seen so it appears once. Settings gains **Show What's New** next to
"Show Onboarding Again".

### 5. Keyboard-navigable Settings

The Settings screen becomes navigable exactly like the results list.

**A selected row**, tracked in `PaletteModel.settingsSelection` and moved with
↑/↓ (clamped, no wrap, same as results). Rows render with the same selected-row
treatment the result rows use, so the interaction reads as one thing.

**Enter activates the selected row's primary action:**

| Row | Enter |
|---|---|
| Launch Hotkey | start recording (as today) |
| Theme | open the dropdown at the row |
| Follow the Highlighted Row | toggle it |
| Software Update | **Install** when one is available, otherwise **Check** |
| Show What's New / Show Onboarding Again | show that screen |

That also resolves a collision: Return currently *always* starts hotkey recording
on this screen, which cannot coexist with "Return activates the selected row". So
recording now starts only when the hotkey row is selected.

**Dropdowns.** The SwiftUI `Picker` is replaced by a row that opens an **`NSMenu`
positioned at the row** (`popUp(positioning:at:in:)`). A menu is the only thing
that gives real dropdown semantics — arrow keys to move, Return to choose, Esc to
cancel — inside a borderless non-activating panel. Clicking the row opens the same
menu, so the mouse path is unchanged.

Because menu tracking runs its own event loop, the palette's local key monitor must
**stand down while a menu is up** (`panel.isKeyWindow` may still be true), or it
would eat the menu's keys.

**Row list lives in Core**, since visibility is state-dependent (the follow row
exists only under Album Art):

```swift
public enum SettingsRow: String, CaseIterable, Sendable {
    case hotKey, theme, followSelection, update, whatsNew, onboarding

    /// The rows shown, in order, for the current state.
    public static func visibleRows(theme: ThemeID) -> [SettingsRow]
}
```

`settingsSelection` is clamped against that list, so hiding the follow row (by
switching to Tahoe) can never leave the selection dangling.

Footer hints become `↑↓ navigate · ⏎ select · esc back`.

### 6. Version + release

- `Resources/Info.plist` → `0.6.0` / build `600` (done by the script).
- **`Scripts/release.sh`**: if `docs/releases/<version>.md` exists, use it as the
  release `--notes`, so GitHub carries the same three highlights the app shows.
  `docs/releases/0.6.0.md` is added for this release.
- Then `Scripts/release.sh 0.6.0` bumps, builds, packages `Cuebar.zip`, signs it,
  commits **everything pending** (plans 16–19 included, `git add -A`), pushes, and
  creates the release.

## Tests

`SearchQueryTests` (extended) — `theme ` → scope `.themes`, empty term; `theme art`
→ scope `.themes`, term `art`; `art theme` → same; bare `theme` → no scope, term
`theme`; the existing `album` / `playlist` cases unchanged.

`SearchScopeTests` (new) — keyword / title / symbol for every case;
`rankPreference` is nil for `.themes` and maps for the music scopes.

`WhatsNewTests` (new) — the current version has exactly three entries; every entry
has a non-empty symbol, title and detail; an unknown version returns `[]`;
`WhatsNewStore` defaults to nil and round-trips.

Theme-scope rows: composing for the scope yields the two themes plus the option;
filtering by `art` narrows to Album Art; the option row's action toggles
`ambientFollowsSelection`.

`SettingsRowTests` (new) — `visibleRows(theme:)` gives 5 rows in order under Album
Art and 4 without the follow row under Tahoe; the order is stable.

Settings selection clamping — moving past either end stops rather than wrapping;
switching to Tahoe while the follow row is selected leaves the selection on a valid
row.

## Manual verification

1. `theme ` → a **Theme** chip appears in the field and the list holds only the
   three options. Return on Tahoe / Album Art switches the panel live.
2. Return on **Follow the Highlighted Row** toggles it; its subtitle flips
   On ↔ Off; the Settings checkbox agrees.
3. Typing after the scope filters (`theme art`); clicking the chip clears it.
4. Bare `theme` still lists the two themes as ordinary results.
5. **Settings by keyboard**: ↑/↓ moves the highlight through the rows; ⏎ on the
   hotkey row starts recording, on the follow row toggles it, on the update row
   checks (or installs), on the onboarding row shows the tour; **esc** still goes
   back. The selected row is visually the same treatment as a selected result.
6. **The dropdown by keyboard**: with the Theme row selected, ⏎ opens the menu;
   ↑/↓ moves between Tahoe and Album Art; ⏎ picks one; esc cancels without
   changing anything. Clicking the row does the same.
7. Switching to Tahoe while the follow row is highlighted leaves the highlight on a
   sensible row rather than vanishing.
8. Relaunch on 0.6.0 → What's New appears once; Settings → Show What's New replays
   it; it does not reappear on the next launch.
9. Update drill: an installed **0.5.0** sees 0.6.0, downloads it, verifies the
   signature, swaps and relaunches — then shows What's New.
10. GitHub release for `v0.6.0` carries `Cuebar.zip` + `Cuebar.zip.sig` and the
    three highlights as notes.

## Decisions to confirm

1. Bare `theme` (no space) **keeps** listing the two theme rows as results
   (recommended) rather than becoming "No matches". — **agreed**
2. What's New content is **curated in code** — offline and testable — with the
   screen linking to the GitHub release, rather than fetching the release body at
   runtime. — **agreed**
3. Version **0.6.0** (from 0.5.0).
4. The third theme-scope row's badge reads **"Option"**.
5. What's New shows **once per version**, after onboarding if both trigger.
6. Settings **Enter** uses each row's primary action — and on the update row that
   means *Install when one is available, otherwise Check*.
7. Settings dropdowns are real **`NSMenu`s** popped up at the row, rather than
   left/right arrows cycling the value in place.

## Risks

- **Blast radius.** `SearchScope` touches `SearchQuery`, `PaletteModel`,
  `SearchScopeChip`, `SearchView` labels and the window controller's scope
  handling. Existing `SearchQueryTests` cover the old contract and will be updated
  alongside — this is the main risk in the plan.
- **Menu tracking vs the key monitor.** `NSMenu.popUp` runs its own event loop
  while the panel may still be the key window, so the local key monitor has to
  stand down or it will swallow the menu's arrow keys and Return. This is the
  fiddliest part of the Settings work and the first thing to verify.
- **Return's meaning changes** on the Settings screen (it no longer unconditionally
  records a hotkey). The footer hint is updated to match, but it is a behaviour
  change for anyone used to the old shortcut.
- `CommandEntry.badge` is a public Core addition; the default keeps every existing
  row reading "Command".
- `PaletteScreen` gains a case, so the window controller's per-screen key handling
  must cover it (Esc dismisses, Return dismisses) or keys fall through to the
  search screen.
- `release.sh` does `git add -A`: every pending change lands in one commit. That is
  what "push everything" means here, but it is worth knowing before running it.

## Files

- **New Core** `SearchScope.swift`, `SettingsRow.swift`, `WhatsNew.swift`,
  `WhatsNewStore.swift`
- **Modified Core** `SearchQuery.swift`, `CommandCatalog.swift` (badge field)
- **New shell** `WhatsNewView.swift`
- **Modified shell** `PaletteModel.swift`, `PaletteView.swift`,
  `SearchScopeChip.swift`, `SettingsView.swift`, `PaletteWindowController.swift`,
  `AppDelegate.swift`
- **Scripts** `release.sh` (notes from a file)
- **Docs** `docs/releases/0.6.0.md`, `README.md`, `README.dev.md`, this file
- **Tests** `SearchQueryTests` (extended), `SearchScopeTests`, `SettingsRowTests`,
  `WhatsNewTests`

## Out of scope

- Fetching What's New from the GitHub API (the release page is linked instead).
- The ~2.5 s uncached artwork lookup (plan18 follow-up; affects row art too, and
  would be fixed by indexing Music's numeric `track id`).
- Deriving the panel's text colours from the wash, which is what would allow truly
  black panels *and* a smooth transition.
