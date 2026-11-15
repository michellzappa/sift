#!/usr/bin/env bash
# Print the CHANGELOG.md section for a version, or fail if it has none.
#
#   ./scripts/changelog-section.sh 0.5.2
#
# release.yml runs it before building, so a tag without notes fails early,
# and again to write the GitHub release notes. Ported from Headroom.
set -euo pipefail
VERSION="${1:?usage: changelog-section.sh X.Y.Z}"
CHANGELOG="$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md"
[[ -f "$CHANGELOG" ]] || { echo "error: missing $CHANGELOG" >&2; exit 1; }
section="$(awk -v v="$VERSION" '
  /^## / { if (found) exit; split($0, a, " "); if (a[2] == v) { found = 1; next } }
  found { print }
' "$CHANGELOG" | sed -e '/./,$!d')"
if [[ -z "${section//[[:space:]]/}" ]]; then
  echo "error: CHANGELOG.md has no '## $VERSION' section (or it is empty)" >&2
  exit 1
fi
printf '%s\n' "$section"
