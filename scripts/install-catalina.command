#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/bin/cat VERSION | /usr/bin/tr -d '[:space:]')"
APP_DIR="$HOME/Applications/AUTO Xray.app"
SRC="src/AUTO_Xray.applescript"
HELPER="src/auto-xray-helper.rb"
XRAY="vendor/xray/xray"
ICON="assets/dove-icon.png"
NOTICE="THIRD_PARTY_NOTICES.txt"
EXPECTED_SHA="25ab858d6a6d763c3bf98d21a9c26571a58d807a857b273e49d6b824c4cb4f39"
TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/auto-xray-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/DoveIcon.iconset"

fail() { echo; echo "ERROR: $1"; echo; exit 1; }
[ "$(/usr/bin/uname -m)" = "x86_64" ] || fail "Этот установщик предназначен для Intel Mac."
[ -x "$XRAY" ] || fail "В пакете отсутствует встроенный Xray-core."
[ -f "$ICON" ] || fail "В пакете отсутствует иконка AUTO Xray."
ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$XRAY" | /usr/bin/awk '{print $1}')"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "Встроенный Xray-core поврежден."
/usr/bin/ruby -c "$HELPER" >/dev/null || fail "Ruby helper поврежден."

if [ -f "$APP_DIR/Contents/Resources/auto-xray-helper.rb" ]; then
  AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" /usr/bin/ruby "$APP_DIR/Contents/Resources/auto-xray-helper.rb" stop >/dev/null 2>&1 || true
fi
/usr/bin/osascript -e 'tell application "AUTO Xray" to quit' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$HOME/Applications" "$ICONSET"
rm -rf "$APP_DIR"

/usr/bin/sips -z 16 16 "$ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$ICON" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

/usr/bin/osacompile -s -o "$APP_DIR" "$SRC"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$HELPER" "$APP_DIR/Contents/Resources/auto-xray-helper.rb"
cp "$XRAY" "$APP_DIR/Contents/Resources/xray"
cp "$NOTICE" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.txt"
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/Dove.icns"
chmod +x "$APP_DIR/Contents/Resources/xray"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AUTO Xray" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.autoxray.menubar" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION//./}" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION//./}" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Dove.icns" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Dove.icns" "$PLIST" 2>/dev/null || true

/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Resources/xray" >/dev/null 2>&1 || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" /usr/bin/ruby "$APP_DIR/Contents/Resources/auto-xray-helper.rb" bootstrap >/dev/null || fail "Первичная настройка не выполнена."
/usr/bin/open "$APP_DIR"
