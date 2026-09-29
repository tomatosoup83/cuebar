# Plan 11 — Menu-bar cleanup (+ ⌘⏎ queue, attempted then removed)

Status: **menu cleanup implemented; ⌘⏎ queue removed.** Companions: plan.md …
plan10.md.

---

## Shipped: remove "Rebuild Library Index" from the menu bar

The in-app `rebuild` command (plan10) replaces it.

- `AppDelegate.configureStatusItem()` drops the item and its separator → menu is
  now **Open Cuebar** / **Quit**.
- The `rebuildIndex` selector is gone; `refreshLibraryIndex()` stays for launch
  and the in-app command.
- `README.dev.md` updated.

---

## Removed: ⌘⏎ "add to queue" / "play next"

### Why it was removed

It added the song to the **Cuebar Queue** playlist but didn't change what
actually played. Diagnosis:

- **Music has no scriptable queue.** The dictionary exposes no queue
  command/property; `get play queue` errors. Music's *Up Next* is a snapshot,
  independent of playlist contents — editing a playlist doesn't touch it.
- **`play <track>` doesn't adopt its playlist as the queue.** Only
  `play <playlist>` does (which is why album playback works).
- The fix that made it *function* — rewrite the queue playlist with the current
  track at the head, then `play q` + `set player position` — works, but it
  **restarts the current track and re-seeks** on every enqueue. The seam felt
  bad, and because Music's queue is opaque we couldn't smooth it out. Per the
  user's call, the feature was removed entirely.

### What was removed

- `Sources/CuebarCore/Queue.swift`, `QueuePreferenceStore.swift`
  (and `Tests/CuebarCoreTests/QueueTests.swift`).
- `MusicController.enqueue` / `playlistTrackIDs` (+ `queueSnapshotScript`,
  `queueLoadScript`, `parseQueueSnapshot`).
- `CommandExecutor.executeEnqueue`; `PlaybackFeedback.addedToQueue`.
- `PaletteModel.enqueueSelection` / queue position; `PaletteWindowController`
  ⌘⏎ handling; Settings "⌘⏎ Queue Position" row; footer `⌘⏎ queue` hint.
- None of the menu cleanup was affected.

### If it's revisited

Music still offers no queue API. The only faithful option is **UI scripting**
(accessibility) to invoke *Play Next* / *Play Later*; the no-permission option
is a Cuebar-owned queue whose seams are visible because Music must be told to
`play` the playlist again.
