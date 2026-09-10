#!/bin/bash
set -u

BUNDLE_ROOT="$(cd "$(dirname "$0")/.." && /bin/pwd)"
PAYLOAD="$BUNDLE_ROOT/Resources/payload"
PROGRESS_SCRIPT="$BUNDLE_ROOT/Resources/dmg-install-progress.js"
LOG_DIR="$HOME/Library/Logs/AUTO Xray"
LOG_FILE="$LOG_DIR/installer.log"
PROGRESS_DONE="${TMPDIR:-/tmp}/auto-xray-install-progress-${UID:-0}-$$.done"
PROGRESS_PID=""

show_error() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon stop with title "AUTO Xray"
end run
APPLESCRIPT
}

start_progress() {
  /bin/rm -f "$PROGRESS_DONE" >/dev/null 2>&1 || true
  [ -f "$PROGRESS_SCRIPT" ] || return 0
  /usr/bin/osascript -l JavaScript "$PROGRESS_SCRIPT" "$PROGRESS_DONE" "$VERSION" >/dev/null 2>&1 &
  PROGRESS_PID=$!
}

stop_progress() {
  /usr/bin/touch "$PROGRESS_DONE" >/dev/null 2>&1 || true
  if [ -n "$PROGRESS_PID" ]; then
    local i=0
    while /bin/kill -0 "$PROGRESS_PID" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
      /bin/sleep 0.1
      i=$((i + 1))
    done
    /bin/kill "$PROGRESS_PID" >/dev/null 2>&1 || true
    wait "$PROGRESS_PID" >/dev/null 2>&1 || true
  fi
  /bin/rm -f "$PROGRESS_DONE" >/dev/null 2>&1 || true
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
start_progress
trap stop_progress EXIT INT TERM HUP
{
  echo "=== AUTO Xray DMG install $(/bin/date) ==="
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_GUI_INSTALLER=1 \
    /bin/bash "$PAYLOAD/scripts/install-catalina.command"
} >"$LOG_FILE" 2>&1
RC=$?
stop_progress
trap - EXIT INT TERM HUP

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
