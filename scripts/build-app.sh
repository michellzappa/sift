#!/bin/zsh
# Build Sift.app and install it to /Applications, signed with the stable
# Apple Development identity, so the Full Disk Access grant survives rebuilds.
#
#   ./scripts/build-app.sh            # Release -> /Applications/Sift.app
#   ./scripts/build-app.sh --debug
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
config=Release
[[ "${1:-}" == "--debug" ]] && config=Debug

cd "$here"
xcodegen generate --quiet
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
build-lock "sift build-app" xcodebuild -project Sift.xcodeproj -scheme Sift -configuration "$config" \
  -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="build/DerivedData/Build/Products/$config/Sift.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
codesign --force --sign "Apple Development" --entitlements Sift/Resources/Sift.entitlements --options runtime "$app"

target=/Applications/Sift.app
if pgrep -xq Sift; then osascript -e 'tell application "Sift" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
codesign --verify --strict "$target"
printf '%s (build %s)\n' "$target" "$build"
