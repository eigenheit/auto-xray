#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/bin/cat VERSION | /usr/bin/tr -d '[:space:]')"
PROFILE="${AUTO_XRAY_NOTARY_PROFILE:-AUTO-Xray-notary}"
INPUT_ZIP="${1:-}"

[ -n "$INPUT_ZIP" ] && [ -f "$INPUT_ZIP" ] || {
  echo "Usage: $0 /path/to/AUTO_Xray_v${VERSION}_Catalina_App_for_Signing.zip"
  exit 2
}

/usr/bin/xcrun notarytool --version >/dev/null 2>&1 || { echo "notarytool не найден."; exit 20; }

IDENTITIES_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/auto-xray-identities.XXXXXX")"
/usr/bin/security find-identity -v -p codesigning | \
  /usr/bin/sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' > "$IDENTITIES_FILE"

COUNT="$(/usr/bin/wc -l < "$IDENTITIES_FILE" | /usr/bin/tr -d ' ')"
[ "$COUNT" -gt 0 ] || {
  rm -f "$IDENTITIES_FILE"
  echo "Developer ID Application certificate not found."
  exit 21
}

if [ -n "${AUTO_XRAY_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$AUTO_XRAY_SIGN_IDENTITY"
else
  IDENTITY="$(/usr/bin/head -n 1 "$IDENTITIES_FILE")"
fi
rm -f "$IDENTITIES_FILE"

WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/auto-xray-public.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

/usr/bin/ditto -x -k "$INPUT_ZIP" "$WORK"
APP="$(find "$WORK" -maxdepth 2 -name 'AUTO Xray.app' -type d -print -quit)"
[ -n "$APP" ] || { echo "AUTO Xray.app not found in ZIP"; exit 22; }

/usr/bin/xattr -cr "$APP" >/dev/null 2>&1 || true
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/xray"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

APP_ZIP="$WORK/AUTO_Xray_notary.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$APP_ZIP"
/usr/bin/xcrun notarytool submit "$APP_ZIP" --keychain-profile "$PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP"

OUT="$HOME/Desktop/AUTO_Xray_v${VERSION}_PUBLIC"
STAGE="$WORK/dmg"
mkdir -p "$OUT" "$STAGE"
cp -R "$APP" "$STAGE/AUTO Xray.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/AUTO_Xray_Catalina_Intel_v${VERSION}.dmg"

/usr/bin/hdiutil create -volname "AUTO Xray" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG"
/usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
/usr/bin/xcrun stapler staple "$DMG"
/usr/bin/xcrun stapler validate "$DMG"
/usr/bin/shasum -a 256 "$DMG" > "$DMG.sha256.txt"

open -R "$DMG"
