#!/bin/bash
# build_release.sh - Compile FongMiTV and copy app to ./release

set -e

PROJECT_DIR="/Users/wclin/openchamber/FongMiTV"
RELEASE_DIR="$PROJECT_DIR/release"
SCHEME="FongMiTV"
CONFIGURATION="Release"

cd "$PROJECT_DIR"

echo "=========================================="
echo "FongMiTV - Release Build Script"
echo "=========================================="

mkdir -p "$RELEASE_DIR"
rm -rf "$RELEASE_DIR"/*

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project FongMiTV.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$PROJECT_DIR/.build/DerivedData" \
  build 2>&1 | tail -20

APP_PATH=$(find "$PROJECT_DIR/.build/DerivedData" -name "FongMiTV.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: FongMiTV.app not found after build"
  exit 1
fi

echo "Copying app to release..."
cp -R "$APP_PATH" "$RELEASE_DIR/FongMiTV.app"

echo "=========================================="
echo "Release build complete!"
echo "App: $RELEASE_DIR/FongMiTV.app"
echo "=========================================="
