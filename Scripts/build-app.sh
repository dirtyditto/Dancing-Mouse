#!/bin/bash
set -euo pipefail

# build-app.sh — Assembles a macOS .app bundle from the SPM build output.
#
# Usage: ./Scripts/build-app.sh [release|debug]
#   Produces: build/Dancing Mouse.app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${1:-release}"

APP_NAME="Dancing Mouse"
EXECUTABLE_NAME="DancingMouse"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

RESOURCES_SRC="$PROJECT_DIR/Sources/DancingMouse/Resources"

echo "==> Building DancingMouse ($CONFIG)..."
cd "$PROJECT_DIR"
swift build -c "$CONFIG"

# Resolve the built binary path.
if [ "$CONFIG" = "release" ]; then
    BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE_NAME"
else
    BINARY="$(swift build -c debug --show-bin-path)/$EXECUTABLE_NAME"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Assembling ${APP_NAME}.app..."

# Clean previous build.
rm -rf "$BUNDLE_DIR"

# Create bundle structure.
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable.
cp "$BINARY" "$MACOS_DIR/$EXECUTABLE_NAME"

# Copy Info.plist.
cp "$RESOURCES_SRC/Info.plist" "$CONTENTS_DIR/Info.plist"

# Generate app icon if it doesn't exist yet.
ICNS_PATH="$PROJECT_DIR/build/AppIcon.icns"
if [ ! -f "$ICNS_PATH" ]; then
    echo "==> Generating app icon..."
    swift "$PROJECT_DIR/Scripts/generate-icon.swift" "$PROJECT_DIR/build"
fi

# Copy icon into Resources.
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$RESOURCES_DIR/AppIcon.icns"
fi

# Write PkgInfo.
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# --- Code signing ---
# Use ad-hoc signing by default. For distribution, set CODESIGN_IDENTITY.
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS="$RESOURCES_SRC/DancingMouse.entitlements"

echo "==> Code signing with identity: $IDENTITY"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$BUNDLE_DIR"

echo ""
echo "✅  ${APP_NAME}.app built successfully!"
echo "    Location: $BUNDLE_DIR"
echo ""
echo "    To run:  open \"$BUNDLE_DIR\""
echo "    To install: cp -R \"$BUNDLE_DIR\" /Applications/"
