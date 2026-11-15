#!/usr/bin/env bash
# Update the installed Sift.app from a GitHub Release. Ported from Headroom.
#
#   ./scripts/update-app.sh            # update if a newer release exists
#   ./scripts/update-app.sh --check    # say what would happen, change nothing
#   ./scripts/update-app.sh --yes      # no confirmation prompt
#   ./scripts/update-app.sh --version 0.5.1
#   ./scripts/update-app.sh --force    # reinstall even at the same version
#
# Sift runs this too, from Contents/Resources, with --yes --version X
# (Sift/App/Updates.swift). The app cannot replace its own bundle while it
# runs, so this script quits it, verifies the download, swaps the bundle,
# keeps the old copy until the new one is in place, and opens Sift again.
#
# System tools only: curl, unzip, shasum, plutil, codesign, spctl, ditto.
set -euo pipefail

REPO="${SIFT_GITHUB_REPO:-michellzappa/sift}"
APP="${SIFT_APP_PATH:-/Applications/Sift.app}"
# The only team whose signature may replace Sift on this Mac. Compiled in,
# never read from the release: a notarized app from anyone else is still
# notarized, it is just not ours.
TEAM_ID="992N457T8D"

CHECK_ONLY=0
ASSUME_YES=0
FORCE=0
WANT_VERSION=""

die() { echo "error: $*" >&2; exit 1; }
note() { echo "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|-n) CHECK_ONLY=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --force) FORCE=1; shift ;;
    --version) WANT_VERSION="${2:-}"; shift 2 ;;
    --app) APP="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

note "$(date '+%Y-%m-%d %H:%M:%S') update-app.sh"

installed_version() {
  [[ -d "$APP" ]] || return 0
  plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true
}

# Highest of two versions by sort -V, so 0.10.0 beats 0.9.0.
newest() { printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1; }

# ---------------------------------------------------------------- what is out

if [[ -n "$WANT_VERSION" ]]; then
  TAG="v${WANT_VERSION#v}"
else
  # /releases/latest skips drafts and prereleases.
  TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$TAG" ]] || die "could not read the latest release tag from GitHub"
fi
LATEST="${TAG#v}"
INSTALLED="$(installed_version)"
note "installed ${INSTALLED:-none} · latest $LATEST"

if [[ -n "$INSTALLED" && "$FORCE" -eq 0 ]]; then
  if [[ "$INSTALLED" == "$LATEST" || "$(newest "$INSTALLED" "$LATEST")" == "$INSTALLED" ]]; then
    note "Already up to date."
    exit 0
  fi
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  note "Would install $LATEST. Nothing changed (--check)."
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  printf 'Update %s (%s → %s)? [Y/n] ' "$APP" "${INSTALLED:-none}" "$LATEST" >&2
  read -r reply </dev/tty || reply=""
  case "$reply" in ""|y|Y|yes|YES) ;; *) note "Cancelled."; exit 0 ;; esac
fi

# ------------------------------------------------------------------- fetch it

STAGE="$(mktemp -d -t sift-update)"
INSTALLED_OK=0
QUIT_APP=0
# Every way out before the install gives the user their app back.
cleanup() {
  rm -rf "$STAGE"
  if [[ "$QUIT_APP" -eq 1 && "$INSTALLED_OK" -eq 0 && -d "$APP" ]]; then
    open "$APP" 2>/dev/null || true
  fi
}
trap cleanup EXIT

BASE="https://github.com/$REPO/releases/download/$TAG"
ZIP="Sift-$LATEST.zip"
note "Downloading $TAG …"
curl -fsSL --proto '=https' --tlsv1.2 -o "$STAGE/$ZIP" "$BASE/$ZIP" || die "download failed: $BASE/$ZIP"
curl -fsSL --proto '=https' --tlsv1.2 -o "$STAGE/SHA256SUMS" "$BASE/SHA256SUMS" || die "download failed: $BASE/SHA256SUMS"
(cd "$STAGE" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || die "checksum does not match SHA256SUMS, refusing to install"

unzip -oq "$STAGE/$ZIP" -d "$STAGE/x" || die "the zip did not unpack"
NEW="$STAGE/x/Sift.app"
[[ -d "$NEW" ]] || die "no Sift.app inside the zip"

# ------------------------------------------------------------------ verify it
# All of this runs before anything on disk changes.

spctl -a -t exec "$NEW" 2>/dev/null || die "Gatekeeper rejected the download (not notarized), refusing to install"
codesign --verify --deep --strict "$NEW" 2>/dev/null || die "signature does not verify, refusing to install"
GOT_TEAM="$(codesign -dv --verbose=4 "$NEW" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
[[ "$GOT_TEAM" == "$TEAM_ID" ]] || die "signed by team ${GOT_TEAM:-none}, expected $TEAM_ID, refusing to install"
NEW_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$NEW/Contents/Info.plist" 2>/dev/null || true)"
[[ "$NEW_VERSION" == "$LATEST" ]] || die "$TAG contains version ${NEW_VERSION:-none}, refusing a bundle that disagrees with its tag"
note "Verified $NEW_VERSION: checksum, notarized, team $GOT_TEAM."

# ----------------------------------------------------------------- install it

# Quit Sift after the download and checks, so it stays open while they run.
if pgrep -x Sift >/dev/null 2>&1; then
  note "Closing Sift…"
  QUIT_APP=1
  osascript -e 'quit app "Sift"' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -x Sift >/dev/null 2>&1 || break
    sleep 0.5
  done
  pgrep -x Sift >/dev/null 2>&1 && die "Sift did not quit, nothing changed"
fi

# Keep the old bundle until the new one is in place.
BACKUP=""
if [[ -d "$APP" ]]; then
  BACKUP="$STAGE/Sift.app.previous"
  mv "$APP" "$BACKUP"
fi
if ! ditto "$NEW" "$APP"; then
  note "copy failed, restoring the previous app"
  rm -rf "$APP"
  [[ -n "$BACKUP" ]] && mv "$BACKUP" "$APP"
  die "install failed, previous version restored"
fi
# The download already passed Gatekeeper; skip the first-open prompt.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
INSTALLED_OK=1

open "$APP" 2>/dev/null || true
note "Installed $NEW_VERSION."
