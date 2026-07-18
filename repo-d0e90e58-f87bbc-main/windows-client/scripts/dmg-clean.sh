#!/usr/bin/env bash
# Unmount stale DMG volumes left by interrupted Tauri builds.
set -euo pipefail

for vol in "/Volumes/Plink" "/Volumes/Plink 1"; do
  if [[ -d "$vol" ]]; then
    echo "Detaching $vol..."
    hdiutil detach "$vol" -force 2>/dev/null || true
  fi
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -f "$ROOT/src-tauri/target/release/bundle/macos/rw."*.dmg 2>/dev/null || true

echo "DMG cleanup done."