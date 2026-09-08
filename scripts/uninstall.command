#!/bin/bash
set -euo pipefail

APP=""
for C in "/Applications/AUTO Xray.app" "$HOME/Applications/AUTO Xray.app"; do
  if [ -d "$C" ]; then APP="$C"; break; fi
done

SUPPORT="$HOME/Library/Application Support/AUTO Xray"
LOGS="$HOME/Library/Logs/AUTO Xray"
PLIST="$HOME/Library/LaunchAgents/local.autoxray.menubar.plist"

if [ -n "$APP" ] && [ -f "$APP/Contents/Resources/auto-xray-helper.rb" ]; then
  AUTO_XRAY_RESOURCES="$APP/Contents/Resources" /usr/bin/ruby "$APP/Contents/Resources/auto-xray-helper.rb" stop >/dev/null 2>&1 || true
  AUTO_XRAY_RESOURCES="$APP/Contents/Resources" /usr/bin/ruby "$APP/Contents/Resources/auto-xray-helper.rb" uninstall-login-agent >/dev/null 2>&1 || true
fi

/usr/bin/osascript -e 'tell application "AUTO Xray" to quit' >/dev/null 2>&1 || true
/bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
[ -n "$APP" ] && rm -rf "$APP"

CHOICE=$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
display dialog "AUTO Xray удален. Удалить также подписку, HWID, JSON и логи?" buttons {"Оставить данные", "Удалить все"} default button "Оставить данные" with title "AUTO Xray"
return button returned of result
APPLESCRIPT
)

if [ "$CHOICE" = "Удалить все" ]; then
  rm -rf "$SUPPORT" "$LOGS"
fi
