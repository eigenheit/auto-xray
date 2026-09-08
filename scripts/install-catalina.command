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
ICON="assets/Dove.icns"
NOTICE="THIRD_PARTY_NOTICES.txt"

fail() { echo; echo "ERROR: $1"; echo; exit 1; }

[ "$(/usr/bin/uname -m)" = "x86_64" ] || fail "Этот установщик предназначен для Intel Mac."
[ -x "$XRAY" ] || fail "В пакете отсутствует встроенный Xray-core."
[ -f "$XRAY_SUMS" ] || fail "В пакете отсутствует контрольная сумма Xray-core."
[ -f "$ICON" ] || fail "В пакете отсутствует иконка AUTO Xray."
[ -f "$CORE_HELPER" ] || fail "В пакете отсутствует основной helper."
[ -f "$SUPERVISOR" ] || fail "В пакете отсутствует supervisor."

EXPECTED_SHA="$(/usr/bin/head -n 1 "$XRAY_SUMS" | /usr/bin/cut -c 1-64)"
ACTUAL_SHA="$(/usr/bin/env LC_ALL=C /usr/bin/shasum -a 256 "$XRAY" | /usr/bin/cut -c 1-64)"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "EXPECTED: $EXPECTED_SHA"
  echo "ACTUAL:   $ACTUAL_SHA"
  fail "Встроенный Xray-core не прошел проверку контрольной суммы."
fi

/usr/bin/ruby -EUTF-8:UTF-8 -c "$CORE_HELPER" >/dev/null || fail "Основной Ruby helper поврежден."
/usr/bin/ruby -EUTF-8:UTF-8 -c "$SUPERVISOR" >/dev/null || fail "Ruby supervisor поврежден."

# Stop an already installed version only after the new package passed validation.
if [ -f "$APP_DIR/Contents/Resources/auto-xray-helper.rb" ]; then
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" \
    /usr/bin/ruby -EUTF-8:UTF-8 "$APP_DIR/Contents/Resources/auto-xray-helper.rb" stop >/dev/null 2>&1 || true
fi
/usr/bin/osascript -e 'tell application "AUTO Xray" to quit' >/dev/null 2>&1 || true
sleep 1

mkdir -p "$HOME/Applications"
rm -rf "$APP_DIR"

/usr/bin/osacompile -s -o "$APP_DIR" "$SRC"
mkdir -p "$APP_DIR/Contents/Resources"

# The original helper becomes the core implementation. The small supervisor keeps
# the public helper name so the menu app does not need a second command path.
cp "$CORE_HELPER" "$APP_DIR/Contents/Resources/auto-xray-core-helper.rb"
cp "$SUPERVISOR" "$APP_DIR/Contents/Resources/auto-xray-helper.rb"
cp "$XRAY" "$APP_DIR/Contents/Resources/xray"
cp "$NOTICE" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.txt"

# Use an ICNS generated during the GitHub release build. Creating ICNS dynamically
# with Catalina's old sips/iconutil produced corrupted artwork on some legacy Macs.
cp "$ICON" "$APP_DIR/Contents/Resources/Dove.icns"

chmod 644 "$APP_DIR/Contents/Resources/auto-xray-core-helper.rb"
chmod 644 "$APP_DIR/Contents/Resources/auto-xray-helper.rb"
chmod 644 "$APP_DIR/Contents/Resources/Dove.icns"
chmod +x "$APP_DIR/Contents/Resources/xray"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AUTO Xray" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.autoxray.menubar" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${VERSION//./}" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION//./}" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Dove.icns" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Dove.icns" "$PLIST" 2>/dev/null || true

/usr/bin/codesign --force --sign - "$APP_DIR/Contents/Resources/xray" >/dev/null 2>&1 || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
/usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$APP_DIR/Contents/Resources" \
  /usr/bin/ruby -EUTF-8:UTF-8 "$APP_DIR/Contents/Resources/auto-xray-helper.rb" bootstrap >/dev/null || fail "Первичная настройка не выполнена."

# Explicitly register the user-local application with Launch Services. This makes
# ~/Applications/AUTO Xray.app visible to Finder/Launchpad on legacy macOS.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
/usr/bin/touch "$APP_DIR"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

CURRENT_TTY="$(/usr/bin/tty 2>/dev/null || true)"
/usr/bin/open "$APP_DIR"
/usr/bin/osascript -e 'display dialog "AUTO Xray установлен и запущен." buttons {"OK"} default button "OK" with title "AUTO Xray"' >/dev/null 2>&1 || true

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
