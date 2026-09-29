# Cuebar — Future features (backlog)

A living list of ideas, not commitments. Feasibility notes reflect what we've
actually verified about `Music.app`:

- ✅ **Scriptable** — plain AppleScript (`MusicController`).
- 🟡 **Needs index work** — extra fields in the library index (version bump).
- ⚠️ **Caveats** — fragile, requires a new permission, or imperfect.
- ❌ **Not possible** — no supported API.

---

## High value, low effort (scriptable ✅)

- **Launch at login** — Settings toggle via `SMAppService.mainApp`. Cuebar is an
  agent app; this is the most expected missing "app" feature.
- **Track actions** — `love` / `dislike` (`favorited`/`disliked`) and `rate 1–5`
  (`rating`), surfaced as ⌘-shortcuts on a selected row.
- **Add to playlist** — `duplicate track to user playlist "…"` with a small
  picker. Reliable (unlike the queue) and fills the gap the removed ⌘⏎ left.
- **Volume & seek** — `volume up/down/mute`, `back 15`, `forward 15`, `restart`
  (`sound volume`, `mute`, `player position`, `fast forward`/`rewind`).
- **Now-playing polish** — a progress bar (`player position`/`duration` are
  already parsed) plus the current **shuffle/repeat** state on that row.

## Search power (🟡 index work, high payoff)

- **More scopes** — `artist <name>`, `genre`, reusing the scope-chip pattern.
- **Filter operators** — `year:2019`, `before:2020`, `added:30d`, `rated:4+`
  (`year`, `genre`, `date added`, `rating` are in the dictionary; needs index v4).
- **Recently played / most played** — index `played date` / `played count`;
  commands `recent` and `top`.
- **Browse mode** — with a scope active and an empty term (`playlist ` / `album `),
  list all albums/playlists instead of "No matches".
- **"play <song> by <artist>"** — parse an explicit artist to disambiguate.

## Nice, medium effort (✅ / ⚠️)

- **Menu-bar now-playing** — status item shows the current title with a small
  transport menu (play/pause/next/previous).
- **Sleep timer** — `stop in 30m` (timer + pause).
- **Lyrics** — `lyrics` shows the current track's lyrics (`lyrics` property).
- **Update checker** — query the GitHub releases API on launch and toast
  "v0.3.0 available"; Cuebar now publishes releases.
- **Full VoiceOver pass** — beyond the toast announcement.

## Repo / process

- **CI** — GitHub Actions running `make test` on push/PR.
- **LICENSE** — the README says "no license chosen"; MIT is a common fit for a
  public repo.
- **Signed / notarised builds** — removes the Gatekeeper warning on release
  downloads (needs a paid Apple Developer account).

## Not possible (don't get tempted)

- ❌ **Real queue / "Play Next" / "Play Later"** — Music exposes no queue API
  (`get play queue` errors; Up Next is a UI-only snapshot). An attempt shipped in
  plan11 and was removed; the only faithful route is Accessibility UI scripting.
- ❌ **Play catalog-only songs in Music.app** — no supported API without a
  MusicKit entitlement.

## If we pick three next

1. **Launch at login** — small, expected, high value.
2. **Track actions (add-to-playlist, love, rate)** — reliable AppleScript.
3. **Recently played / most played** — uses data we already index.
