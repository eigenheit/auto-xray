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

if ! /usr/bin/osascript - "$VERSION" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set v to item 1 of argv
  display dialog "Установить AUTO Xray " & v & "?\n\nПодписка, HWID и настройки будут сохранены. После установки AUTO Xray запустится в состоянии OFF, поэтому обычный интернет должен продолжить работать напрямую." buttons {"Отмена", "Установить"} default button "Установить" cancel button "Отмена" with title "AUTO Xray"
end run
APPLESCRIPT
then
  exit 0
fi

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
  display dialog "AUTO Xray " & v & " установлен и запущен.\n\nГолубь в строке меню сейчас должен быть полупрозрачным: AUTO Xray OFF. Обычный интернет работает напрямую. Для подключения нажмите голубя → Включить." buttons {"Готово"} default button "Готово" with title "AUTO Xray"
end run
APPLESCRIPT
  exit 0
fi

show_error "Установка не завершена.\n\nЛог сохранен здесь:\n~/Library/Logs/AUTO Xray/installer.log"
exit "$RC"
