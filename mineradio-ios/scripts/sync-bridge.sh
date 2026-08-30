#!/usr/bin/env bash
# Syncs shared Bridge assets into the iOS bundle Resources.
# Run from the repo root or from mineradio-ios/.
#
#   ./mineradio-ios/scripts/sync-bridge.sh
#
# What it does:
#   - copies ../Mineradio-Bridge-1.4.1/**  ->  MineRadioWeb/Resources/bridge/
#   - refreshes host/inject.js from the Android built copy (keeps page-injection
#     logic identical across mobile platforms)
#   - copies the 1024 app icon into Assets.xcassets
#   - leaves host/runner.html (iOS-specific host) untouched
set -euo pipefail

# Resolve repo root (parent of the mineradio-ios directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"

BRIDGE_SRC="$REPO_ROOT/Mineradio-Bridge-1.4.1"
ANDROID_HOST="$REPO_ROOT/mineradio-android/app/src/main/assets/host/inject.js"
ICON_SRC="$REPO_ROOT/assets/mr-icon-1024.png"

RES_DIR="$IOS_DIR/MineRadioWeb/Resources"
BRIDGE_DST="$RES_DIR/bridge"
HOST_DST="$RES_DIR/host"
ICON_DST="$IOS_DIR/MineRadioWeb/Assets.xcassets/AppIcon.appiconset/mr-icon-1024.png"

if [[ ! -d "$BRIDGE_SRC" ]]; then
  echo "[sync-bridge] WARNING: source not found: $BRIDGE_SRC — skipping bridge sync (build will still compile)" >&2
  exit 0
fi

echo "[sync-bridge] syncing Bridge from $BRIDGE_SRC -> $BRIDGE_DST"
rm -rf "$BRIDGE_DST"
mkdir -p "$BRIDGE_DST"
# Use rsync if available (preserves structure), else cp -R.
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$BRIDGE_SRC"/ "$BRIDGE_DST"/
else
  cp -R "$BRIDGE_SRC/." "$BRIDGE_DST/"
fi

echo "[sync-bridge] refreshing host/inject.js"
mkdir -p "$HOST_DST"
if [[ -f "$ANDROID_HOST" ]]; then
  cp "$ANDROID_HOST" "$HOST_DST/inject.js"
elif [[ -f "$HOST_DST/inject.js" ]]; then
  echo "[sync-bridge] warning: android inject.js missing; keeping committed copy"
else
  echo "[sync-bridge] error: no host/inject.js available" >&2
  exit 1
fi

echo "[sync-bridge] copying app icon"
mkdir -p "$(dirname "$ICON_DST")"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$ICON_DST"
else
  echo "[sync-bridge] warning: $ICON_SRC missing (icon left as-is)"
fi

echo "[sync-bridge] done. (host/runner.html is iOS-specific and was NOT overwritten.)"
