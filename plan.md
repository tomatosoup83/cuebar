# Cuebar — Spotlight-style Command Palette for Apple Music (macOS)

Status: **APPROVED DIRECTION — awaiting go-ahead to implement**. No implementation code written yet.

Decisions locked with the user:
1. Playback engine → **AppleScript → Music.app** (substitute for the macOS-unavailable `SystemMusicPlayer`).
2. Project format → **SwiftPM package + `Scripts/build-app.sh`** (no `.xcodeproj`).
3. Library search → **AppleScript enumeration + disk-cached index**, fuzzy-ranked in Swift.
4. Shuffle → `shuffle` **toggles**; `shuffle on` / `shuffle off` also accepted.

---

## 0. Environment fact-check (verified on this machine before planning)

These are hard facts obtained by probing the installed SDK, not assumptions:

| Check | Result |
|---|---|
| macOS / Xcode / Swift | macOS 27.0, Xcode 27.1, Swift 6.4, SDK `MacOSX27.0` |
| `SystemMusicPlayer` on macOS | ❌ **`@available(macOS, unavailable)`** — compiler error, SDK-verified |
| `MPMusicPlayerController` (legacy) | ❌ **`@available(macOS, unavailable)`** — compiler error |
| `ApplicationMusicPlayer` on macOS | ✅ available (macOS 14+), but plays audio **inside our app**, not via Music.app |
| `MusicLibrarySearchRequest` | ✅ compiles (macOS 14+) |
| `MusicCatalogSearchRequest` | ✅ compiles (macOS 12+) |
| Codesigning identities | ❌ `0 valid identities found` — no Apple Developer team configured |
| Music.app present | ✅ `/System/Applications/Music.app` |
| Carbon `RegisterEventHotKey` | ✅ compiles (no Accessibility permission needed) |
| `NSPanel` `.nonactivatingPanel` + `canBecomeKey` | ✅ compiles |
| SwiftUI `.glassEffect(.regular, in:)` | ✅ compiles (macOS 26+ API) |

### The one blocking conflict with the request

The request says: *"Use MusicKit and `SystemMusicPlayer` for playback."*

**`SystemMusicPlayer` does not exist on native macOS.** Apple explicitly marks it unavailable (`@available(macOS, unavailable)`). The same is true of the older `MPMusicPlayerController.systemMusicPlayer`. This is an OS-level limitation, not a configuration problem.

What actually exists on macOS:

1. **AppleScript / ScriptingBridge → Music.app** — the only way to genuinely control the *system* Apple Music player (play/pause/next/previous/shuffle affect the real Music app, share state, keep playing when Cuebar is closed). No entitlement or paid account required; only a one-time Automation (TCC) permission prompt.
2. **`ApplicationMusicPlayer` (MusicKit)** — plays Audio *inside Cuebar's own process*. It does **not** control Music.app, so "next/previous/shuffle" would only affect Cuebar's private queue. It also requires the MusicKit entitlement + a Music user token, which needs a paid Apple Developer team that is **not present on this machine**, and catalog playback additionally requires an Apple Music subscription.

**Recommendation:** use **AppleScript → Music.app as the playback/control engine** (functionally replaces `SystemMusicPlayer`), and keep MusicKit behind a protocol as an optional, feature-flagged provider if a signed/entitled build is ever used. Details in §2 and §5.

---

## 1. MVP requirements

Scope is deliberately small and deterministic. No LLM, no settings UI, no playlists/library management.

### Commands (verb + optional query)

| Input | Behavior |
|---|---|
| `play <song>` | Search library → catalog, rank, play best match |
| `pause` | Pause Music.app |
| `resume` | Resume Music.app |
| `next` | Skip to next track |
| `previous` | Previous track |
| `shuffle` | Toggle shuffle (`shuffle on` / `shuffle off` also accepted) |
| bare text (e.g. `take on me`) | Convenience: treated as `play <text>` |

### `play <song>` ranking rules (hard requirements)

