# Plan 20 — ⌘K quick-actions menu

Status: **implemented.** Companions: plan.md … plan19.md.
Reference: `references/opened.png`, `references/raycast cmdk.png`.

## Goal

1. Pressing **⌘K** opens a Raycast-style **actions popup** for the highlighted row,
   anchored to the **bottom-right corner** of the palette.
2. The popup lists contextual actions — **Play / Run**, **Like / Unlike**,
   **Add to Playlist** (submenu), **Open in Music.app**, **Dismiss** — with a
   **“Search for actions…”** field at the bottom, exactly like Raycast.
3. The footer gains an **Actions ⌘K** hint next to settings so it reads
   **`settings ⌘,  |  actions ⌘K`**.
4. The experimental badge drops its label: **orange potion icon only**.

## UX

### Footer

```
↑↓ navigate   ⏎ run   esc close            [status]   ⌘, settings │ ⌘K actions   🧪
```

- The `⌘K actions` hint is always visible on the search screen (Raycast keeps it
  permanently in the bar).
- `⌘, settings` stays where it is today (idle state), with a thin vertical divider
  before the actions hint.
- The experimental badge becomes icon-only (same orange capsule, `flask.fill`).

### The popup

- A glass card anchored to the **bottom-trailing** corner of the palette,
  inset ~12 pt, width ~300 pt, height capped ~300 pt, with a shadow.
- Header: the target row's title + artist (secondary, one line).
- List of actions: SF Symbol + title; the highlighted row uses the standard
  `.selection` treatment. Destructive action (**Dismiss**) is red.
- Bottom: a `TextField("Search for actions…")` that filters the list live.
- Rendered **inside the existing panel** (a SwiftUI overlay on `searchScreen`),
  not a second window — the palette is a non-activating `NSPanel` that hides on
  resign-key, so a separate key window would dismiss the palette. The overlay
  keeps the single local key monitor and focus model.

### Keyboard

While the popup is open:

| Key | Action |
|---|---|
| `↑` / `↓` | move action highlight |
| `⏎` | run highlighted action |
| `esc` | back from the playlist submenu, else close the popup |
| `⌘K` | close the popup |
| any other key | typed into the actions filter field |

`⌘K` from the search screen opens the popup for the highlighted row. Focus moves
to the actions filter (`actionsFocusToken`); on close, focus returns to the search
field (`requestFocus()`).

### Actions by row kind

| Row | Actions |
|---|---|
| `nowPlaying` | Play/Pause · Like/Unlike · Add to Playlist · Open in Music · Dismiss |
| `music` song (library) | Play · Like/Unlike · Add to Playlist · Open in Music · Dismiss |
| `recent` (song) | Play · Like/Unlike · Add to Playlist · Open in Music · Dismiss |
| `music` album | Play Album · Open in Music · Dismiss |
| `music` playlist | Play Playlist · Open in Music · Dismiss |
| `music` catalog-only | Play (if resolvable) · Open in Music · Dismiss |
| `command` | Run “<title>” · Dismiss |

- **Like/Unlike** only appears when a library `persistentID` exists (directly, or
  after `LibraryResolver` maps a catalog item to a library track). The label
  reflects the current `loved` state; the state is read **on open** via one
  AppleScript call (`isLoved`), so the menu can show the correct verb.
- **Add to Playlist** switches the popup into a second mode listing the user's
  playlists (from the library index, excluding `Cuebar Queue`). Filtering works
  there too; `esc` goes back.
- **Open in Music.app** `reveal`s the library track and activates Music; for a
  catalog item it opens its `playbackURL`.

## Core (CuebarCore, unit-tested)

**New `QuickAction.swift`**

