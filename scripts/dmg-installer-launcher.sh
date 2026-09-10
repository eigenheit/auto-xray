#!/bin/bash
set -u

BUNDLE_ROOT="$(cd "$(dirname "$0")/.." && /bin/pwd)"
PAYLOAD="$BUNDLE_ROOT/Resources/payload"
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

run_progress_ui() {
  /usr/bin/python - "$1" "$2" <<'PY'
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import sys

try:
    from AppKit import *
    from Foundation import *
except Exception as exc:
    sys.stderr.write("PyObjC import failed: %s\n" % exc)
    sys.exit(2)

done_path = sys.argv[1] if len(sys.argv) > 1 else ""
version = sys.argv[2] if len(sys.argv) > 2 else ""


def make_label(frame, text, size, bold=False):
    label = NSTextField.alloc().initWithFrame_(frame)
    label.setStringValue_(text)
    label.setBezeled_(False)
    label.setDrawsBackground_(False)
    label.setEditable_(False)
    label.setSelectable_(False)
    label.setAlignment_(NSCenterTextAlignment)
    if bold:
        label.setFont_(NSFont.boldSystemFontOfSize_(size))
    else:
        label.setFont_(NSFont.systemFontOfSize_(size))
    return label


app = NSApplication.sharedApplication()
app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
app.finishLaunching()

frame = NSMakeRect(0, 0, 380, 132)
window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
    frame, NSTitledWindowMask, NSBackingStoreBuffered, False
)
window.setReleasedWhenClosed_(False)
window.setLevel_(NSFloatingWindowLevel)
window.setTitle_("AUTO Xray %s" % version if version else "AUTO Xray")

content = window.contentView()
content.addSubview_(make_label(NSMakeRect(30, 82, 320, 24), "Установка AUTO Xray…", 14, True))
content.addSubview_(make_label(NSMakeRect(30, 57, 320, 20), "Пожалуйста, подождите. Окно закроется автоматически.", 11, False))

progress = NSProgressIndicator.alloc().initWithFrame_(NSMakeRect(45, 27, 290, 16))
progress.setIndeterminate_(True)
progress.setStyle_(NSProgressIndicatorBarStyle)
progress.startAnimation_(None)
content.addSubview_(progress)

window.center()
window.makeKeyAndOrderFront_(None)
window.orderFrontRegardless()
app.activateIgnoringOtherApps_(True)

fm = NSFileManager.defaultManager()
while done_path and not fm.fileExistsAtPath_(done_path):
    NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(0.2))

window.orderOut_(None)
sys.exit(0)
PY
}

start_progress() {
  /bin/rm -f "$PROGRESS_DONE" >/dev/null 2>&1 || true
  if [ ! -x /usr/bin/python ]; then
    echo "WARNING: /usr/bin/python unavailable; progress UI disabled" >>"$LOG_FILE"
    return 0
  fi
  run_progress_ui "$PROGRESS_DONE" "$VERSION" >>"$LOG_FILE" 2>&1 &
  PROGRESS_PID=$!
  # Give the system Cocoa window time to become visible before installation work starts.
  /bin/sleep 0.5
}

stop_progress() {
  if [ -n "$PROGRESS_PID" ] && /bin/kill -0 "$PROGRESS_PID" >/dev/null 2>&1; then
    # Keep the indicator visible long enough to be perceptible on a fast update.
    /bin/sleep 0.7
    /usr/bin/touch "$PROGRESS_DONE" >/dev/null 2>&1 || true
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
: > "$LOG_FILE"
start_progress
trap stop_progress EXIT INT TERM HUP
{
  echo "=== AUTO Xray DMG install $(/bin/date) ==="
  echo "Progress UI: /usr/bin/python + system PyObjC/Cocoa"
  if [ -n "$PROGRESS_PID" ]; then
    echo "Progress UI PID: $PROGRESS_PID"
  else
    echo "WARNING: progress UI did not start"
  fi
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_GUI_INSTALLER=1 \
    /bin/bash "$PAYLOAD/scripts/install-catalina.command"
} >>"$LOG_FILE" 2>&1
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
