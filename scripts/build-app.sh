#!/bin/zsh
# Build Sift.app and install it to /Applications, signed with the stable
# Apple Development identity, so the Full Disk Access grant survives rebuilds.
# Regenerates the icon from the HouseKit "sift" glyph every time.
#
#   ./scripts/build-app.sh            # Release -> /Applications/Sift.app
#   ./scripts/build-app.sh --debug
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
housekit="${HOUSEKIT_PATH:-$here/../../housekit}"
config=Release
[[ "${1:-}" == "--debug" ]] && config=Debug

# The committed AppIcon.icns is used as is when HouseKit is not next to the repo.
if [[ -d "$housekit" ]]; then
  swift build -c release --package-path "$housekit" >/dev/null
  "$(swift build -c release --package-path "$housekit" --show-bin-path)/housekit-icon" sift "$here/Sift/Resources/AppIcon.icns" >/dev/null
fi

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
# Nested code first: the MCP server in Contents/MacOS, then the app around it.
codesign --force --sign "$identity" --identifier app.sift.sift-mcp --options runtime "$app/Contents/MacOS/sift-mcp"
codesign --force --sign "$identity" --entitlements Sift/Resources/Sift.entitlements --options runtime "$app"

target=/Applications/Sift.app
if pgrep -xq Sift; then osascript -e 'tell application "Sift" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
codesign --verify --deep --strict "$target"
printf '%s (build %s)\n' "$target" "$build"
