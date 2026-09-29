# Plan 10 — "Rebuild Library Index" command + toast

Status: **implemented.** Companion to `plan9.md` (playlists + scope chip).

---

## Goal

Expose the existing menu-bar **Rebuild Library Index** action as a palette
command, and report progress/result with a toast.

## Implementation

- **`PaletteAction.rebuildLibraryIndex`** + a `CommandCatalog` entry
  (`rebuildIndex`, keywords `rebuild`, `reindex`, `library index`, `rescan`),
  so typing `rebuild` surfaces it.
- **`LibraryIndexSummary`** (Core) — `trackCount` + `playlistCount`.
- **`Toast.Kind.info`** for the in-progress message (new icon/colour in
  `ToastView`), with `PlaybackFeedback.rebuildingIndex()` /
  `indexRebuilt(_:)` / `indexRebuildFailed()`.
- **`AppDelegate.refreshLibraryIndex()`** now returns an optional
  `LibraryIndexSummary` (used by the menu item and the palette).
- **Wiring:** `AppDelegate` → `PaletteWindowController.onRebuildLibraryIndex`
  → `PaletteModel.onRebuildLibraryIndex`. The model shows
  "Rebuilding library index…", then a success toast ("Library indexed ·
  N tracks · M playlists") or an error toast. The palette stays open; the
  footer still shows the indexing spinner via `searchService.isIndexing`.

## Tests

- `CommandCatalog`: `rebuild` / `reindex` / `library index` → `rebuildIndex`.
- `PlaybackFeedback`: index toast copy and `Toast.Kind.info` duration.

`make test`: **138** passing (was 136).

## Out of scope

- Progress percentage (the scan is sub-second).
- Cancelling an in-flight rebuild.
