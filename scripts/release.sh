#!/bin/bash
# Publishes the current version (from project.yml) as a GitHub release with the
# DMG and ZIP from build/Builds (built via scripts/build-dmg.sh if missing) and
# that version's CHANGELOG section as notes.
#
# Usage: scripts/release.sh            (bump + build first: scripts/build-dmg.sh minor)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
DMG="build/Builds/Backlit-$VERSION.dmg"
ZIP="build/Builds/Backlit-$VERSION.zip"

if [ ! -f "$DMG" ] || [ ! -f "$ZIP" ]; then
  ./scripts/build-dmg.sh --no-bump
fi

# Notes: the "## v$VERSION" section of the changelog, up to the next "## " heading.
NOTES=$(awk -v h="## v$VERSION" 'index($0, h) == 1 {on=1; next} on && /^## / {exit} on' CHANGELOG.md)
[ -n "$NOTES" ] || { echo "ERROR: no '## v$VERSION' section in CHANGELOG.md" >&2; exit 1; }

echo "=== Creating GitHub release v$VERSION ==="
git push origin HEAD
printf '%s\n' "$NOTES" | gh release create "v$VERSION" --title "Backlit $VERSION" --notes-file - "$DMG" "$ZIP"
echo "=== Released Backlit $VERSION — update the Homebrew cask sha256: $(cat "build/Builds/Backlit-$VERSION.sha256") ==="
