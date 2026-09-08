#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/bin/cat VERSION | /usr/bin/tr -d '[:space:]')"
APP_DIR="$HOME/Applications/AUTO Xray.app"
SRC="src/AUTO_Xray.applescript"
CORE_HELPER="src/auto-xray-helper.rb"
SUPERVISOR="src/auto-xray-supervisor.rb"
XRAY="vendor/xray/xray"
XRAY_SUMS="vendor/xray/XRAY_SHA256.txt"
ICON="assets/dove-clean.png"
NOTICE="THIRD_PARTY_NOTICES.txt"
TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/auto-xray-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/DoveIcon.iconset"
COMPILED_SRC="$TMP/AUTO_Xray.applescript"

fail() { echo; echo "ERROR: $1"; echo; exit 1; }
[ "$(/usr/bin/uname -m)" = "x86_64" ] || fail "Этот установщик предназначен для Intel Mac."
[ -x "$XRAY" ] || fail "В пакете отсутствует встроенный Xray-core."
[ -f "$XRAY_SUMS" ] || fail "В пакете отсутствует контрольная сумма Xray-core."
[ -f "$ICON" ] || fail "В пакете отсутствует иконка AUTO Xray."
[ -f "$CORE_HELPER" ] || fail "В пакете отсутствует основной helper AUTO Xray."
[ -f "$SUPERVISOR" ] || fail "В пакете отсутствует supervisor AUTO Xray."

# Catalina can run old system tools under unusual locale settings. Compare the first
# 64 ASCII hex characters directly instead of parsing shasum output with awk.
EXPECTED_SHA="$(/usr/bin/head -n 1 "$XRAY_SUMS" | /usr/bin/cut -c 1-64)"
ACTUAL_SHA="$(/usr/bin/env LC_ALL=C /usr/bin/shasum -a 256 "$XRAY" | /usr/bin/cut -c 1-64)"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "EXPECTED: $EXPECTED_SHA"
  echo "ACTUAL:   $ACTUAL_SHA"
  fail "Встроенный Xray-core не прошел проверку контрольной суммы."
fi

/usr/bin/ruby -EUTF-8:UTF-8 -c "$CORE_HELPER" >/dev/null || fail "Основной Ruby helper поврежден."
/usr/bin/ruby -EUTF-8:UTF-8 -c "$SUPERVISOR" >/dev/null || fail "Ruby supervisor поврежден."

# Stop the installed version cleanly. This works for both the old direct helper and
# the new supervisor wrapper.
if [ -f "$APP_DIR/Contents/Resources/auto-xray-helper.rb" ]; then
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" \
    /usr/bin/ruby -EUTF-8:UTF-8 "$APP_DIR/Contents/Resources/auto-xray-helper.rb" stop >/dev/null 2>&1 || true
fi
/usr/bin/osascript -e 'tell application "AUTO Xray" to quit' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$HOME/Applications" "$ICONSET"
rm -rf "$APP_DIR"

# Keep the menu/app version synchronized with VERSION even if the source template
# still contains the previous 2.5.x number.
/usr/bin/sed -E "s/2\.5\.[0-9]+/${VERSION}/g" "$SRC" > "$COMPILED_SRC"

# Build a fresh icon from the cleaned transparent dove source. The previous 128 px
# source could produce a damaged-looking ICNS on Catalina when scaled to Retina sizes.
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

/usr/bin/osacompile -s -o "$APP_DIR" "$COMPILED_SRC"
mkdir -p "$APP_DIR/Contents/Resources"

# The AppleScript calls auto-xray-helper.rb. Install the supervisor under that name
# and keep the original implementation as auto-xray-core-helper.rb.
cp "$CORE_HELPER" "$APP_DIR/Contents/Resources/auto-xray-core-helper.rb"
cp "$SUPERVISOR" "$APP_DIR/Contents/Resources/auto-xray-helper.rb"
cp "$XRAY" "$APP_DIR/Contents/Resources/xray"
cp "$NOTICE" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.txt"
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/Dove.icns" || fail "Не удалось создать иконку AUTO Xray."
chmod 644 "$APP_DIR/Contents/Resources/auto-xray-core-helper.rb" "$APP_DIR/Contents/Resources/auto-xray-helper.rb"
chmod +x "$APP_DIR/Contents/Resources/xray"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AUTO Xray" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleName AUTO Xray" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.autoxray.menubar" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION//./}" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION//./}" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Dove.icns" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Dove.icns" "$PLIST" 2>/dev/null || true

/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Resources/xray" >/dev/null 2>&1 || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

# Force Finder / LaunchServices / Launchpad to notice the replaced bundle and icon.
/usr/bin/touch "$APP_DIR"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
/usr/bin/killall Dock >/dev/null 2>&1 || true

/usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" \
  /usr/bin/ruby -EUTF-8:UTF-8 "$APP_DIR/Contents/Resources/auto-xray-helper.rb" bootstrap >/dev/null || fail "Первичная настройка не выполнена."

CURRENT_TTY="$(/usr/bin/tty 2>/dev/null || true)"
/usr/bin/open "$APP_DIR"
/usr/bin/osascript -e 'display dialog "AUTO Xray установлен и запущен." buttons {"OK"} default button "OK" with title "AUTO Xray"' >/dev/null 2>&1 || true

# When the installer was opened by double-click in Finder, Terminal otherwise leaves
# a completed window on screen. Close only the Terminal window that owns this TTY.
if [[ "$CURRENT_TTY" == /dev/ttys* ]]; then
  (
    /bin/sleep 1
    /usr/bin/osascript - "$CURRENT_TTY" <<'APPLESCRIPT'
on run argv
  set targetTTY to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      try
        if (tty of selected tab of w as text) is targetTTY then
          close w
          return
        end if
      end try
    end repeat
  end tell
end run
APPLESCRIPT
  ) >/dev/null 2>&1 &
fi

exit 0