1. Exact song-title match is the strongest signal.
2. A **song whose title exactly matches ranks above an album with the same name**.
3. Fuzzy matching tolerates minor typos.
4. **Library first**, catalog fallback only when the library has no good match.
5. Fast + deterministic: stable, reproducible ordering for identical inputs.

### UI (keyboard-first)

- Minimal Spotlight-style floating panel, Liquid Glass material.
- `Enter` = execute, `Esc` = close, `↑`/`↓` = move selection.
- Search field focused on open; panel closes on focus loss.
- Result rows: artwork, title, artist · album, source badge (Library / Catalog).
- No settings, no advanced features.

### Non-goals (MVP)
Playlist management, library editing, queue browsing, custom hotkey configuration, lyrics, artwork caching policy, multi-window, preferences.

---

## 2. Architecture

Simple, modular, protocol-oriented so commands and providers can be added later.

```
                       ┌───────────────────────────┐
  ⌘⌥Space (global) ──► │ HotKeyManager (Carbon)    │
                       └────────────┬──────────────┘
                                    ▼
                       ┌───────────────────────────┐
                       │ PaletteWindowController   │  NSPanel (.nonactivatingPanel)
                       │  + NSHostingView          │  SwiftUI + .glassEffect
                       └────────────┬──────────────┘
                                    ▼
                       ┌───────────────────────────┐
   typed text ───────► │ CommandParser             │  "play take on me" → .play("take on me")
                       └────────────┬──────────────┘
                       ┌────────────┴──────────────┐
                       ▼                           ▼
            ┌────────────────────┐      ┌────────────────────────┐
            │ SearchService      │      │ MusicController         │
            │  LibraryProvider   │      │  AppleScriptMusic...    │
            │  CatalogProvider   │      │  MockMusicController    │
            │  Ranking           │      │  (MusicKit optional)    │
            └─────────┬──────────┘      └───────────┬────────────┘
                      ▼                              ▼
            LibraryIndex (disk cache)         Music.app (AppleScript)
            iTunes Search API (catalog)
```

### Core protocols (the extension seam)

```swift
protocol MusicController: Sendable {          // replaces "SystemMusicPlayer"
    func play(song: MusicCandidate) async throws
    func pause() async throws
    func resume() async throws
    func next() async throws
    func previous() async throws
    func setShuffle(_ on: Bool) async throws
    func toggleShuffle() async throws
}

protocol SearchProvider: Sendable {
    var source: MusicSource { get }           // .library | .catalog
    func search(_ query: String, limit: Int) async throws -> [MusicCandidate]
}
```

`AppleScriptMusicController` and `AppleScriptLibraryProvider` are the MVP concrete implementations. `MusicKit*` implementations are optional and only compiled/used when authorization succeeds.

### Concurrency model (Swift 6 strict concurrency)
- AppleScript execution + `NSPanel` on `@MainActor`.
- Search/ranking off the main actor; results delivered back to the main actor.
- `Task` cancellation on each keystroke (debounce ~120 ms) to avoid stale results.

---

## 3. Project / file structure

No XcodeGen/Tuist discovered, and there is no signing identity — so the build targets a locally-built agent `.app` bundle. Two viable formats (decision in §8):

