#!/bin/zsh
# Build Sift.app and install it to /Applications, signed with the stable
# Apple Development identity, so the Full Disk Access grant survives rebuilds.
# The icon is the committed Sift/Resources/AppIcon.icns, drawn by
# scripts/icon/make-icon.swift (run it after changing the drawing).
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
lock=()
command -v build-lock >/dev/null && lock=(build-lock "sift build-app")
"${lock[@]}" xcodebuild -project Sift.xcodeproj -scheme Sift -configuration "$config" \
  -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="build/DerivedData/Build/Products/$config/Sift.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
identity="${SIGN_IDENTITY:-Apple Development}"
# Nested code first: the MCP server and the Chrome helper in Contents/MacOS,
# then the app around them.
codesign --force --sign "$identity" --identifier app.sift.sift-mcp --options runtime "$app/Contents/MacOS/sift-mcp"
codesign --force --sign "$identity" --identifier app.sift.sift-chrome --options runtime "$app/Contents/MacOS/sift-chrome"
# Sparkle ships signed by its own team; hardened runtime refuses to load a
# framework from another team, so sign it with ours.
codesign --force --deep --sign "$identity" --options runtime "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$identity" --entitlements Sift/Resources/Sift.entitlements --options runtime "$app"

target=/Applications/Sift.app
if pgrep -xq Sift; then osascript -e 'tell application "Sift" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
codesign --verify --deep --strict "$target"
# Only the installed copy may carry the app's icon and id for macOS: a
# registered build copy kept the old icon in the Dock (2026-11-15).
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$app" >/dev/null 2>&1 || true
touch "$target"
"$lsregister" -f "$target" >/dev/null 2>&1 || true
printf '%s (build %s)\n' "$target" "$build"
