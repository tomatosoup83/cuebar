#!/usr/bin/env bash
#
# Generates the Ed25519 key pair used to sign Cuebar updates.
#
# The private key stays on this machine (default ~/.cuebar/ed25519.pem, override
# with CUEBAR_KEY_DIR). The printed public key is pasted into
# Sources/CuebarCore/ReleaseVerifier.swift (UpdateKey.publicKeyBase64):
# Cuebar verifies every downloaded update against it.
#
set -euo pipefail

DIR="${CUEBAR_KEY_DIR:-$HOME/.cuebar}"
KEY="$DIR/ed25519.pem"
mkdir -p "$DIR"

if [ -f "$KEY" ]; then
    echo "A private key already exists at:"
    echo "    $KEY"
    echo "Refusing to overwrite it. Move it aside first to rotate the key."
else
    openssl genpkey -algorithm ed25519 -out "$KEY"
    chmod 600 "$KEY"
    echo "Wrote a new private key to:"
    echo "    $KEY"
    echo "Keep it secret (1Password / Keychain); it signs every release."
fi

PUB="$(openssl pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64)"

echo
echo "Paste this into Sources/CuebarCore/ReleaseVerifier.swift:"
echo
echo "    public static let publicKeyBase64 = \"$PUB\""
echo
