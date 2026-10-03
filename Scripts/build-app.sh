#!/usr/bin/env bash
# Builds Cuebar and assembles a runnable .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP_NAME="Cuebar"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "error: built binary not found at $BIN" >&2
  exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Stamp the build channel so non-release builds can show an "Experimental"
# badge in the palette. An explicit CUEBAR_BUILD_CHANNEL wins (release.sh sets
# it), otherwise the current branch decides.
CHANNEL="${CUEBAR_BUILD_CHANNEL:-}"
if [[ -z "$CHANNEL" ]]; then
  BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$BRANCH" == "experimental" || "$BRANCH" == exp* ]]; then
    CHANNEL="experimental"
  else
    CHANNEL="release"
  fi
fi
/usr/libexec/PlistBuddy -c "Delete :CuebarBuildChannel" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CuebarBuildChannel string $CHANNEL" "$APP/Contents/Info.plist"
echo "==> build channel: $CHANNEL"

echo "==> ad-hoc codesign"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "warning: codesign failed (the app may still run)"

echo "==> done: $APP"
