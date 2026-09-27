#!/usr/bin/env bash
# Builds and launches Cuebar.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/build-app.sh"

echo "==> launching Cuebar"
open "$ROOT/build/Cuebar.app"
