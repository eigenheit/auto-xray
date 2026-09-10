#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && /bin/pwd)"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
REPORT="$HOME/Desktop/AUTO_Xray_Installer_UI_Test_$STAMP.txt"
DONE="${TMPDIR:-/tmp}/auto-xray-ui-test-${UID:-0}-$$.done"

find_helper() {
  local candidate

  for candidate in \
    "$SCRIPT_DIR/installer-progress" \
    "$SCRIPT_DIR/../Install AUTO Xray.app/Contents/Resources/installer-progress" \
    /Volumes/AUTO\ Xray\ */Install\ AUTO\ Xray.app/Contents/Resources/installer-progress
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

HELPER="$(find_helper || true)"

{
  echo "AUTO Xray installer UI preflight"
  echo "Started: $(/bin/date)"
  echo "Machine: $(/usr/bin/uname -m)"
  echo "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Test script: $0"
  echo "Resolved helper: ${HELPER:-not found}"
} > "$REPORT"

if [ -z "$HELPER" ] || [ ! -x "$HELPER" ]; then
  echo "RESULT: FAIL - progress helper missing or not executable" >> "$REPORT"
  printf '\nAUTO Xray — тест индикатора\n\n'
  printf 'Не найден исполняемый индикатор установки.\n'
  printf 'Ничего не устанавливалось и системные настройки не менялись.\n\n'
  printf 'Оставьте DMG AUTO Xray смонтированным и запустите этот файл снова.\n'
  printf 'Его можно запускать как из папки Diagnostics внутри DMG, так и после копирования на Desktop.\n\n'
  printf 'Отчёт: %s\n' "$REPORT"
  exit 1
fi

printf '\nAUTO Xray — тест индикатора\n\n'
printf 'Сейчас примерно на 6 секунд должно появиться окно «Установка AUTO Xray…»\n'
printf 'с полосой активности. Этот тест ничего не устанавливает.\n\n'

/bin/rm -f "$DONE" >/dev/null 2>&1 || true
"$HELPER" "$DONE" "UI test" >/dev/null 2>&1 &
PID=$!
/bin/sleep 6
/usr/bin/touch "$DONE" >/dev/null 2>&1 || true
wait "$PID" >/dev/null 2>&1
RC=$?
/bin/rm -f "$DONE" >/dev/null 2>&1 || true

echo "Helper exit code: $RC" >> "$REPORT"

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
printf '\nМожно закрыть Terminal.\n'