```
cuebar/
├── Package.swift
├── Makefile
├── README.md
├── Sources/
│   └── Cuebar/
│       ├── CuebarApp.swift                 # @main, AppDelegate, accessory policy, status item
│       ├── Cuebar.entitlements             # (only if sandbox later)
│       ├── HotKey/
│       │   └── HotKeyManager.swift         # Carbon RegisterEventHotKey + event handler
│       ├── Palette/
│       │   ├── PalettePanel.swift          # NSPanel subclass
│       │   ├── PaletteWindowController.swift
│       │   ├── PaletteView.swift           # search field + results + footer
│       │   └── ResultRowView.swift
│       ├── Commands/
│       │   ├── Command.swift               # enum
│       │   ├── CommandParser.swift
│       │   └── CommandExecutor.swift
│       ├── Search/
│       │   ├── MusicCandidate.swift        # id, title, artist, album, source, kind, artworkURL, persistentID
│       │   ├── SearchService.swift         # orchestrates providers + ranking
│       │   ├── Ranking.swift               # scoring + deterministic sort
│       │   ├── AppleScriptLibraryProvider.swift
│       │   └── ITunesCatalogProvider.swift # public iTunes Search API fallback
│       ├── Library/
│       │   ├── LibraryIndex.swift          # in-memory index
│       │   └── LibraryIndexStore.swift     # JSON cache in Application Support
│       ├── Music/
│       │   ├── MusicController.swift
│       │   ├── AppleScriptMusicController.swift
│       │   └── MockMusicController.swift
│       └── Support/
│           ├── AppleScriptRunner.swift     # NSAppleScript wrapper + error mapping
│           ├── Log.swift
│           └── AppInfo.swift
├── Tests/
│   └── CuebarTests/
│       ├── CommandParserTests.swift
│       ├── RankingTests.swift
│       └── SearchServiceTests.swift
├── Resources/
│   └── Info.plist                          # LSUIElement, NSAppleEventsUsageDescription, bundle id
└── Scripts/
    ├── build-app.sh                        # swift build + assemble Cuebar.app + ad-hoc codesign
    └── run.sh
```

---

## 4. Implementation steps

Each step ends in a runnable/observable state.

1. **Risk spike (no product code).**
   - Verify `NSAppleScript` can read from and control Music.app (one-time TCC prompt), and measure library enumeration time on the real library.
   - (Optional) Attempt `MusicAuthorization.request()` to confirm whether MusicKit works here at all; record the outcome.
   - Output: go/no-go on AppleScript path and a measured index-build time.

2. **Scaffold.** SwiftPM package, `Info.plist`, `Scripts/build-app.sh`, `LSUIElement` agent app, menu-bar status item (Quit / Open). Runs with an empty window.

3. **Hotkey + panel shell.** Carbon hotkey (default **⌘⌥Space**), `PalettePanel` show/hide/center-on-active-screen, `Esc` closes, panel becomes key for typing, focus-loss dismiss, `.glassEffect` container with `NSVisualEffectView` fallback.

4. **Commands.** `Command` enum, `CommandParser`, `CommandExecutor` wired to `MusicController`. Implement `pause/resume/next/previous/shuffle` end-to-end via AppleScript, with `MockMusicController` for tests.

5. **Library index + search + ranking.** Enumerate library → `LibraryIndex` → disk cache; implement `Ranking`; unit-test exact-vs-album, prefix, substring, typo, tie-breakers.

6. **Catalog fallback.** `ITunesCatalogProvider` against the public iTunes Search API (no auth), debounced, merged after library results.

7. **`play <song>` end-to-end.** Resolve selected candidate → play library track by persistent ID (fast) or open catalog URL in Music.app.

8. **UI polish.** Result rows + artwork (async, cached, placeholder), selection highlight, empty/error/loading states, command hints, footer key legend, Reduce Motion/Transparency behavior.

9. **Test pass + smoke checklist.** Unit tests green; manual checklist (§7) completed.

Rough effort: steps 1–4 ≈ foundation, 5–7 ≈ the core product, 8–9 ≈ polish/verification.

---

## 5. Important macOS / MusicKit considerations

### Playback
- **`SystemMusicPlayer` is unavailable on macOS.** `AppleScriptMusicController` is the substitute and is the *correct* semantic equivalent (it drives the real Music app).
- `ApplicationMusicPlayer` is only a fallback if the user explicitly wants in-app playback; it does **not** control Music.app.
- Play library tracks by **persistent ID**: `tell application "Music" to play (some track of library playlist 1 whose persistent ID is "…")` — precise and fast vs. name matching.
- Catalog tracks: `open location "<music.apple.com URL>"` hands playback to Music.app; requires an active Apple Music subscription.

### Authorization / signing
- AppleScript automation needs a one-time **Automation (TCC)** grant; add `NSAppleEventsUsageDescription` to `Info.plist`.
- Ad-hoc signed apps can be re-prompted after each rebuild because the code hash changes; note for the dev loop (may need a stable signing identity later).
- MusicKit (`MusicAuthorization`, library/catalog requests) requires the **MusicKit App Service entitlement** and a Music user token → needs a paid developer team. Only **0 valid signing identities** exist here, so MusicKit is treated as optional/feature-flagged, never on the MVP critical path.
- Do **not** sandbox for MVP; if sandboxing later, add `com.apple.security.automation.apple-events`.

