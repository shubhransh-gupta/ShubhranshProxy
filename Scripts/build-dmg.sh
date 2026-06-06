#!/usr/bin/env bash
# Build ShubhranshProxy Release .app and pack it into a .dmg for download.
# Usage: ./Scripts/build-dmg.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="ShubhranshProxy"
PROJECT="$ROOT/ShubhranshProxy.xcodeproj"
BUILD_DIR="$ROOT/build/release"
# Reuse Xcode DerivedData when available (avoids re-downloading Swift packages).
if [[ -d "$ROOT/.derivedData" ]]; then
  DERIVED="$ROOT/.derivedData"
else
  DERIVED="$BUILD_DIR/DerivedData"
fi
STAGE="$BUILD_DIR/dmg-stage"
DMG_PATH="$BUILD_DIR/ShubhranshProxy.dmg"

echo "==> Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building Release (this can take a minute)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "${SCHEME}.app" -print -quit)"
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "ERROR: Could not find ${SCHEME}.app after build." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "1")"
VERSIONED_DMG="$BUILD_DIR/ShubhranshProxy-${VERSION}.dmg"

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

echo "==> Creating compressed DMG"
hdiutil create \
  -volname "ShubhranshProxy ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

cp -f "$DMG_PATH" "$VERSIONED_DMG"

echo
echo "Done."
echo "  App:  $APP"
echo "  DMG:  $DMG_PATH"
echo "  DMG:  $VERSIONED_DMG"
echo
echo "Next steps:"
echo "  1. Upload the .dmg to your server or GitHub Releases"
echo "  2. Link it from web/index.html (or run Scripts/publish-release.sh)"
echo "  3. For public distribution, sign + notarize with an Apple Developer account"
