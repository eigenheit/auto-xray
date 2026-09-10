#!/bin/bash
set -u

APP_DIR="$HOME/Applications/AUTO Xray.app"
RES="$APP_DIR/Contents/Resources"
HELPER="$RES/auto-xray-helper.rb"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
OUT_DIR="$HOME/Desktop/AUTO_Xray_Install_Test_$STAMP"
REPORT="$OUT_DIR/install-test.log"
TIMELINE="$OUT_DIR/install-timeline.tsv"
PROCESSES="$OUT_DIR/process-events.tsv"
BASELINE="$OUT_DIR/baseline.txt"
FIRST_STATE="$OUT_DIR/first-launch-state.txt"
SUMMARY="$OUT_DIR/timing-summary.txt"
ARCHIVE="$OUT_DIR.zip"
STOP_FILE="${TMPDIR:-/tmp}/auto-xray-install-monitor-${UID:-0}-$$.stop"
INSTALL_SEEN="${TMPDIR:-/tmp}/auto-xray-install-monitor-${UID:-0}-$$.install"
FIRST_LAUNCH_SEEN="${TMPDIR:-/tmp}/auto-xray-install-monitor-${UID:-0}-$$.launch"
START_MS=0
START_EPOCH=0
MONITOR_PID=""

mkdir -p "$OUT_DIR"
: > "$REPORT"
: > "$TIMELINE"
: > "$PROCESSES"

log() {
  /usr/bin/printf '%s\n' "$*" | /usr/bin/tee -a "$REPORT"
}

monotonic_ms() {
  /usr/bin/ruby -e 'puts((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round)' 2>/dev/null
}

elapsed_ms() {
  local now
  now="$(monotonic_ms)"
  /usr/bin/expr "$now" - "$START_MS"
}

record_event() {
  local kind="$1" detail="$2" ms
  ms="$(elapsed_ms)"
  /usr/bin/printf '%s\t%s\t%s\n' "$ms" "$kind" "$detail" >> "$TIMELINE"
  log "T+${ms} ms [$kind] $detail"
}

sanitize_line() {
  /usr/bin/sed -E \
    -e "s#${HOME}#~#g" \
    -e 's#https?://[^[:space:]]+#<URL>#g' \
    -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g'
}

relevant_processes() {
  /bin/ps -axo pid=,ppid=,command= 2>/dev/null | \
    /usr/bin/grep -E 'Install AUTO Xray\.app|INSTALL_AUTO_XRAY_CATALINA\.command|install-catalina\.command|dmg-installer-launcher\.sh|installer-progress|AUTO Xray\.app/Contents/MacOS|auto-xray-helper\.rb|auto-xray-core-helper\.rb|/Contents/Resources/xray( |$)|osacompile|codesign|lsregister' | \
    /usr/bin/grep -v -E 'grep -E|RUN_AUTO_XRAY_INSTALL_TEST\.command' | \
    sanitize_line | /usr/bin/sort -n || true
}

app_version() {
  local plist="$APP_DIR/Contents/Info.plist"
  [ -f "$plist" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true
}

app_mtime() {
  [ -d "$APP_DIR" ] || { echo 0; return; }
  /usr/bin/stat -f '%m' "$APP_DIR" 2>/dev/null || echo 0
}

capture_proxy_state() {
  local title="$1"
  {
    echo "--- $title ---"
    /usr/bin/env LC_ALL=C /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      case "$svc" in "An asterisk"*) continue ;; esac
      svc="${svc#\*}"
      echo "[$svc]"
      /usr/bin/env LC_ALL=C /usr/sbin/networksetup -getwebproxy "$svc" 2>/dev/null || true
      /usr/bin/env LC_ALL=C /usr/sbin/networksetup -getsecurewebproxy "$svc" 2>/dev/null || true
      /usr/bin/env LC_ALL=C /usr/sbin/networksetup -getsocksfirewallproxy "$svc" 2>/dev/null || true
    done
  } | sanitize_line
}