### Library enumeration
- AppleScript enumeration of a large library can take seconds. Cache to `~/Library/Application Support/Cuebar/library-index.json`, rebuild on launch in the background, keep the UI usable with a lightweight indexing indicator.
- Only enumerate `name`, `artist`, `album`, `duration`, `persistent ID` to keep it cheap.

### Panel + Liquid Glass pitfalls (from the skill references)
- Apply `.glassEffect()` to the **single container** (navigation-layer surface), never to list rows. Glass does not belong on content.
- Glass can degrade to a plain blur when the app is inactive — back the panel with `NSVisualEffectView` so it still looks intentional; verify with the panel non-key.
- Use `.tint(.clear)` on any `.buttonStyle(.glass)` on macOS.
- Use `.rect(cornerRadius: .containerConcentric)` so glass corners match the panel.
- Respect `accessibilityReduceTransparency`/`Reduce Motion` (the system adapts automatically; expose `.identity` as a manual override if needed).
- `.nonactivatingPanel` + `canBecomeKey = true` lets Cuebar receive keystrokes without stealing app activation, so focus returns to the previous app on close (Spotlight behavior).

### Keyboard nav
- Prefer SwiftUI `.onKeyPress(.upArrow/.downArrow/.return)` on the results list; if the focused `TextField` swallows arrow keys, fall back to an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in the window controller (scoped to the panel).

### Other
- Agent app: `LSUIElement = 1` (no Dock icon); provide Quit via a status-bar item.
- Network politeness: debounce catalog queries (~120 ms) and cancel in-flight tasks.
- No Apple Music subscription: library playback still works; surface a clear error for catalog-only matches.

---

## 6. Song search / ranking logic

### 6.1 Normalization
`lowercased` + `.diacriticInsensitive` + `.caseInsensitive` folding; strip punctuation except spaces; collapse whitespace. Query tokenized on whitespace.

### 6.2 Candidate scoring

| Signal | Score |
|---|---|
| Title == query (normalized) | **1000** |
| Title starts with query | 850 |
| All query tokens match title tokens in order (prefix-style) | 700 |
| Title contains query substring | 600 |
| Fuzzy (Damerau–Levenshtein on normalized title, similarity ≥ 0.60) | `round(similarity * 500)` |
| Artist contains a query token | +150 |
| Album title contains query | +30 |

### 6.3 Deterministic tie-breakers
`score desc` → **kind rank** (song `0`, album `1`, artist `2`) → **source rank** (library `0`, catalog `1`) → normalized title `asc` → stable id `asc`.

- Explicit type weight (song > album) guarantees the mandated rule: an exact song title outranks an exact album title.
- Library-before-catalog source weight implements "library first"; the catalog fallback is only surfaced when the library has no good match, but is always *ranked* below an equal library match.

### 6.4 Flow for `play <query>`
1. Parse → `.play(query)`.
2. Start library search against the in-memory index (local, sub-50 ms target) → rank → show immediately.
3. Start catalog search concurrently (debounced); on arrival, rank and merge; library items keep priority on ties.
4. `Enter` executes the selected candidate: library → play by persistent ID; catalog → `open location` URL.
5. Zero results → friendly empty state ("No match in library or Apple Music catalog").

### 6.5 Testability
`Ranking` is a pure function over `[MusicCandidate]` + query string → no I/O, fully unit-testable and deterministic. This is the highest-risk logic and gets the most tests.

---

## 7. How the MVP will be tested

### Automated (SwiftPM test target)
- **`CommandParserTests`**: `play take on me`, bare text → play, unknown verbs, `shuffle on/off`, case/whitespace, empty input.
- **`RankingTests`** (table-driven / golden):
  - exact song title beats album of the same name (the explicit requirement);
  - prefix beats substring beats fuzzy;
  - library beats catalog on equal score;
  - typo tolerance (`take on me` vs `take on me`), including a near-miss within the similarity threshold;
  - deterministic ordering across repeated runs and shuffled input order.
