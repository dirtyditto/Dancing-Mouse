#!/bin/bash
set -euo pipefail

# create-dmg.sh — Creates a distributable DMG disk image.
#
# Usage: ./Scripts/create-dmg.sh
#   Requires: build/Dancing Mouse.app (run build-app.sh first)
#   Produces: build/DancingMouse-1.0.0.dmg

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Dancing Mouse"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
VERSION="1.0.0"
DMG_NAME="DancingMouse-${VERSION}"
DMG_PATH="$PROJECT_DIR/build/${DMG_NAME}.dmg"
DMG_STAGING="$PROJECT_DIR/build/dmg-staging"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "ERROR: ${APP_NAME}.app not found. Run build-app.sh first."
    exit 1
fi

echo "==> Creating DMG..."

# Clean previous.
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING"

# Create staging directory with app + symlink to /Applications.
mkdir -p "$DMG_STAGING"
cp -R "$BUNDLE_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create a background instructions file.
cat > "$DMG_STAGING/.background-README.txt" << 'EOF'
Drag "Dancing Mouse" to Applications to install.

This app requires Accessibility permission to function.
After first launch, go to System Settings → Privacy & Security → Accessibility
and grant access to Dancing Mouse.
EOF

# Create the DMG.
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# Clean up staging.
rm -rf "$DMG_STAGING"

echo ""
echo "✅  DMG created successfully!"
echo "    Location: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
