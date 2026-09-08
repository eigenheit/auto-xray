#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/bin/cat VERSION | /usr/bin/tr -d '[:space:]')"
BUILD="${VERSION//./}"
SRC="src/AUTO_Xray.applescript"
HELPER="src/auto-xray-helper.rb"
XRAY="vendor/xray/xray"
ICON="assets/dove-icon.png"
NOTICE="THIRD_PARTY_NOTICES.txt"
EXPECTED_SHA="25ab858d6a6d763c3bf98d21a9c26571a58d807a857b273e49d6b824c4cb4f39"

OUT="$HOME/Desktop/AUTO_Xray_${VERSION}_BUILD"
APP="$OUT/AUTO Xray.app"
DMG="$OUT/AUTO_Xray_Catalina_Intel_v${VERSION}_LOCAL.dmg"
TRANSFER="$OUT/AUTO_Xray_v${VERSION}_Catalina_App_for_Signing.zip"
ICONSET="$OUT/DoveIcon.iconset"
STAGE="$OUT/dmg-stage"

fail() { echo; echo "ERROR: $1"; echo; exit 1; }

[ "$(/usr/bin/uname -m)" = "x86_64" ] || fail "Сборка Catalina предназначена для Intel Mac."
[ -x /usr/bin/ruby ] || fail "Не найден системный Ruby."
[ -x /usr/bin/osacompile ] || fail "Не найден osacompile."
[ -x /usr/bin/iconutil ] || fail "Не найден iconutil."
[ -x "$XRAY" ] || fail "Сначала запустите scripts/import-xray-from-installed.command"
[ -f "$ICON" ] || fail "Не найден assets/dove-icon.png"

ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$XRAY" | /usr/bin/awk '{print $1}')"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "Xray-core имеет неверную контрольную сумму."
/usr/bin/ruby -c "$HELPER" >/dev/null || fail "Ruby helper не прошел syntax check."

rm -rf "$OUT"
mkdir -p "$OUT" "$ICONSET"

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

/usr/bin/osacompile -s -o "$APP" "$SRC"
mkdir -p "$APP/Contents/Resources"
cp "$HELPER" "$APP/Contents/Resources/auto-xray-helper.rb"
cp "$XRAY" "$APP/Contents/Resources/xray"
cp "$NOTICE" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "vendor/xray/XRAY_VERSION.txt" "$APP/Contents/Resources/XRAY_VERSION.txt"
cp "vendor/xray/XRAY_SHA256.txt" "$APP/Contents/Resources/XRAY_SHA256.txt"
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
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Dove.icns" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Dove.icns" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST" 2>/dev/null || true

/usr/bin/codesign --force --sign - "$APP/Contents/Resources/xray" >/dev/null 2>&1 || true
/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

XRAY_VER="$("$APP/Contents/Resources/xray" version 2>&1 || true)"
echo "$XRAY_VER" | /usr/bin/grep -q "Xray 1.8.4" || fail "Встроенный Xray-core не запускается."
AUTO_XRAY_RESOURCES="$APP/Contents/Resources" /usr/bin/ruby "$APP/Contents/Resources/auto-xray-helper.rb" menu-state >/dev/null || fail "Helper smoke test failed."

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/AUTO Xray.app"
ln -s /Applications "$STAGE/Applications"
cp "$APP/Contents/Resources/Dove.icns" "$STAGE/.VolumeIcon.icns"
if [ -x /usr/bin/SetFile ]; then /usr/bin/SetFile -a C "$STAGE" >/dev/null 2>&1 || true; fi
/usr/bin/hdiutil create -volname "AUTO Xray" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
/usr/bin/ditto -c -k --keepParent "$APP" "$TRANSFER"
/usr/bin/shasum -a 256 "$DMG" > "$DMG.sha256.txt"

echo
printf 'READY\nApp: %s\nLocal DMG: %s\nSigning ZIP: %s\n' "$APP" "$DMG" "$TRANSFER"
/usr/bin/open "$OUT"
