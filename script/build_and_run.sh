#!/usr/bin/env bash
# Usage: script/build_and_run.sh [run|build|install|release]
#   install copies BeamMac.app to ~/Applications
#   release builds a bundle that does not point at this checkout and packs it
#   into dist/BeamMac-<version>.dmg
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BeamMac"
BUNDLE_ID="at.johannesgrof.BeamMac"
APP_VERSION="${BEAMMAC_VERSION:-0.1.0}"
CONFIGURATION="${BEAMMAC_CONFIGURATION:-release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ICON_DIR="$ROOT_DIR/Assets"

cd "$ROOT_DIR"
[[ "$MODE" == run || "$MODE" == install ]] && { pkill -x "$APP_NAME" >/dev/null 2>&1 || true; }
swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

if [[ ! -f "$ICON_DIR/AppIcon.icns" ]]; then
  mkdir -p "$ICON_DIR"
  iconset="$DIST_DIR/AppIcon.iconset"
  rm -rf "$iconset" && mkdir -p "$iconset"
  swift script/generate_icon.swift "$DIST_DIR/AppIcon-1024.png"
  for px in 16 32 128 256 512; do
    sips -z $px $px "$DIST_DIR/AppIcon-1024.png" --out "$iconset/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$DIST_DIR/AppIcon-1024.png" --out "$iconset/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$ICON_DIR/AppIcon.icns"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ICON_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
mkdir -p "$APP_BUNDLE/Contents/Resources/BeamMac"
cp -R bin lib config "$APP_BUNDLE/Contents/Resources/BeamMac/"

# Development builds also know the checkout, so an install that lives there
# keeps its data. Release builds keep everything in Application Support.
dev_keys=""
if [[ "$MODE" != release ]]; then
  dev_keys="<key>BeamMacRoot</key><string>$ROOT_DIR</string>"
fi

cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  $dev_keys
</dict>
</plist>
PLIST

# BEAMMAC_SIGN_IDENTITY signs with a Developer ID and the hardened runtime that
# notarization requires; without it the bundle is only ad-hoc signed.
if [[ -n "${BEAMMAC_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$BEAMMAC_SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
fi

case "$MODE" in
  run) open "$APP_BUNDLE" ;;
  install)
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$HOME/Applications/"
    open "$HOME/Applications/$APP_NAME.app"
    ;;
  build) ;;
  release)
    dmg="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
    staging="$DIST_DIR/dmg"
    rm -rf "$staging" "$dmg"
    mkdir -p "$staging"
    cp -R "$APP_BUNDLE" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg" >/dev/null
    rm -rf "$staging"
    [[ -n "${BEAMMAC_SIGN_IDENTITY:-}" ]] && codesign --force --timestamp --sign "$BEAMMAC_SIGN_IDENTITY" "$dmg"
    echo "$dmg"
    ;;
  *) echo "unbekannter Modus: $MODE" >&2; exit 1 ;;
esac
echo "$APP_BUNDLE"
