#!/bin/bash
# Takes the README screenshots from Sift's demo mode, in light and dark, into
# docs/images/<view>-light.png and <view>-dark.png.
#
# Never take README screenshots from real data: this script only launches
# Sift with -demo, which reads the sample data in Application Support/Sift-Demo.
#
# Needs: Sift installed in /Applications (scripts/build-app.sh builds it) and
# Screen Recording permission for the terminal that runs this. It builds
# nothing in the repo. It quits a running Sift first and quits the demo
# instance at the end.
#
# Usage: scripts/screenshots.sh

set -euo pipefail

APP=/Applications/Sift.app
BUNDLE_ID=app.sift.Sift
SIZE=1440x900
OUT="$(cd "$(dirname "$0")/.." && pwd)/docs/images"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -d "$APP" ] || { echo "Sift is not in /Applications. Run scripts/build-app.sh first." >&2; exit 1; }
mkdir -p "$OUT"

# A tiny helper that prints the id of the frontmost normal window of a process.
cat > "$TMP/winid.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1]) ?? 0
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    let bounds = w[kCGWindowBounds as String] as? [String: Any]
    if let height = bounds?["Height"] as? Double, height > 200, let id = w[kCGWindowNumber as String] as? Int {
        print(id)
        exit(0)
    }
}
exit(1)
SWIFT
xcrun swiftc -O -o "$TMP/winid" "$TMP/winid.swift"

quit_sift() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -x Sift >/dev/null || return 0
        sleep 0.25
    done
    echo "Sift did not quit. Quit it by hand and run this again." >&2
    exit 1
}

# shot <file name> <demo view> <appearance> <seconds to settle>
shot() {
    local name=$1 view=$2 mode=$3 wait=$4
    quit_sift
    open -n -a "$APP" --args -demo -demoView "$view" -demoSize "$SIZE" -demoAppearance "$mode"
    local pid=""
    for _ in $(seq 1 40); do
        pid=$(pgrep -n -x Sift || true)
        [ -n "$pid" ] && break
        sleep 0.25
    done
    [ -n "$pid" ] || { echo "Sift did not start." >&2; exit 1; }
    sleep "$wait"
    local id
    id=$("$TMP/winid" "$pid") || { echo "No Sift window found for $name." >&2; exit 1; }
    screencapture -o -x -l "$id" "$OUT/$name-$mode.png"
    echo "docs/images/$name-$mode.png"
}

for mode in light dark; do
    shot overview          graph                 "$mode" 5
    shot theme             "theme:Climate Tech"  "$mode" 6
    shot list              list:reading-list     "$mode" 4
    shot settings-library  settings:library      "$mode" 4
    shot settings-outputs  settings:outputs      "$mode" 4
done

quit_sift
echo "Done."