monitor_loop() {
  local prev cur tmp now install_started app_present helper_present xray_present launch_seen base_mtime
  prev="${TMPDIR:-/tmp}/auto-xray-install-prev-${UID:-0}-$$.txt"
  cur="${TMPDIR:-/tmp}/auto-xray-install-cur-${UID:-0}-$$.txt"
  tmp="${TMPDIR:-/tmp}/auto-xray-install-diff-${UID:-0}-$$.txt"
  relevant_processes > "$prev"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    /usr/bin/printf '0\tBASELINE\t%s\n' "$line" >> "$PROCESSES"
  done < "$prev"

  base_mtime="$(app_mtime)"
  install_started=0
  app_present=0
  helper_present=0
  xray_present=0
  launch_seen=0
  [ -d "$APP_DIR" ] && app_present=1
  [ -f "$HELPER" ] && helper_present=1
  [ -x "$RES/xray" ] && xray_present=1

  while [ ! -f "$STOP_FILE" ]; do
    relevant_processes > "$cur"
    if ! /usr/bin/cmp -s "$prev" "$cur"; then
      now="$(elapsed_ms)"
      /usr/bin/comm -13 "$prev" "$cur" > "$tmp" 2>/dev/null || true
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        /usr/bin/printf '%s\tSTART\t%s\n' "$now" "$line" >> "$PROCESSES"
      done < "$tmp"
      /usr/bin/comm -23 "$prev" "$cur" > "$tmp" 2>/dev/null || true
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        /usr/bin/printf '%s\tEXIT\t%s\n' "$now" "$line" >> "$PROCESSES"
      done < "$tmp"
      /bin/cp "$cur" "$prev" >/dev/null 2>&1 || true
    fi

    if [ "$install_started" -eq 0 ]; then
      if /usr/bin/grep -Eq 'Install AUTO Xray\.app|INSTALL_AUTO_XRAY_CATALINA\.command|install-catalina\.command|dmg-installer-launcher\.sh' "$cur" 2>/dev/null; then
        install_started=1
        /usr/bin/touch "$INSTALL_SEEN"
        /usr/bin/printf '%s\tINSTALL_START\tinstaller process detected\n' "$(elapsed_ms)" >> "$TIMELINE"
      elif [ "$(app_mtime)" != "$base_mtime" ]; then
        install_started=1
        /usr/bin/touch "$INSTALL_SEEN"
        /usr/bin/printf '%s\tINSTALL_START\tapplication bundle changed\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi
    fi

    if [ "$install_started" -eq 1 ]; then
      if [ "$app_present" -eq 1 ] && [ ! -d "$APP_DIR" ]; then
        app_present=0
        /usr/bin/printf '%s\tAPP_REMOVED\tprevious application bundle removed\n' "$(elapsed_ms)" >> "$TIMELINE"
      elif [ "$app_present" -eq 0 ] && [ -d "$APP_DIR" ]; then
        app_present=1
        /usr/bin/printf '%s\tAPP_CREATED\tapplication bundle appeared\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi

      if [ "$helper_present" -eq 0 ] && [ -f "$HELPER" ]; then
        helper_present=1
        /usr/bin/printf '%s\tHELPER_READY\tpublic helper present\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi
      if [ "$xray_present" -eq 0 ] && [ -x "$RES/xray" ]; then
        xray_present=1
        /usr/bin/printf '%s\tXRAY_READY\txray executable present\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi

      if [ "$launch_seen" -eq 0 ] && /usr/bin/grep -q 'AUTO Xray\.app/Contents/MacOS' "$cur" 2>/dev/null; then
        launch_seen=1
        /usr/bin/printf '%s\tFIRST_LAUNCH\tAUTO Xray process detected\n' "$(elapsed_ms)" >> "$TIMELINE"
        /usr/bin/touch "$FIRST_LAUNCH_SEEN"
      fi
    fi

    /bin/sleep 0.20
  done

  /bin/rm -f "$prev" "$cur" "$tmp" >/dev/null 2>&1 || true
}

