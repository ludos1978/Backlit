#!/bin/bash
# Builds a versioned Backlit release: bumps the version, builds Release, ad-hoc
# signs it and writes build/Builds/Backlit-<version>.dmg + .zip (+ .sha256 for
# the Homebrew cask).
#
# Usage: scripts/build-dmg.sh [patch|minor|major|X.Y.Z|--no-bump] [--install] [--no-commit] [--no-push]
#   patch (default)  0.5.2 → 0.5.3      minor  0.5.2 → 0.6.0      major  0.5.2 → 1.0.0
#   --no-bump        rebuild the current version
#   --install        replace /Applications/Backlit.app with the new build and launch it
#   --no-commit      leave the version bump uncommitted (implies --no-push)
#   --no-push        commit the version bump but do not push it
#
# The version bump edits project.yml (MARKETING_VERSION, CURRENT_PROJECT_VERSION + 1),
# renames a "## Unreleased" CHANGELOG section to the new version and commits
# "Version X.Y.Z" (then pushes). Intermediate build data is wiped first; build/Builds is kept.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Backlit"
SCHEME="Backlit"
BUILD_DIR="$(pwd)/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
OUT_DIR="$BUILD_DIR/Builds"

BUMP="patch"; INSTALL=0; COMMIT=1; PUSH=1
for arg in "$@"; do
  case "$arg" in
    patch|minor|major|--no-bump) BUMP="$arg" ;;
    [0-9]*.[0-9]*.[0-9]*)        BUMP="$arg" ;;
    --install)                   INSTALL=1 ;;
    --no-commit)                 COMMIT=0 ;;
    --no-push)                   PUSH=0 ;;
    -h|--help) sed -n 2,15p "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Version ──────────────────────────────────────────────────────────────────
CURRENT=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
BUILD_NUMBER=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml)
[ -n "$CURRENT" ] && [ -n "$BUILD_NUMBER" ] || { echo "ERROR: version not found in project.yml" >&2; exit 1; }

IFS=. read -r MAJ MIN PAT <<< "$CURRENT"
case "$BUMP" in
  patch)     VERSION="$MAJ.$MIN.$((PAT + 1))" ;;
  minor)     VERSION="$MAJ.$((MIN + 1)).0" ;;
  major)     VERSION="$((MAJ + 1)).0.0" ;;
  --no-bump) VERSION="$CURRENT" ;;
  *)         VERSION="$BUMP" ;;
esac

if [ "$VERSION" != "$CURRENT" ]; then
  if [ "$COMMIT" = 1 ] && [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: working tree not clean — commit first (or pass --no-commit)" >&2
    exit 1
  fi
  BUILD_NUMBER=$((BUILD_NUMBER + 1))
  echo "=== Version $CURRENT → $VERSION (build $BUILD_NUMBER) ==="
  if [ "$COMMIT" = 1 ]; then
    # Tree was clean: undo the bump if anything below fails.
    trap 'echo "=== Failed — reverting version bump ==="; git checkout -- project.yml CHANGELOG.md "$APP_NAME.xcodeproj/project.pbxproj"' ERR
  fi
  sed -i '' -E "s/^( *MARKETING_VERSION: *)\".*\"/\1\"$VERSION\"/" project.yml
  sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)\".*\"/\1\"$BUILD_NUMBER\"/" project.yml
  if grep -q '^## Unreleased' CHANGELOG.md; then
    sed -i '' "s/^## Unreleased.*/## v$VERSION ($(date +%Y-%m-%d))/" CHANGELOG.md
  fi
else
  echo "=== Rebuilding $VERSION (build $BUILD_NUMBER) ==="
fi

xcodegen generate >/dev/null

# ── Build ────────────────────────────────────────────────────────────────────
echo "=== Cleaning intermediate build data (keeping build/Builds) ==="
mkdir -p "$OUT_DIR"
find "$BUILD_DIR" -mindepth 1 -maxdepth 1 ! -name Builds -exec rm -rf {} +

echo "=== Building $APP_NAME $VERSION (Release) ==="
# Skip Xcode's codesign; we sign ad-hoc after stripping xattrs.
xcodebuild -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build > "$BUILD_DIR/xcodebuild.log" 2>&1 \
  || { tail -30 "$BUILD_DIR/xcodebuild.log"; echo "ERROR: build failed (log: build/xcodebuild.log)" >&2; exit 1; }

APP_PATH="$DERIVED_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "ERROR: $APP_PATH not found" >&2; exit 1; }
BUILT_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
[ "$BUILT_VERSION" = "$VERSION" ] || { echo "ERROR: built $BUILT_VERSION, expected $VERSION" >&2; exit 1; }

echo "=== Signing (ad-hoc) ==="
/usr/bin/xattr -cr "$APP_PATH"          # /usr/bin: Homebrew's xattr has no -r
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

# ── Package ──────────────────────────────────────────────────────────────────
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$OUT_DIR/$APP_NAME-$VERSION.zip"
STAGING="$BUILD_DIR/dmg-staging"

echo "=== Creating DMG ==="
rm -rf "$STAGING" "$DMG" "$ZIP"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "=== Creating ZIP (Homebrew cask) ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
shasum -a 256 "$ZIP" | cut -d' ' -f1 > "$OUT_DIR/$APP_NAME-$VERSION.sha256"

# ── Commit ───────────────────────────────────────────────────────────────────
if [ "$VERSION" != "$CURRENT" ] && [ "$COMMIT" = 1 ]; then
  git add project.yml CHANGELOG.md "$APP_NAME.xcodeproj/project.pbxproj"
  git commit -q -m "Version $VERSION"
  trap - ERR
  echo "=== Committed \"Version $VERSION\" ==="
  if [ "$PUSH" = 1 ]; then
    git push -q origin HEAD && echo "=== Pushed ===" || echo "WARNING: git push failed" >&2
  fi
fi

# ── Install ──────────────────────────────────────────────────────────────────
if [ "$INSTALL" = 1 ]; then
  echo "=== Installing to /Applications ==="
  # Quit normally (not kill) so Backlit records a clean exit and resets its gamma.
  osascript -e "tell application id \"io.github.ludos1978.backlit\" to quit" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.5; done
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$APP_PATH" "/Applications/$APP_NAME.app"
  codesign --verify --deep --strict "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
fi

echo "=== Done: $APP_NAME $VERSION ==="
ls -lh "$DMG" "$ZIP"
