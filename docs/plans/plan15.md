# Plan 15 — Update system (check GitHub, notify, install)

Status: **implemented.** Companions: plan.md … plan14.md.

Implemented in this iteration:

- **Core**: `AppVersion` (semver parse/compare), `UpdateInfo`/`UpdateCheckResult`,
  `UpdateChecker` (GitHub `releases/latest`, injectable loader), `ReleaseVerifier`
  (Ed25519 via CryptoKit) + `UpdateKey` (embedded public key), `SwapScript`
  (pure builder), `UpdatePreferenceStore`, `UpdateFeedback`.
- **Shell**: `UpdateController` (check → download → verify → swap → relaunch),
  an injected **"Install Update (x.y.z)"** command row, a **Settings → Software
  Update** row (current version, Check, Install), auto-check ~5 s after launch.
- **Release tooling**: `Scripts/make-update-key.sh` (key pair + public key) and
  `Scripts/release.sh` (bump → build → `Cuebar.zip` + `.sig` → commit/push →
  `gh release`).
- Tests: **178** passing (was 164). Verified openssl ↔ CryptoKit signature
  interop (valid → VERIFIED, tampered → FAILED).

> Needs a one-time key setup (see below) before installation will work; until the
> public key is embedded, installs abort with "updates aren't signed".

---

## Goal

On launch (and on demand) Cuebar checks the latest GitHub release; when a newer
version exists it **notifies** the user and can **download, verify, install and
relaunch** into the new version — i.e. updating actually works, not just a
notification.

Repo: `tomatosoup83/cuebar`. Current version lives in
`Resources/Info.plist` (`CFBundleShortVersionString`), e.g. `0.4.0`.

## Feasibility & constraints

- **GitHub API** `GET /repos/tomatosoup83/cuebar/releases/latest` returns
  `tag_name`, `body`, `html_url`, `assets[]` (`name`, `browser_download_url`).
  Unauthenticated limit is 60 req/h — fine. GitHub requires a `User-Agent`.
- **Stable asset URL** avoids parsing asset URLs:
  `https://github.com/tomatosoup83/cuebar/releases/latest/download/Cuebar.zip`
  (302-redirects to the latest asset). **Release flow must upload a fixed name**
  (see below).
- **Self-replace** works because Cuebar is unsandboxed, but a running bundle
  can't overwrite itself: a small **helper script** must wait for the app to
  quit, swap the bundle, and relaunch.
- **Trust**: downloading and running code needs verification. GitHub HTTPS alone
  is weak if the account/token is compromised → recommend a **signature**.
- **Writable location**: swapping `/Applications/Cuebar.app` needs write access;
  if it isn't writable, fall back to opening the release page.

## Design

### Core (testable)

- **`AppVersion`** — parse `"0.4.0"` / `"v0.5.0"` → `(major, minor, patch)`;
  `Comparable`, tolerant of extra suffixes (`0.5.0-beta`).
- **`UpdateInfo`** — `version`, `downloadURL`, `releaseURL`, `notes`.
- **`UpdateChecker`** — `async func latest() throws -> UpdateInfo?`; fetches the
  API (URLSession injected), decodes JSON, picks the `Cuebar.zip` asset, returns
  nil when up to date. Separate `check(current:)` returns `.upToDate` /
  `.available(UpdateInfo)`.
- **`ReleaseVerifier`** — verifies the downloaded archive against the embedded
  public key (Ed25519 via CryptoKit) — signature fetched from the release assets
  (`Cuebar.zip.sig` or `SHA256SUMS`).
- **`SwapScript`** — pure builder for the helper shell script (below), so its
  text is unit-tested.
- **`UpdatePreferenceStore`** — "check automatically" flag, mirroring
  `HotKeyStore`.

### Shell

- Check on launch (debounced ~5 s, after the index settles) if enabled; also on
  demand via a `check for updates` command and a **Settings → Software Update**
  row.
- **Notify via the existing toast**: `Cuebar 0.5.0 is available`. Because
  `ToastPanel` is click-through, the *action* lives in the palette:
  - an **"Install Update (0.5.0)"** command row (Return installs), and
  - a **Settings → Software Update** row with **Check** / **Install** buttons.
- Install flow with toasts: *Downloading…* → *Verifying…* → *Installing — Cuebar
  will relaunch*.

### Update flow

1. `UpdateChecker.check(current: AppVersion.bundle!)`.
2. If newer → toast + make the "Install Update" row available.
3. Download `Cuebar.zip` to a temp dir (URLSession, progress optional).
4. **Verify** the Ed25519 signature against the embedded key; also sanity-check
   the unzipped `Cuebar.app`'s `CFBundleShortVersionString` matches.