finish() {
  /usr/bin/touch "$STOP_FILE" >/dev/null 2>&1 || true
  if [ -n "$MONITOR_PID" ]; then
    wait "$MONITOR_PID" >/dev/null 2>&1 || true
  fi
  /bin/rm -f "$STOP_FILE" "$INSTALL_SEEN" "$FIRST_LAUNCH_SEEN" >/dev/null 2>&1 || true
}

trap finish EXIT
trap 'exit 130' INT TERM

START_MS="$(monotonic_ms)"
START_EPOCH="$(/bin/date '+%s')"

{
  echo "AUTO Xray install + first-launch timing test"
  echo "Started: $(/bin/date)"
  echo "Machine: $(/usr/bin/uname -m)"
  echo "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "Existing app: $([ -d "$APP_DIR" ] && echo yes || echo no)"
  echo "Existing version: $(app_version)"
  echo "Existing app mtime: $(app_mtime)"
  echo "Test script: $0"
  echo
  capture_proxy_state "Proxy state before installation"
} > "$BASELINE"

log "AUTO Xray — монитор установки и первого запуска"
log ""
log "Тест запущен ДО установки. Он фиксирует только процессы AUTO Xray/установщика, а не все процессы macOS."
log "Для каждого события используется монотонный таймер в миллисекундах. URL подписки и UUID в process-log редактируются."
log ""
log "Теперь запустите установщик AUTO Xray обычным способом и оставьте это окно Terminal открытым."
log "Подойдут DMG → Install AUTO Xray.app или ZIP → INSTALL_AUTO_XRAY_CATALINA.command."
log ""

record_event "MONITOR_READY" "waiting for installer"
monitor_loop &
MONITOR_PID=$!

i=0
while [ ! -f "$FIRST_LAUNCH_SEEN" ] && [ "$i" -lt 3000 ]; do
  /bin/sleep 0.20
  i=$((i + 1))
done

if [ ! -f "$FIRST_LAUNCH_SEEN" ]; then
  record_event "TIMEOUT" "first AUTO Xray launch was not observed within 10 minutes"
  log ""
  log "Не удалось дождаться первого запуска за 10 минут. Отчёт всё равно сохранён в $OUT_DIR."
  exit 2
fi

record_event "FIRST_LAUNCH_OBSERVED" "checking first menu-state response"
/bin/sleep 0.5

MENU_TMP="$OUT_DIR/menu-state-first.txt"
MENU_META="$OUT_DIR/menu-state-first-timing.txt"
start="$(monotonic_ms)"
if [ -f "$HELPER" ]; then
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$RES" \
    /usr/bin/ruby -EUTF-8:UTF-8 "$HELPER" menu-state > "$MENU_TMP" 2>&1
  MENU_RC=$?
else
  /usr/bin/printf 'helper missing\n' > "$MENU_TMP"
  MENU_RC=127
fi
end="$(monotonic_ms)"
MENU_MS=$((end - start))
/usr/bin/printf 'menu-state-ms\t%s\nrc\t%s\n' "$MENU_MS" "$MENU_RC" > "$MENU_META"
record_event "MENU_STATE" "first response ${MENU_MS} ms rc=${MENU_RC}"

{
  echo "Observed version: $(app_version)"
  echo "App exists: $([ -d "$APP_DIR" ] && echo yes || echo no)"
  echo "Helper exists: $([ -f "$HELPER" ] && echo yes || echo no)"
  echo "Xray executable: $([ -x "$RES/xray" ] && echo yes || echo no)"
  echo "First menu-state: ${MENU_MS} ms rc=${MENU_RC}"
  echo
  capture_proxy_state "Proxy state after first launch"
  echo
  echo "Listeners after first launch:"
  /usr/sbin/lsof -nP -iTCP:2081 -sTCP:LISTEN 2>/dev/null | sanitize_line || true
  /usr/sbin/lsof -nP -iTCP:9001 -sTCP:LISTEN 2>/dev/null | sanitize_line || true
} > "$FIRST_STATE"

