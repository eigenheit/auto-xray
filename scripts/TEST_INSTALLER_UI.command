#!/bin/bash
set -u

STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
REPORT="$HOME/Desktop/AUTO_Xray_Installer_UI_Test_$STAMP.txt"
DONE="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.done"
UI_LOG="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.log"

run_progress_ui() {
  /usr/bin/python - "$1" "$2" <<'PY'
# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import os
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

{
  echo "AUTO Xray installer UI preflight"
  echo "Started: $(/bin/date)"
  echo "Machine: $(/usr/bin/uname -m)"
  echo "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Test script: $0"
  echo "UI method: /usr/bin/python + system PyObjC/Cocoa"
  echo "Installer app touched: no"
} > "$REPORT"

if [ "$(/usr/bin/uname -m)" != "x86_64" ]; then
  echo "RESULT: FAIL - not an Intel Mac" >> "$REPORT"
  printf '\nFAIL: этот тест предназначен для Intel Mac.\n'
  printf 'Отчёт: %s\n' "$REPORT"
  exit 1
fi

if [ ! -x /usr/bin/python ]; then
  echo "RESULT: FAIL - /usr/bin/python missing" >> "$REPORT"
  printf '\nFAIL: системный Python Catalina не найден.\n'
  printf 'Отчёт: %s\n' "$REPORT"
  exit 1
fi

printf '\nAUTO Xray — тест индикатора\n\n'
printf 'Этот тест НЕ запускает и НЕ открывает Install AUTO Xray.app.\n'
printf 'Он использует только системный Python/PyObjC Catalina.\n\n'
printf 'Сейчас примерно на 6 секунд должно появиться окно «Установка AUTO Xray…»\n'
printf 'с полосой активности. Ничего не устанавливается.\n\n'

/bin/rm -f "$DONE" "$UI_LOG" >/dev/null 2>&1 || true
run_progress_ui "$DONE" "UI test" >"$UI_LOG" 2>&1 &
PID=$!
/bin/sleep 6
/usr/bin/touch "$DONE" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1
RC=$?
/bin/rm -f "$DONE" >/dev/null 2>&1 || true

echo "UI exit code: $RC" >> "$REPORT"
if [ -s "$UI_LOG" ]; then
  echo "--- UI stderr/stdout ---" >> "$REPORT"
  /bin/cat "$UI_LOG" >> "$REPORT"
  echo "--- end UI stderr/stdout ---" >> "$REPORT"
fi
/bin/rm -f "$UI_LOG" >/dev/null 2>&1 || true

printf 'Вы видели окно индикатора? [y/N]: '
IFS= read -r ANSWER
case "$ANSWER" in
  y|Y|yes|YES|Yes|д|Д|да|Да|ДА)
    SAW="Да"
    ;;
  *)
    SAW="Нет"
    ;;
esac

echo "User saw indicator: $SAW" >> "$REPORT"
if [ "$RC" -eq 0 ] && [ "$SAW" = "Да" ]; then
  echo "RESULT: PASS" >> "$REPORT"
  printf '\nPASS: индикатор подтверждён пользователем.\n'
else
  echo "RESULT: FAIL" >> "$REPORT"
  printf '\nFAIL: индикатор не подтверждён.\n'
fi

printf 'Отчёт сохранён на Desktop:\n%s\n' "$REPORT"
printf '\nЭтот preflight не открывал Install AUTO Xray.app и не менял Gatekeeper.\n'
printf 'Можно закрыть Terminal.\n'
