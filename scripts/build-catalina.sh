#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-${VERSION//./}}"
OUT="${OUT_DIR:-$HOME/Desktop/AUTO_Xray_${VERSION}_BUILD}"
APP="$OUT/AUTO Xray.app"
STAGE="$OUT/dmg-stage"
DMG="$OUT/AUTO_Xray_Catalina_Intel_v${VERSION}_LOCAL.dmg"
TRANSFER="$OUT/AUTO_Xray_v${VERSION}_Catalina_App_for_Signing.zip"

SRC="$ROOT/src/AUTO_Xray.applescript"
HELPER="$ROOT/src/auto-xray-helper.rb"
XRAY="${XRAY_BIN:-$ROOT/vendor/xray}"
NOTICE="$ROOT/THIRD_PARTY_NOTICES.txt"
XVER="$ROOT/vendor/XRAY_VERSION.txt"
XSHA="$ROOT/vendor/XRAY_SHA256.txt"
ICON_MASTER="$ROOT/assets/dove-icon.png"
ICONSET="$OUT/DoveIcon.iconset"

fail() {
  echo
  echo "ERROR: $1"
  echo
  exit 1
}

printf '\nAUTO Xray %s — Catalina Builder\n' "$VERSION"
printf '================================\n\n'

[ "$(uname -m)" = "x86_64" ] || fail "Build must run on an Intel Mac."
[ -x /usr/bin/ruby ] || fail "System Ruby not found."
[ -x /usr/bin/osacompile ] || fail "osacompile not found."
[ -x /usr/bin/iconutil ] || fail "iconutil not found."
[ -f "$SRC" ] || fail "Missing $SRC"
[ -f "$HELPER" ] || fail "Missing $HELPER"
[ -f "$XRAY" ] || fail "Missing Xray binary. Set XRAY_BIN=/path/to/xray or place it at vendor/xray."
[ -f "$ICON_MASTER" ] || fail "Missing $ICON_MASTER"

ruby -c "$HELPER" >/dev/null || fail "Ruby helper syntax check failed."

EXPECTED_SHA="$(awk '{print $1}' "$XSHA")"
ACTUAL_SHA="$(shasum -a 256 "$XRAY" | awk '{print $1}')"
[ "$EXPECTED_SHA" = "$ACTUAL_SHA" ] || fail "Xray SHA-256 does not match vendor/XRAY_SHA256.txt."

rm -rf "$OUT"
mkdir -p "$OUT" "$ICONSET"

# Generate a standard macOS iconset from the repository PNG.
for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  set -- $spec
  /usr/bin/sips -z "$1" "$1" "$ICON_MASTER" --out "$ICONSET/$2" >/dev/null
 done

printf 'Compiling app on Catalina...\n'
/usr/bin/osacompile -s -o "$APP" "$SRC" || fail "AppleScript compilation failed."
mkdir -p "$APP/Contents/Resources"

cp "$HELPER" "$APP/Contents/Resources/auto-xray-helper.rb"
cp "$XRAY" "$APP/Contents/Resources/xray"
cp "$NOTICE" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$XVER" "$APP/Contents/Resources/XRAY_VERSION.txt"
cp "$XSHA" "$APP/Contents/Resources/XRAY_SHA256.txt"
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Dove.icns"

chmod 644 "$APP/Contents/Resources/auto-xray-helper.rb"
chmod +x "$APP/Contents/Resources/xray"
/usr/bin/xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AUTO Xray" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.autoxray.menubar" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Dove.icns" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Dove.icns" "$PLIST" 2>/dev/null || true

# Local test signature only. Public signing/notarization is a separate stage.
codesign --force --sign - "$APP/Contents/Resources/xray" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

"$APP/Contents/Resources/xray" version | grep -q 'Xray 1.8.4' || fail "Embedded Xray failed its smoke test."
AUTO_XRAY_RESOURCES="$APP/Contents/Resources" /usr/bin/ruby "$APP/Contents/Resources/auto-xray-helper.rb" menu-state >/dev/null || fail "Helper smoke test failed."

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/AUTO Xray.app"
ln -s /Applications "$STAGE/Applications"
cp "$APP/Contents/Resources/Dove.icns" "$STAGE/.VolumeIcon.icns"

rm -f "$DMG"
hdiutil create -volname 'AUTO Xray' -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

rm -f "$TRANSFER"
ditto -c -k --keepParent "$APP" "$TRANSFER"

shasum -a 256 "$DMG" > "$DMG.sha256.txt"

echo
echo "READY"
echo "App:      $APP"
echo "Test DMG: $DMG"
echo "Signing:  $TRANSFER"
