#!/usr/bin/env bash
#
# Builds Cuebar, signs the archive for the in-app updater, and publishes a
# GitHub release. The updater expects two assets with fixed names:
#   Cuebar.zip      the built app bundle
#   Cuebar.zip.sig  base64 Ed25519 signature of Cuebar.zip
#
# Usage:  Scripts/release.sh 0.5.0
# Needs:  the private key from Scripts/make-update-key.sh (default
#         ~/.cuebar/ed25519.pem, override with CUEBAR_UPDATE_KEY), and an
#         authenticated `gh`.
#
set -euo pipefail

VERSION="${1:?usage: Scripts/release.sh <version, e.g. 0.5.0>}"
KEY="${CUEBAR_UPDATE_KEY:-$HOME/.cuebar/ed25519.pem}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f "$KEY" ]; then
    echo "No signing key at $KEY"
    echo "Run Scripts/make-update-key.sh first."
    exit 1
fi

MAJOR="$(echo "$VERSION" | cut -d. -f1)"
MINOR="$(echo "$VERSION" | cut -d. -f2)"
PATCH="$(echo "$VERSION" | cut -d. -f3)"
BUILD=$(( MAJOR * 10000 + MINOR * 100 + PATCH ))

echo "==> Version $VERSION (build $BUILD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist
/usr/bin/sed -i '' -E "s#Cuebar/[0-9]+\.[0-9]+ \(macOS\)#Cuebar/${MAJOR}.${MINOR} (macOS)#" Sources/CuebarCore/SearchProviders.swift

echo "==> Building"
./Scripts/build-app.sh

echo "==> Packaging Cuebar.zip"
rm -f build/Cuebar.zip build/Cuebar.zip.sig build/Cuebar.zip.sig.bin
/usr/bin/ditto -c -k --keepParent build/Cuebar.app build/Cuebar.zip

echo "==> Signing"
openssl pkeyutl -sign -inkey "$KEY" -rawin -in build/Cuebar.zip -out build/Cuebar.zip.sig.bin
base64 < build/Cuebar.zip.sig.bin > build/Cuebar.zip.sig
rm -f build/Cuebar.zip.sig.bin

echo "==> Committing + pushing"
git add -A
if git diff --cached --quiet; then
    echo "    (nothing to commit)"
else
    git commit -m "Release v$VERSION"
fi
git push origin HEAD

echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" build/Cuebar.zip build/Cuebar.zip.sig \
    --title "Cuebar v$VERSION" \
    --notes "Cuebar $VERSION. See the repository for details."

echo
echo "Done: released v$VERSION"