5. Write + run the **swap script** detached, then `NSApp.terminate`:

   ```sh
   #!/bin/sh
   DEST="/Applications/Cuebar.app"; NEW="$TMP/Cuebar.app"; BAK="$TMP/Cuebar.bak"
   while pgrep -x Cuebar >/dev/null; do sleep 0.2; done   # wait for us to quit
   rm -rf "$BAK"; mv "$DEST" "$BAK" 2>/dev/null
   if ditto "$NEW" "$DEST" && [ -d "$DEST" ]; then
       rm -rf "$BAK"
   else
       rm -rf "$DEST"; mv "$BAK" "$DEST"        # roll back on failure
   fi
   xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
   open "$DEST"
   ```
6. New version launches; the old process is gone. On any failure, keep the old
   bundle and toast an error (or open the release page).

## Release-flow changes

- `Scripts/release.sh` (new): build app → zip as **`Cuebar.zip`** (fixed name) →
  sign → `gh release create <tag> Cuebar.zip Cuebar.zip.sig`.
- Keep the versioned asset too if desired, but the updater depends on
  **`Cuebar.zip`** + **`Cuebar.zip.sig`**.
- One-time: generate an Ed25519 key pair; store the **public** key in the app
  (`UpdateKey`), keep the **private** key in the maintainer's keychain/1Password.

## Security

- Recommended: **Ed25519 signature** of the archive, public key embedded; the app
  refuses unsigned/mismatched downloads. CryptoKit provides
  `Curve25519.Signing` (no dependency).
- Fallback (simpler, weaker): verify HTTPS + that the unzipped bundle's version
  equals the advertised tag. Documented as insecure against a compromised
  release.
- Strip `com.apple.quarantine` after install (the build is ad-hoc signed, not
  notarised).

## Files

- **New** `Sources/CuebarCore/AppVersion.swift`, `UpdateChecker.swift`,
  `ReleaseVerifier.swift`, `SwapScript.swift`, `UpdatePreferenceStore.swift`
- **New** `Sources/Cuebar/UpdateController.swift` (orchestrates check/install),
  `UpdateKey.swift` (embedded public key), `SettingsView` update row
- **New** `Scripts/release.sh`
- **New** tests: `AppVersionTests`, `UpdateCheckerTests` (stubbed URLSession),
  `SwapScriptTests`, `UpdatePreferenceStoreTests`
- `Sources/CuebarCore/CommandCatalog.swift` — "Check for Updates" command
- `Sources/Cuebar/AppDelegate.swift` — launch check wiring
- `Sources/Cuebar/PaletteModel.swift` — install command row + toasts
- `README.md` / `README.dev.md`

## Tests

- `AppVersion`: parses `v0.4.0`/`0.5.0`; orders `0.4.10 > 0.4.9`; tolerates
  suffixes; ignores non-numeric.
- `UpdateChecker`: decodes a sample release JSON (fixture); picks `Cuebar.zip`;
  "up to date" → nil; bad status → throws.
- `ReleaseVerifier`: valid signature passes (test key pair); tampered bytes fail.
- `SwapScript`: contains the wait loop, backup/rollback, quarantine strip,
  `open`.
- `UpdatePreferenceStore`: default + round-trip.
- Existing 164 stay green.

## Manual verification ("make sure updating works")

1. Publish a throwaway **v0.4.1** with the fixed `Cuebar.zip` + signature.
2. From a 0.4.0 build, run check → toast → Install.
3. Confirm: download → verify → Cuebar quits → app is replaced → relaunches as
   0.4.1; the old bundle is gone; re-running check says up to date.
4. Failure drill: tamper the signature → install aborts with an error toast and
   the old app still runs.
5. Read-only location: point `DEST` at a non-writable dir → falls back to
   opening the release page.

## Decisions locked with the user

1. **Ed25519-signed updates.** Releases are signed; the app verifies against an
   embedded public key before installing. One-time setup: generate a key pair,
   keep the private key in the maintainer's keychain/1Password, embed the public
   key in `UpdateKey.swift`.
2. **Auto-check on launch** (~5 s after startup, when enabled); also on demand.
3. **Action surface:** an in-palette **"Install Update (x.y.z)"** command row
   (Return installs) plus a **Settings → Software Update** row. (Toasts stay
   click-through — they only notify.)
4. **Auto install + relaunch**: download → verify → swap the bundle → relaunch.

## Out of scope

- Delta/patch updates, beta channels, staged rollout.
- Notarisation (would still need a paid Apple Developer account).
- Windows/Linux.
