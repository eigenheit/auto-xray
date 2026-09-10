#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && /bin/pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && /bin/pwd)"
HELPER="$ROOT/Install AUTO Xray.app/Contents/Resources/installer-progress"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
REPORT="$HOME/Desktop/AUTO_Xray_Installer_UI_Test_$STAMP.txt"
DONE="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.done"

{
  echo "AUTO Xray installer UI preflight"
  echo "Started: $(/bin/date)"
  echo "Machine: $(/usr/bin/uname -m)"
  echo "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Helper: $HELPER"
} > "$REPORT"

if [ ! -x "$HELPER" ]; then
  echo "RESULT: FAIL - progress helper missing or not executable" >> "$REPORT"
  /usr/bin/osascript -e 'display dialog "Не найден исполняемый индикатор установки. Ничего не устанавливалось." buttons {"OK"} default button "OK" with icon stop with title "AUTO Xray"' >/dev/null 2>&1 || true
  exit 1
fi

/bin/rm -f "$DONE" >/dev/null 2>&1 || true
"$HELPER" "$DONE" "UI test" >/dev/null 2>&1 &
PID=$!
/bin/sleep 6
/usr/bin/touch "$DONE" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1
RC=$?
/bin/rm -f "$DONE" >/dev/null 2>&1 || true

echo "Helper exit code: $RC" >> "$REPORT"

CHOICE="$(/usr/bin/osascript -e 'button returned of (display dialog "Перед этим примерно 6 секунд должно было быть видно окно «Установка AUTO Xray…» с полосой активности. Вы его видели?\n\nЭтот тест ничего не устанавливает." buttons {"Нет", "Да"} default button "Да" with title "AUTO Xray — тест индикатора")' 2>/dev/null || echo "Нет")"

echo "User saw indicator: $CHOICE" >> "$REPORT"
if [ "$RC" -eq 0 ] && [ "$CHOICE" = "Да" ]; then
  echo "RESULT: PASS" >> "$REPORT"
else
  echo "RESULT: FAIL" >> "$REPORT"
fi

/usr/bin/osascript -e "display dialog \"Тест завершён. Отчёт сохранён на Desktop:\n$(/usr/bin/basename "$REPORT")\" buttons {\"OK\"} default button \"OK\" with title \"AUTO Xray\"" >/dev/null 2>&1 || true
