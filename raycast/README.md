# Cuebar for Raycast

Send commands to [Cuebar](../../) — the command palette for Apple Music —
without leaving Raycast.

The extension is a thin client for Cuebar's `cuebar://` URL scheme. It never
talks to Music.app itself, so Cuebar keeps its one Automation grant and all the
matching, ranking and playback logic lives in one place.

## Commands

| Command | What it does |
|---|---|
| **Run Cuebar Command** | Prompts for a command and sends it: `pause`, `next`, `shuffle off`, `take on me`, `album after hours`, `rebuild` |
| **Pause** · **Play / Resume** · **Next Track** · **Previous Track** · **Toggle Shuffle** | One-keystroke transport commands — assign Raycast hotkeys to these |

Because **Run Cuebar Command** takes a text argument, Raycast also gives you a
prompt, a searchable entry in root search, **Quicklinks** and **aliases** that
can pre-fill it (`pause`, `shuffle on`, a favourite album, …).

Cuebar reports the outcome itself with its own toast — `Playing “Take On Me”`,
`No match for “…”`, or a permission explanation — so the extension stays quiet
and the two can't disagree.

## Requirements

- macOS with **Raycast** installed.
- A **Cuebar build that registers `cuebar://`** (this branch — 0.7.1 and earlier
  don't have it). Build it with `make app`, then `open -a build/Cuebar.app`. The
  extension launches Cuebar if it isn't running.

## Run it in development mode

```sh
cd raycast/cuebar
npm install
npm run dev
```

`ray` ships inside the `@raycast/api` dependency, so nothing else is needed.
Raycast links the extension into its own storage and you'll find the commands in
root search under **Cuebar**.

To build without installing into Raycast:

```sh
npm run build
```

## Sandboxed or scripted use

Any launcher that can open a URL works — the extension is a convenience, not a
requirement:

```sh
open "cuebar://run?command=next"
open "cuebar://run?command=album%20after%20hours"
open "cuebar://rebuild"
```

The host form is shorthand for the same thing: `cuebar://pause` is
`cuebar://run?command=pause`, and `cuebar://album/SWAG%20II` searches for the
album. A `command` parameter always wins over the host, so a mistyped host can't
silently become a song search.

## Not published

This lives in the Cuebar repo rather than the Raycast Store, so it's installed
in development mode. Publishing would mean moving it to a standalone repo and
submitting it through `npm run publish`.
