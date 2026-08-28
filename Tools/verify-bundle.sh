#!/usr/bin/env bash
# Check that a built HAWKER app actually contains what it needs to work.
#
# ARCHIVE SUCCEEDED says nothing about the contents. This checker is
# negative-tested: run it against a bundle with a resource deleted and it must
# fail. A check that has only ever passed is not a check.
#
#   ./Tools/verify-bundle.sh /path/to/HAWKER.app
set -uo pipefail

APP="${1:?usage: verify-bundle.sh /path/to/HAWKER.app}"
FAIL=0

# macOS nests everything under Contents/; iOS, watchOS and visionOS do not.
if [ -d "$APP/Contents/MacOS" ]; then
    RES="$APP/Contents/Resources"
    ROOT="$APP/Contents/Resources"
else
    RES="$APP"
    ROOT="$APP"
fi

ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=1; }

check_file() {
    local path="$1" min="$2"
    if [ ! -e "$path" ]; then
        bad "missing: ${path#"$APP"/}"
        return
    fi
    local size
    size=$(find "$path" -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
    if [ -z "$size" ] || [ "$size" -lt "$min" ]; then
        bad "too small (${size:-0} < $min): ${path#"$APP"/}"
    else
        ok "${path#"$APP"/}  ($size bytes)"
    fi
}

echo "Verifying $APP"

# The exemplar bank is the classifier's fallback. It lives in HawkerKit's own
# resource bundle, whose name differs between SwiftPM and Xcode integrations, so
# it is located rather than assumed.
BANK=$(find "$APP" -name "exemplar_bank.json" 2>/dev/null | head -1)
if [ -n "$BANK" ]; then
    check_file "$BANK" 100000
else
    bad "exemplar_bank.json not found anywhere in the bundle"
fi

# The compiled icon at the bundle ROOT, not the .appiconset: an empty appiconset
# still builds and ships an app with no icon.
#
# Which artefact to expect depends on the PLATFORM, read from the Info.plist. An
# earlier version guessed it from the path, which works for a build inside
# Debug-xrsimulator and then reports a perfectly good visionOS archive as missing
# its iPhone icons.
PLIST="$APP/Info.plist"
[ -f "$APP/Contents/Info.plist" ] && PLIST="$APP/Contents/Info.plist"
PLATFORM=$(plutil -extract DTPlatformName raw "$PLIST" 2>/dev/null || echo "")

case "$PLATFORM" in
    macosx)
        check_file "$RES/AppIcon.icns" 20000 ;;
    watchos|watchsimulator|xros|xrsimulator)
        # watchOS and visionOS keep their icons inside Assets.car only, and
        # visionOS's is a layered stack rather than a flat image.
        check_file "$ROOT/Assets.car" 50000 ;;
    iphoneos|iphonesimulator)
        check_file "$ROOT/AppIcon60x60@2x.png" 2000
        check_file "$ROOT/AppIcon76x76@2x~ipad.png" 2000 ;;
    *)
        bad "could not read DTPlatformName from $PLIST" ;;
esac

# A companion watch app must actually be inside the iOS app, not merely built.
if [ -f "$APP/Info.plist" ] && plutil -extract WKWatchKitApp raw "$APP/Info.plist" >/dev/null 2>&1; then
    :  # this IS the watch app
elif [ -d "$APP/Watch" ]; then
    W=$(find "$APP/Watch" -maxdepth 1 -name "*.app" | head -1)
    if [ -n "$W" ]; then
        ok "embedded watch app: ${W#"$APP"/}"
        WID=$(plutil -extract CFBundleIdentifier raw "$W/Info.plist" 2>/dev/null)
        [ "$WID" = "com.mdeller.hawker.watchkitapp" ] \
            && ok "watch bundle id $WID" || bad "watch bundle id is '$WID'"
    else
        bad "Watch/ exists but holds no .app"
    fi
fi

# Signing authority. A simulator build is ad-hoc signed and reports no Authority
# line at all, which is correct there and must not read as a failure.
SIGINFO=$(codesign -dv --verbose=2 "$APP" 2>&1)
AUTH=$(printf '%s' "$SIGINFO" | grep "^Authority=" | head -1 | cut -d= -f2-)
if [ -n "$AUTH" ]; then
    ok "codesign authority: $AUTH"
    case "$AUTH" in
        *"Apple Development"*)
            bad "signed with Apple Development: a Release archive must use Apple Distribution" ;;
    esac
elif printf '%s' "$SIGINFO" | grep -q "linker-signed\|Signature=adhoc"; then
    printf '  note  ad-hoc signed (expected for a simulator build)\n'
else
    bad "not signed"
fi

# The app's OWN profile, not the embedded watch app's: an unqualified find walks
# into Watch/ first and reports the wrong one.
PROFILE=""
for candidate in "$APP/embedded.mobileprovision" "$APP/Contents/embedded.provisionprofile"; do
    [ -f "$candidate" ] && { PROFILE="$candidate"; break; }
done
if [ -n "$PROFILE" ]; then
    NAME=$(security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Name raw - 2>/dev/null)
    [ -n "$NAME" ] && ok "profile: $NAME" || ok "profile present"
else
    printf '  note  no embedded profile (expected for a simulator build)\n'
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$FAIL"
