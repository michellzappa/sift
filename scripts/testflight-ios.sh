#!/bin/bash
set -euo pipefail

# Sift for iPhone to TestFlight: archive, export an App Store IPA, upload.
# Runs on the laptop (signing stays here) under the machine lock.
#
#   ./scripts/testflight-ios.sh "What to test in this build"
#
# The version is MARKETING_VERSION in prototypes/ios-deck/project.yml. The
# build number is the commit count, so every upload is higher than the last.
# Needs: the asc CLI signed in (asc auth doctor), the App Store Connect app
# "Sift" (bundle com.centaur-labs.sift), Xcode signed in to team 992N457T8D.

NOTES="${1:-Bug fixes and improvements.}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DECK="$ROOT/prototypes/ios-deck"
OUT="$DECK/build/testflight"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"

APP_ID="$(asc apps list --bundle-id com.centaur-labs.sift --output json | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("data",d); print(d[0]["id"])')"
[[ -n "$APP_ID" ]] || { echo "No App Store Connect app for com.centaur-labs.sift"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$DECK"
xcodegen generate -q

cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>992N457T8D</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

echo "==> Archiving Sift for iPhone (build $BUILD_NUMBER)"
build-lock "sift-ios-archive" xcodebuild archive \
    -project SiftDeck.xcodeproj -scheme SiftDeck -configuration Release \
    -destination "generic/platform=iOS" -archivePath "$OUT/Sift.xcarchive" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD_NUMBER" 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"
[[ -d "$OUT/Sift.xcarchive" ]] || { echo "Archive failed"; exit 1; }

echo "==> Exporting the IPA"
build-lock "sift-ios-export" xcodebuild -exportArchive -archivePath "$OUT/Sift.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT" \
    -allowProvisioningUpdates 2>&1 | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"
IPA="$(ls "$OUT"/*.ipa | head -1)"

echo "==> Uploading $IPA"
asc builds upload --app "$APP_ID" --ipa "$IPA" --test-notes "$NOTES" --locale "en-US" --wait
