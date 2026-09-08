#!/bin/bash
#
# build.sh — clean build of FreeDisplay from the command line.
#
#   ./build.sh                 clean Debug build
#   ./build.sh --release       clean Release build
#   ./build.sh --run           build, then (re)launch the app
#   ./build.sh --release --run
#
# Signing: if a valid "Apple Development" certificate is installed, the
# project's own signing settings are used. Otherwise the app is signed ad-hoc
# (runs fine locally; macOS permission grants such as Screen Recording /
# Accessibility may have to be re-approved after each rebuild).
# Force ad-hoc signing with:  SIGN=adhoc ./build.sh
#
# Requirements: Xcode (command line tools selected), and xcodegen
# (brew install xcodegen) — used to regenerate the .xcodeproj from project.yml.
#
# Output: build/Build/Products/<Debug|Release>/FreeDisplay.app
# Full compiler log: build/xcodebuild.log

set -euo pipefail
cd "$(dirname "$0")"

CONFIG=Debug
RUN=0
for arg in "$@"; do
    case "$arg" in
        --release) CONFIG=Release ;;
        --debug)   CONFIG=Debug ;;
        --run)     RUN=1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg (see --help)"; exit 2 ;;
    esac
done

# 1. Regenerate the Xcode project (new source files are picked up automatically).
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
elif [ ! -d FreeDisplay.xcodeproj ]; then
    echo "xcodegen is required to generate the project: brew install xcodegen"; exit 1
else
    echo "note: xcodegen not installed — using the existing FreeDisplay.xcodeproj"
fi

# 2. Decide how to sign.
SIGN_ARGS=()
if [ "${SIGN:-auto}" = "adhoc" ] || ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    echo "signing: ad-hoc (no Apple Development certificate found)"
    SIGN_ARGS=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
else
    echo "signing: Apple Development certificate (project settings)"
fi

# 3. Clean build.
mkdir -p build
echo "building: $CONFIG (clean) …"
if xcodebuild -scheme FreeDisplay -configuration "$CONFIG" -derivedDataPath build \
        clean build "${SIGN_ARGS[@]}" > build/xcodebuild.log 2>&1; then
    APP="build/Build/Products/$CONFIG/FreeDisplay.app"
    echo "ok: $APP"
else
    echo "BUILD FAILED — errors:"
    grep -E "error:" build/xcodebuild.log | head -20
    echo "(full log: build/xcodebuild.log)"
    exit 1
fi

# 4. Optionally (re)launch.
if [ "$RUN" = 1 ]; then
    pkill -f "FreeDisplay.app/Contents/MacOS/FreeDisplay" 2>/dev/null || true
    sleep 1
    open "$APP"
    echo "launched"
fi
