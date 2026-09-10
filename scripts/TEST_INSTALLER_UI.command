#!/bin/bash
set -u

STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
REPORT="$HOME/Desktop/AUTO_Xray_Installer_UI_Test_$STAMP.txt"
DONE="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.done"
STATE="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.state"
READY="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.ready"
UI_LOG="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.log"

set_progress() {
  local value="$1"
  local message="$2"
  local tmp="${STATE}.tmp.$$"
  /usr/bin/printf '%s\t%s\n' "$value" "$message" > "$tmp" 2>/dev/null || return 0
  /bin/mv -f "$tmp" "$STATE" >/dev/null 2>&1 || /bin/rm -f "$tmp" >/dev/null 2>&1 || true
  return 0
}

run_progress_ui() {
  /usr/bin/python - "$1" "$2" "$3" "$4" <<'PY'
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
state_path = sys.argv[2] if len(sys.argv) > 2 else ""
ready_path = sys.argv[3] if len(sys.argv) > 3 else ""
version = sys.argv[4] if len(sys.argv) > 4 else ""


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


def apply_state(progress, detail):
    if not state_path or not os.path.exists(state_path):
        return
    try:
        raw = open(state_path, 'rb').read().decode('utf-8', 'replace').strip()
        parts = raw.split('\t', 1)
        if parts and parts[0]:
            value = max(0.0, min(100.0, float(parts[0])))
            progress.setDoubleValue_(value)
        if len(parts) > 1 and parts[1].strip():
            detail.setStringValue_(parts[1].strip())
    except Exception as exc:
        sys.stderr.write("Progress state read failed: %s\n" % exc)


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
detail = make_label(NSMakeRect(30, 57, 320, 20), "Подготовка…", 11, False)
content.addSubview_(detail)

progress = NSProgressIndicator.alloc().initWithFrame_(NSMakeRect(45, 27, 290, 16))
progress.setIndeterminate_(False)
progress.setMinValue_(0.0)
progress.setMaxValue_(100.0)
progress.setDoubleValue_(3.0)
progress.setStyle_(NSProgressIndicatorBarStyle)
content.addSubview_(progress)

apply_state(progress, detail)
window.center()
window.makeKeyAndOrderFront_(None)
window.orderFrontRegardless()
app.activateIgnoringOtherApps_(True)
window.displayIfNeeded()

if ready_path:
    try:
        open(ready_path, 'wb').write(b'ready\n')
    except Exception as exc:
        sys.stderr.write("Ready marker failed: %s\n" % exc)

while done_path and not os.path.exists(done_path):
    apply_state(progress, detail)
    NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(0.1))

apply_state(progress, detail)
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
  echo "Progress mode: determinate simulated stages"
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
printf 'После появления окна полоса должна заметно пройти несколько этапов до 100%%.\n'
printf 'Ничего не устанавливается.\n\n'

/bin/rm -f "$DONE" "$STATE" "$READY" "$UI_LOG" >/dev/null 2>&1 || true
set_progress 5 "Подготовка…"
run_progress_ui "$DONE" "$STATE" "$READY" "UI test" >"$UI_LOG" 2>&1 &
PID=$!

i=0
while [ ! -f "$READY" ] && /bin/kill -0 "$PID" >/dev/null 2>&1 && [ "$i" -lt 100 ]; do
  /bin/sleep 0.1
  i=$((i + 1))
done

if [ -f "$READY" ]; then
  echo "UI ready before simulation: yes" >> "$REPORT"
  set_progress 15 "Проверка пакета…"
  /bin/sleep 1
  set_progress 35 "Подготовка системы…"
  /bin/sleep 1
  set_progress 58 "Копирование компонентов…"
  /bin/sleep 1
  set_progress 82 "Первичная настройка…"
  /bin/sleep 1
  set_progress 100 "Готово"
  /bin/sleep 0.7
else
  echo "UI ready before simulation: no" >> "$REPORT"
fi

/usr/bin/touch "$DONE" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1
RC=$?
/bin/rm -f "$DONE" "$STATE" "$READY" >/dev/null 2>&1 || true

echo "UI exit code: $RC" >> "$REPORT"
if [ -s "$UI_LOG" ]; then
  echo "--- UI stderr/stdout ---" >> "$REPORT"
  /bin/cat "$UI_LOG" >> "$REPORT"
  echo "--- end UI stderr/stdout ---" >> "$REPORT"
fi
/bin/rm -f "$UI_LOG" >/dev/null 2>&1 || true

printf 'Вы видели окно и заметное движение полосы прогресса? [y/N]: '
IFS= read -r ANSWER
case "$ANSWER" in
  y|Y|yes|YES|Yes|д|Д|да|Да|ДА)
    SAW="Да"
    ;;
  *)
    SAW="Нет"
    ;;
esac

echo "User saw moving indicator: $SAW" >> "$REPORT"
if [ "$RC" -eq 0 ] && [ "$SAW" = "Да" ]; then
  echo "RESULT: PASS" >> "$REPORT"
  printf '\nPASS: движущийся индикатор подтверждён пользователем.\n'
else
  echo "RESULT: FAIL" >> "$REPORT"
  printf '\nFAIL: движущийся индикатор не подтверждён.\n'
fi

printf 'Отчёт сохранён на Desktop:\n%s\n' "$REPORT"
printf '\nЭтот preflight не открывал Install AUTO Xray.app и не менял Gatekeeper.\n'
printf 'Можно закрыть Terminal.\n'
