#!/usr/bin/env bash
# Capture App Store screenshots from a simulator.
#
# Drives the app through the DEBUG launch arguments, because there is no other way
# to put a particular tab and a particular asset on screen from outside: a
# hawker:// deep link makes the simulator raise a confirmation dialog, and simctl
# cannot tap it.
#
#   ./Tools/capture-screenshots.sh <device-udid> <output-dir>
#
# The simulator's cache is seeded from a completed ingest first, so the shots show
# real data instead of a loading state. Run the harness once to produce it:
#
#   ./HawkerKit/.build/release/hawker-ingest 400 assets.json
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="${1:?usage: capture-screenshots.sh <udid> <out-dir>}"
OUT="${2:?}"
ASSETS="${ASSETS:-assets.json}"
BUNDLE="com.mdeller.hawker"
mkdir -p "$OUT"

# Seed the cache so the app opens on data. Without this every shot is a progress bar:
# a cold ingest takes many minutes and the App Store does not want a picture of that.
if [ -f "$ASSETS" ]; then
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    sleep 4
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    CONT=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    mkdir -p "$CONT/Library/Caches"
    cp "$ASSETS" "$CONT/Library/Caches/hawker-assets.json"
    echo "seeded cache from $ASSETS"
else
    echo "WARNING: $ASSETS not found; shots will show the ingest running" >&2
fi

# Status bar frozen at the conventional time, and no stray carrier or battery state.
xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 \
    >/dev/null 2>&1 || true

shot() {
    local name="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep "${SETTLE:-12}"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
    echo "  $name.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null \
        | awk '/pixel/{printf "%s ", $2}')"
}

echo "Capturing from $UDID into $OUT"
shot "1-stall"                                   # the graveyard, browsable
shot "2-postmortem" -AppAsset CHEMBL276711       # Semaxanib: evidence highlighted
shot "3-graveyard"  -AppTab graveyard            # the business-vs-biology headline
shot "4-shelf"      -AppTab shelf                # lapsed horizons, with the caveat
shot "5-method"     -AppMethod YES               # the app showing its own working