- **`SearchServiceTests`**: `MockSearchProvider`/`MockMusicController` verify merge order, cancellation of stale queries, conflict resolution, and error propagation.

### Manual smoke checklist (run `Scripts/run.sh`)
1. Launch → no Dock icon; status item present.
2. Press **⌘⌥Space** from another app → panel appears centered, search focused, glass renders.
3. `pause` / `resume` / `next` / `previous` / `shuffle` affect the real Music app.
4. `play take on me` → correct song plays in Music.app (verify title/artist in Music).
5. Type a typo → still resolves to the correct song.
6. Search a song absent from the library → catalog result appears and plays.
7. `↑`/`↓` change selection; `Enter` executes; `Esc` closes and returns focus to the prior app; clicking outside closes.
8. Empty/gibberish query → clean empty state, no crash.
9. Deny Automation permission once → clear, actionable error message.
10. Shuffle result ordering is stable across repeated identical searches.
11. Reduced Transparency/Contrast and Reduce Motion enabled → panel stays legible and calm.

### Performance targets
- Panel shows in < 150 ms after hotkey.
- Library search/ranking < 50 ms on a typical library.
- Catalog round-trip annotated with a subtle loading state; stale results discarded.

---

## 8. Decisions (resolved)

1. **Playback engine** — ✅ **AppleScript → Music.app.** `SystemMusicPlayer` cannot be used on macOS; this is the semantic equivalent and controls the real Music app.
2. **Project format** — ✅ **SwiftPM package + `Scripts/build-app.sh`.** `swift build` → assemble `Cuebar.app` (Info.plist, `LSUIElement`, ad-hoc codesign). No `.xcodeproj` authored or needed for the MVP.
3. **Library search source** — ✅ **AppleScript enumeration + disk-cached `LibraryIndex`.** No signing/entitlement required.
4. **Shuffle semantics** — ✅ **`shuffle` toggles**; `shuffle on` / `shuffle off` also accepted.

MusicKit (`ApplicationMusicPlayer` / `MusicLibrarySearchRequest`) remains behind the `MusicController`/`SearchProvider` protocols as an optional, feature-flagged provider for a future signed/entitled build — not on the MVP path.

---

## 9. Implementation notes (final, as built)

Everything in this plan was implemented. See `README.md` for build/run/test
instructions and the full architecture. Notable refinements made during
implementation:

1. **Catalog is a true fallback.** The catalog (public iTunes Search API) is
   only queried when the library has no *strong* (non-fuzzy) match, matching the
   "search library first, fall back when necessary" requirement. Strong means an
   exact, prefix, token-in-order or substring title match (base score ≥ 550).
2. **Artist/album matching added.** "play a-ha" works even though the title does
   not match: artist/album containment gives a base score (500/400).
3. **Live-verified numbers on this machine:** library enumeration = 6310 tracks
   in ~0.26 s (570 KB over one bulk Apple Event per property); `persistent ID`
   lookup ≈ 0.1 s round-trip. Enumeration and playback-by-`persistent ID` were
   validated against the real Music.app.
4. **Hotkey is ⌘⌥Space** (changed from ⌥Space at the user's request).
5. **Verified:** 27 unit tests pass; `swift build` is warning-free; the app
   launches as an agent, indexes the real library and caches it; the palette
   renders with library-first results, catalog fallback and typo tolerance
   (confirmed via offscreen panel snapshots).
6. **Not exercised end-to-end:** actually starting audio playback (Enter on a
   result) was left for a manual check to avoid changing the user's playback
   state. The AppleScript is syntax-validated and uses the verified
   `some track ... whose persistent ID is` reference form.
7. **Debug affordances** (`#if DEBUG`): `CUEBAR_SHOW_ON_LAUNCH`,
   `CUEBAR_PREVIEW_QUERY`, `CUEBAR_SNAPSHOT`.
