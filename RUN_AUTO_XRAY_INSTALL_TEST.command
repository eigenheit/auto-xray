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
READY_OFF_SEEN="${TMPDIR:-/tmp}/auto-xray-install-monitor-${UID:-0}-$$.ready-off"
FIRST_LAUNCH_SEEN="${TMPDIR:-/tmp}/auto-xray-install-monitor-${UID:-0}-$$.launch"
START_MS=0
START_EPOCH=0
MONITOR_PID=""
RUNTIME_ZIP=""

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
  /usr/bin/printf '%s\n' "$((now - START_MS))"
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

app_version() {
  local plist="$APP_DIR/Contents/Info.plist"
  [ -f "$plist" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true
}

app_mtime() {
  [ -d "$APP_DIR" ] || { echo 0; return; }
  /usr/bin/stat -f '%m' "$APP_DIR" 2>/dev/null || echo 0
}

app_running() {
  /bin/ps -axo command= 2>/dev/null | /usr/bin/grep -q '[A]UTO Xray\.app/Contents/MacOS'
}

menu_state_raw() {
  [ -f "$HELPER" ] || return 127
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$RES" \
    /usr/bin/ruby -EUTF-8:UTF-8 "$HELPER" menu-state 2>/dev/null
}

menu_state_is_off() {
  local state="$1"
  /usr/bin/printf '%s' "$state" | /usr/bin/ruby -rjson -e '
    begin
      j = JSON.parse(STDIN.read)
      exit(j["on"] == false ? 0 : 1)
    rescue StandardError
      exit 1
    end
  ' >/dev/null 2>&1
}

listeners_clear() {
  [ -z "$(/usr/sbin/lsof -nP -tiTCP:2081 -sTCP:LISTEN 2>/dev/null || true)" ] && \
  [ -z "$(/usr/sbin/lsof -nP -tiTCP:9001 -sTCP:LISTEN 2>/dev/null || true)" ]
}

proxy_kind_is_auto_enabled() {
  local service="$1" flag="$2" expected_port="$3" out enabled server port
  out="$(/usr/bin/env LC_ALL=C /usr/sbin/networksetup "$flag" "$service" 2>/dev/null || true)"
  enabled="$(/usr/bin/printf '%s\n' "$out" | /usr/bin/awk -F': ' '/^Enabled:/{print $2; exit}')"
  server="$(/usr/bin/printf '%s\n' "$out" | /usr/bin/awk -F': ' '/^Server:/{print $2; exit}')"
  port="$(/usr/bin/printf '%s\n' "$out" | /usr/bin/awk -F': ' '/^Port:/{print $2; exit}')"
  [ "$enabled" = "Yes" ] && [ "$server" = "127.0.0.1" ] && [ "$port" = "$expected_port" ]
}

auto_proxy_disabled() {
  local tmp svc
  tmp="${TMPDIR:-/tmp}/auto-xray-services-${UID:-0}-$$.txt"
  /usr/bin/env LC_ALL=C /usr/sbin/networksetup -listallnetworkservices 2>/dev/null | \
    /usr/bin/sed '1{/An asterisk/d;}' > "$tmp" || true

  while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    svc="${svc#\*}"
    if proxy_kind_is_auto_enabled "$svc" -getwebproxy 9001 || \
       proxy_kind_is_auto_enabled "$svc" -getsecurewebproxy 9001 || \
       proxy_kind_is_auto_enabled "$svc" -getsocksfirewallproxy 2081; then
      /bin/rm -f "$tmp" >/dev/null 2>&1 || true
      return 1
    fi
  done < "$tmp"

  /bin/rm -f "$tmp" >/dev/null 2>&1 || true
  return 0
}

capture_proxy_state() {
  local title="$1" svc
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

relevant_processes() {
  /bin/ps -axo pid=,ppid=,command= 2>/dev/null | \
    /usr/bin/grep -E 'Install AUTO Xray\.app|INSTALL_AUTO_XRAY_CATALINA\.command|install-catalina\.command|dmg-installer-launcher\.sh|installer-progress|AUTO Xray\.app/Contents/MacOS|auto-xray-helper\.rb|auto-xray-core-helper\.rb|/Contents/Resources/xray( |$)|osacompile|codesign|lsregister' | \
    /usr/bin/grep -v -E 'grep -E|RUN_AUTO_XRAY_INSTALL_TEST\.command' | \
    sanitize_line | /usr/bin/sort || true
}

monitor_loop() {
  local prev cur added removed now base_mtime install_seen bundle_changed first_launch_seen ready_seen current_mtime state
  prev="${TMPDIR:-/tmp}/auto-xray-install-prev-${UID:-0}-$$.txt"
  cur="${TMPDIR:-/tmp}/auto-xray-install-cur-${UID:-0}-$$.txt"
  added="${TMPDIR:-/tmp}/auto-xray-install-added-${UID:-0}-$$.txt"
  removed="${TMPDIR:-/tmp}/auto-xray-install-removed-${UID:-0}-$$.txt"
  base_mtime="$(app_mtime)"
  install_seen=0
  bundle_changed=0
  first_launch_seen=0
  ready_seen=0

  relevant_processes > "$prev"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    /usr/bin/printf '0\tBASELINE\t%s\n' "$line" >> "$PROCESSES"
  done < "$prev"

  while [ ! -f "$STOP_FILE" ]; do
    relevant_processes > "$cur"
    if ! /usr/bin/cmp -s "$prev" "$cur"; then
      now="$(elapsed_ms)"
      /usr/bin/comm -13 "$prev" "$cur" > "$added" 2>/dev/null || true
      /usr/bin/comm -23 "$prev" "$cur" > "$removed" 2>/dev/null || true
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        /usr/bin/printf '%s\tSTART\t%s\n' "$now" "$line" >> "$PROCESSES"
      done < "$added"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        /usr/bin/printf '%s\tEXIT\t%s\n' "$now" "$line" >> "$PROCESSES"
      done < "$removed"
      /bin/cp "$cur" "$prev" >/dev/null 2>&1 || true
    fi

    if [ "$install_seen" -eq 0 ]; then
      if /usr/bin/grep -Eq 'Install AUTO Xray\.app|INSTALL_AUTO_XRAY_CATALINA\.command|install-catalina\.command|dmg-installer-launcher\.sh' "$cur" 2>/dev/null; then
        install_seen=1
        /usr/bin/printf '%s\tINSTALL_START\tinstaller process detected\n' "$(elapsed_ms)" >> "$TIMELINE"
      elif [ "$(app_mtime)" != "$base_mtime" ]; then
        install_seen=1
        bundle_changed=1
        /usr/bin/printf '%s\tINSTALL_START\tapplication bundle changed\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi
    fi

    if [ "$install_seen" -eq 1 ]; then
      current_mtime="$(app_mtime)"
      if [ "$bundle_changed" -eq 0 ] && [ "$current_mtime" != "$base_mtime" ]; then
        bundle_changed=1
        /usr/bin/printf '%s\tAPP_UPDATED\tapplication bundle changed\n' "$(elapsed_ms)" >> "$TIMELINE"
      fi

      if [ "$bundle_changed" -eq 1 ] && [ "$first_launch_seen" -eq 0 ] && app_running; then
        first_launch_seen=1
        /usr/bin/printf '%s\tFIRST_LAUNCH\tnew AUTO Xray menu process detected\n' "$(elapsed_ms)" >> "$TIMELINE"
        /usr/bin/touch "$FIRST_LAUNCH_SEEN"
      fi

      if [ "$first_launch_seen" -eq 1 ] && [ "$ready_seen" -eq 0 ] && app_running; then
        state="$(menu_state_raw || true)"
        if [ -n "$state" ] && menu_state_is_off "$state" && listeners_clear && auto_proxy_disabled; then
          ready_seen=1
          /usr/bin/printf '%s\tAPP_READY_OFF\tmenu app running; state OFF; AUTO Xray proxy disabled; listeners clear\n' "$(elapsed_ms)" >> "$TIMELINE"
          /usr/bin/touch "$READY_OFF_SEEN"
        fi
      fi
    fi

    /bin/sleep 0.25
  done

  /bin/rm -f "$prev" "$cur" "$added" "$removed" >/dev/null 2>&1 || true
}

stop_monitor() {
  /usr/bin/touch "$STOP_FILE" >/dev/null 2>&1 || true
  if [ -n "$MONITOR_PID" ]; then
    wait "$MONITOR_PID" >/dev/null 2>&1 || true
    MONITOR_PID=""
  fi
}

write_summary() {
  {
    /usr/bin/printf 'elapsed_ms\tevent\tdetail\n'
    /bin/cat "$TIMELINE"
  } > "$SUMMARY"
}

make_archive() {
  write_summary
  (cd "$HOME/Desktop" && /usr/bin/zip -qry "$ARCHIVE" "$(/usr/bin/basename "$OUT_DIR")") >/dev/null 2>&1 || true
}

finish() {
  stop_monitor
  /bin/rm -f "$STOP_FILE" "$READY_OFF_SEEN" "$FIRST_LAUNCH_SEEN" >/dev/null 2>&1 || true
}

trap finish EXIT
trap 'exit 130' INT TERM

START_MS="$(monotonic_ms)"
START_EPOCH="$(/bin/date '+%s')"

{
  echo "AUTO Xray install + first-launch OFF + runtime timing test"
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

log "AUTO Xray — единый тест установки и работы"
log ""
log "1) Тест уже запущен и ждёт установщик."
log "2) После установки он дождётся первого запуска AUTO Xray в состоянии OFF."
log "3) OFF подтверждается по menu-state, отсутствию listeners 2081/9001 и выключенным системным proxy AUTO Xray."
log "4) Только после этого Terminal предложит запустить автоматические тесты работы приложения."
log ""
log "Теперь запустите установщик AUTO Xray обычным способом и оставьте это окно Terminal открытым."
log "Подойдут DMG → Install AUTO Xray.app или ZIP → INSTALL_AUTO_XRAY_CATALINA.command."
log ""

record_event "MONITOR_READY" "waiting for installer"
monitor_loop &
MONITOR_PID=$!

total_ticks=0
off_ticks=0
while [ ! -f "$READY_OFF_SEEN" ] && [ "$total_ticks" -lt 2400 ]; do
  /bin/sleep 0.25
  total_ticks=$((total_ticks + 1))
  if [ -f "$FIRST_LAUNCH_SEEN" ]; then
    off_ticks=$((off_ticks + 1))
    [ "$off_ticks" -lt 240 ] || break
  fi
done

if [ ! -f "$READY_OFF_SEEN" ]; then
  if [ -f "$FIRST_LAUNCH_SEEN" ]; then
    record_event "TIMEOUT" "AUTO Xray launched but did not reach confirmed ready-OFF state within 60 seconds"
    log ""
    log "Приложение запустилось, но за 60 секунд не подтвердило готовое состояние OFF."
  else
    record_event "TIMEOUT" "first AUTO Xray launch was not observed within 10 minutes"
    log ""
    log "Не удалось дождаться первого запуска за 10 минут."
  fi
  stop_monitor
  {
    echo "Observed version: $(app_version)"
    echo "App exists: $([ -d "$APP_DIR" ] && echo yes || echo no)"
    echo "App running: $(app_running && echo yes || echo no)"
    echo "Current menu-state:"
    menu_state_raw || true
    echo
    echo "Listeners clear: $(listeners_clear && echo yes || echo no)"
    echo "AUTO Xray proxy disabled: $(auto_proxy_disabled && echo yes || echo no)"
    echo
    capture_proxy_state "Proxy state at timeout"
  } > "$FIRST_STATE"
  make_archive
  log "Диагностический архив сохранён: $ARCHIVE"
  exit 2
fi

record_event "READY_OFF_CONFIRMED" "new app is running with translucent-icon equivalent OFF state"
stop_monitor

MENU_TMP="$OUT_DIR/menu-state-ready-off.txt"
MENU_META="$OUT_DIR/menu-state-ready-off-timing.txt"
start="$(monotonic_ms)"
menu_state_raw > "$MENU_TMP" 2>&1
MENU_RC=$?
end="$(monotonic_ms)"
MENU_MS=$((end - start))
/usr/bin/printf 'menu-state-ms\t%s\nrc\t%s\n' "$MENU_MS" "$MENU_RC" > "$MENU_META"
record_event "MENU_STATE" "ready-OFF response ${MENU_MS} ms rc=${MENU_RC}"

{
  echo "Observed version: $(app_version)"
  echo "App exists: $([ -d "$APP_DIR" ] && echo yes || echo no)"
  echo "App running: $(app_running && echo yes || echo no)"
  echo "Helper exists: $([ -f "$HELPER" ] && echo yes || echo no)"
  echo "Xray executable: $([ -x "$RES/xray" ] && echo yes || echo no)"
  echo "Ready-OFF menu-state: ${MENU_MS} ms rc=${MENU_RC}"
  echo "Menu-state payload:"
  /bin/cat "$MENU_TMP" 2>/dev/null || true
  echo
  echo "Listeners clear: $(listeners_clear && echo yes || echo no)"
  echo "AUTO Xray proxy disabled: $(auto_proxy_disabled && echo yes || echo no)"
  echo
  capture_proxy_state "Proxy state after first launch, before runtime tests"
} > "$FIRST_STATE"

log ""
log "Установка и первый запуск завершены."
log "Версия приложения: $(app_version)"
log "AUTO Xray работает в строке меню, но остаётся OFF; это состояние полупрозрачной иконки."
log "Первый menu-state в готовом OFF-состоянии: ${MENU_MS} ms (rc=${MENU_RC})"
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
    record_event "RUNTIME_TEST_START" "starting runtime self-test from confirmed OFF state"
    RUNTIME_START_EPOCH="$(/bin/date '+%s')"
    /bin/bash "$RUNNER"
    RUNTIME_RC=$?
    record_event "RUNTIME_TEST_END" "runtime self-test rc=${RUNTIME_RC}"

    LATEST_RUNTIME_ZIP="$(/bin/ls -t "$HOME/Desktop"/AUTO_Xray_Test_*.zip 2>/dev/null | /usr/bin/head -n 1 || true)"
    if [ -n "$LATEST_RUNTIME_ZIP" ]; then
      ZIP_MTIME="$(/usr/bin/stat -f '%m' "$LATEST_RUNTIME_ZIP" 2>/dev/null || echo 0)"
      if [ "$ZIP_MTIME" -ge "$RUNTIME_START_EPOCH" ]; then
        /bin/cp "$LATEST_RUNTIME_ZIP" "$OUT_DIR/runtime-selftest.zip" 2>/dev/null || true
        if [ -s "$OUT_DIR/runtime-selftest.zip" ]; then
          RUNTIME_ZIP="$LATEST_RUNTIME_ZIP"
          log "Runtime-отчёт добавлен внутрь общего архива."
        fi
      fi
    fi
  else
    record_event "RUNTIME_TEST_SKIPPED" "RUN_AUTO_XRAY_TESTS.command not found beside install monitor"
    log "RUN_AUTO_XRAY_TESTS.command рядом с монитором не найден."
  fi
else
  record_event "RUNTIME_TEST_SKIPPED" "user chose not to start runtime suite"
fi

record_event "SESSION_END" "creating combined archive"
make_archive

if [ -s "$ARCHIVE" ] && [ -n "$RUNTIME_ZIP" ] && [ -f "$RUNTIME_ZIP" ]; then
  /bin/rm -f "$RUNTIME_ZIP" >/dev/null 2>&1 || true
fi

log ""
log "Готово. Для отправки нужен один общий архив:"
log "$ARCHIVE"

exit 0