```swift
public enum QuickAction: Equatable, Sendable {
    case play
    case like
    case unlike
    case openAddToPlaylist
    case addToPlaylist(playlistID: String, name: String)
    case openInMusic
    case dismiss
}

public struct QuickActionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbolName: String
    public let action: QuickAction
    public let keywords: [String]
    public let isDestructive: Bool
    public let shortcut: String?     // "↩", "⌃X" …
}

public enum QuickActions {
    /// Contextual actions for a row. `loved == nil` means "not known yet".
    public static func items(
        for item: PaletteItem,
        loved: Bool?,
        canLike: Bool,
        isPlaying: Bool
    ) -> [QuickActionItem]

    /// The playlist submenu rows.
    public static func playlistItems(_ playlists: [MusicCandidate]) -> [QuickActionItem]

    /// Live filter for the actions search field.
    public static func filter(_ items: [QuickActionItem], query: String) -> [QuickActionItem]
}
```

**`MusicController` additions** (protocol + `AppleScriptMusicController`):

```swift
func isLoved(persistentID: String) async throws -> Bool
func setLoved(_ loved: Bool, persistentID: String) async throws
func addToPlaylist(trackPersistentID: String, playlistPersistentID: String) async throws
func revealInMusic(persistentID: String) async throws   // reveal + activate
func openInMusic(url: URL) async throws                  // open location
```

Each gets a static, testable script builder alongside `albumQueueScript`
(`lovedScript`, `addToPlaylistScript`, `revealScript`), and all values go through
`AppleScriptMusicController.escape(_:)`.

**`PlaybackFeedback` additions**: `liked`, `unliked`, `addedToPlaylist`,
`openedInMusic`.

## Shell (Sources/Cuebar)

**`PaletteModel`**

- `@Published private(set) var actionsMenu: ActionsMenuState?` where
  `ActionsMenuState { mode: .main / .playlists; selection: Int; query: String }`.
- `@Published private(set) var actionsLoved: Bool?`.
- Snapshot of the target row (`actionsTarget: PaletteItem?`) so a background
  now-playing refresh can't move the menu out from under the user.
- `openActionsMenu()` — snapshot target, reset state, resolve a library ID, kick
  off `isLoved` (async), set `actionsFocusToken`.
- `closeActionsMenu()`, `backActionsMenu()`, `moveActionsSelection(by:)`,
  `activateActionsSelection()`, `setActionsQuery(_:)`, `visibleActionsItems`.
- `runQuickAction(_:)` — executes via `executor` / `musicController`, emits
  `PlaybackFeedback` toasts, closes the menu on success (except entering the
  playlist submenu).

**New `ActionsMenuView.swift`** — the glass popup (header, rows, filter field,
reduce-motion-aware transition).

**`PaletteView`** — wrap `searchScreen` in a `ZStack(alignment: .bottomTrailing)`
with the overlay; add the `⌘K actions` hint + divider to the footer.

**`PaletteWindowController`** — key-monitor branch for the open menu, and the
global `⌘K` open/close.

**`ExperimentalBadge.swift`** — icon-only.

## Files

- **New Core** `QuickAction.swift`
- **Modified Core** `MusicController.swift`, `PlaybackFeedback.swift`,
  `SearchProviders.swift` (`LibrarySearchProvider.playlistSnapshot()`)
- **New shell** `ActionsMenuView.swift`
- **Modified shell** `PaletteModel.swift`, `PaletteView.swift`,
  `PaletteWindowController.swift`, `ExperimentalBadge.swift`
- **Tests** `QuickActionsTests` (new), `AppleScriptMusicControllerTests`
  (extended), `Mocks.swift` (`MockMusicController` new calls)

## Tests

- `QuickActions.items(for:...)` for every row kind, Like vs Unlike, the
  destructive flag, and the “no library ID → no Like/Add” rule.
- `QuickActions.filter` ranking/edge cases.
- Script builders for loved/add/reveal escape IDs correctly.
- `MockMusicController` records the new calls so `PaletteModel` behaviour can be
  covered in a later pass if we extract it.

## Out of scope (call out if wanted)

- **Play Next / Play Later** queue actions.
- **New Playlist…** creation from the submenu.
- **Go to Artist / Start Radio**.
- A floating window for the popup (we stay in-panel for focus reasons).

## Open questions

1. Popup placement: in-panel bottom-right overlay (proposed) vs a separate
   floating window to the right of the palette.
2. Should the `⌘K actions` hint always show, or only when idle alongside
   `settings`?
3. Any other actions you want on day one (Play Next / Play Later / Go to Artist)?
