#!/bin/bash
set -u

BUNDLE_ROOT="$(cd "$(dirname "$0")/.." && /bin/pwd)"
PAYLOAD="$BUNDLE_ROOT/Resources/payload"
LOG_DIR="$HOME/Library/Logs/AUTO Xray"
LOG_FILE="$LOG_DIR/installer.log"

show_error() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon stop with title "AUTO Xray"
end run
APPLESCRIPT
}

if [ "$(/usr/bin/uname -m)" != "x86_64" ]; then
  show_error "Этот установщик предназначен для Intel Mac."
  exit 1
fi

if [ ! -f "$PAYLOAD/VERSION" ] || [ ! -f "$PAYLOAD/scripts/install-catalina.command" ]; then
  show_error "Установочный пакет AUTO Xray поврежден. Скачайте DMG заново с GitHub Releases."
  exit 1
fi

VERSION="$(/bin/cat "$PAYLOAD/VERSION" | /usr/bin/tr -d '[:space:]')"

/bin/mkdir -p "$LOG_DIR"
{
  echo "=== AUTO Xray DMG install $(/bin/date) ==="
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_GUI_INSTALLER=1 \
    /bin/bash "$PAYLOAD/scripts/install-catalina.command"
} >"$LOG_FILE" 2>&1
RC=$?

if [ "$RC" -eq 0 ]; then
  /usr/bin/osascript - "$VERSION" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set v to item 1 of argv
  display notification "Установка завершена. AUTO Xray запущен в состоянии OFF." with title "AUTO Xray " & v
end run
APPLESCRIPT
  exit 0
fi

show_error "Установка не завершена.\n\nЛог сохранен здесь:\n~/Library/Logs/AUTO Xray/installer.log"
exit "$RC"