/usr/bin/touch "$STOP_FILE" >/dev/null 2>&1 || true
wait "$MONITOR_PID" >/dev/null 2>&1 || true
MONITOR_PID=""

{
  echo -e "elapsed_ms\tevent\tdetail"
  /bin/cat "$TIMELINE"
} > "$SUMMARY"

log ""
log "Установка и первый запуск зафиксированы."
log "Версия приложения: $(app_version)"
log "Первый menu-state: ${MENU_MS} ms (rc=${MENU_RC})"
log ""
printf 'Начать автоматические тесты работы AUTO Xray с замером отклика? [Y/n]: '
IFS= read -r ANSWER
case "$ANSWER" in
  n|N|no|NO|No|н|Н|нет|Нет|НЕТ) RUN_RUNTIME=0 ;;
  *) RUN_RUNTIME=1 ;;
esac

if [ "$RUN_RUNTIME" -eq 1 ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  RUNNER=""
  for candidate in \
    "$SCRIPT_DIR/RUN_AUTO_XRAY_TESTS.command" \
    "$SCRIPT_DIR/Diagnostics/RUN_AUTO_XRAY_TESTS.command" \
    "$(dirname "$SCRIPT_DIR")/RUN_AUTO_XRAY_TESTS.command"; do
    if [ -f "$candidate" ]; then
      RUNNER="$candidate"
      break
    fi
  done

  if [ -n "$RUNNER" ]; then
    record_event "RUNTIME_TEST_START" "starting RUN_AUTO_XRAY_TESTS.command"
    /bin/bash "$RUNNER"
    RUNTIME_RC=$?
    record_event "RUNTIME_TEST_END" "runtime self-test rc=${RUNTIME_RC}"

    LATEST_RUNTIME_ZIP="$(/bin/ls -t "$HOME/Desktop"/AUTO_Xray_Test_*.zip 2>/dev/null | /usr/bin/head -n 1 || true)"
    if [ -n "$LATEST_RUNTIME_ZIP" ]; then
      ZIP_MTIME="$(/usr/bin/stat -f '%m' "$LATEST_RUNTIME_ZIP" 2>/dev/null || echo 0)"
      if [ "$ZIP_MTIME" -ge "$START_EPOCH" ]; then
        /bin/cp "$LATEST_RUNTIME_ZIP" "$OUT_DIR/runtime-selftest.zip" 2>/dev/null || true
        log "Runtime-архив добавлен в общий отчёт: runtime-selftest.zip"
      fi
    fi
  else
    record_event "RUNTIME_TEST_SKIPPED" "RUN_AUTO_XRAY_TESTS.command not found beside monitor"
    log "RUN_AUTO_XRAY_TESTS.command рядом с монитором не найден. Runtime-тест можно запустить отдельно."
  fi
else
  record_event "RUNTIME_TEST_SKIPPED" "user chose not to start runtime suite"
fi

record_event "SESSION_END" "creating combined archive"
{
  echo -e "elapsed_ms\tevent\tdetail"
  /bin/cat "$TIMELINE"
} > "$SUMMARY"

log ""
log "Итоговые файлы:"
log "  $TIMELINE"
log "  $PROCESSES"
log "  $FIRST_STATE"

(cd "$HOME/Desktop" && /usr/bin/zip -qry "$ARCHIVE" "$(/usr/bin/basename "$OUT_DIR")") >/dev/null 2>&1 || true
log ""
log "Готово. Общий архив для отправки ChatGPT:"
log "$ARCHIVE"

exit 0
