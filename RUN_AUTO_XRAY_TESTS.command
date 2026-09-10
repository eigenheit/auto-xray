#!/bin/bash
set -u

APP_DIR="$HOME/Applications/AUTO Xray.app"
RES="$APP_DIR/Contents/Resources"
HELPER="$RES/auto-xray-helper.rb"
RUNTIME_LOG="$HOME/Library/Logs/AUTO Xray/runtime.log"
STAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
OUT_DIR="$HOME/Desktop/AUTO_Xray_Test_$STAMP"
REPORT="$OUT_DIR/self-test.log"
RUNTIME_OUT="$OUT_DIR/runtime-during-test.log"
STATUS_OUT="$OUT_DIR/final-status.txt"
NODES_OUT="$OUT_DIR/nodes.txt"
ARCHIVE="$OUT_DIR.zip"
PASS=0
WARN=0
FAIL=0
RUNTIME_START=0
ORIG_TYPE="auto"
ORIG_VALUE="RF"

mkdir -p "$OUT_DIR"
: > "$REPORT"

log() {
  /usr/bin/printf '%s\n' "$*" | /usr/bin/tee -a "$REPORT"
}

mark_pass() {
  PASS=$((PASS + 1))
  log "PASS: $*"
}

mark_warn() {
  WARN=$((WARN + 1))
  log "WARN: $*"
}

mark_fail() {
  FAIL=$((FAIL + 1))
  log "FAIL: $*"
}

run_helper() {
  /usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES="$RES" \
    /usr/bin/ruby -EUTF-8:UTF-8 "$HELPER" "$@"
}

menu_state() {
  run_helper menu-state 2>&1
}

json_field() {
  local expression="$1"
  /usr/bin/ruby -rjson -e "j=JSON.parse(STDIN.read); v=${expression}; puts(v.nil? ? '' : v)" 2>/dev/null
}

probe_direct() {
  /usr/bin/curl --silent --show-error --connect-timeout 5 --max-time 10 \
    -o /dev/null -w '%{http_code} %{time_total}' https://www.gstatic.com/generate_204 2>&1
}

probe_socks() {
  /usr/bin/curl --silent --show-error --connect-timeout 5 --max-time 12 \
    --socks5-hostname 127.0.0.1:2081 \
    -o /dev/null -w '%{http_code} %{time_total}' https://www.gstatic.com/generate_204 2>&1
}

probe_http() {
  /usr/bin/curl --silent --show-error --connect-timeout 5 --max-time 12 \
    --proxy http://127.0.0.1:9001 \
    -o /dev/null -w '%{http_code} %{time_total}' https://www.gstatic.com/generate_204 2>&1
}

probe_ok() {
  case "$1" in
    204\ *|200\ *) return 0 ;;
    *) return 1 ;;
  esac
}

listener_pids() {
  /usr/sbin/lsof -nP -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
}

runtime_line_count() {
  if [ -f "$RUNTIME_LOG" ]; then
    /usr/bin/wc -l < "$RUNTIME_LOG" | /usr/bin/tr -d ' '
  else
    echo 0
  fi
}

capture_runtime_delta() {
  local end start
  start=$((RUNTIME_START + 1))
  if [ -f "$RUNTIME_LOG" ]; then
    /usr/bin/sed -n "${start},\$p" "$RUNTIME_LOG" 2>/dev/null | \
      /usr/bin/sed -E \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
        > "$RUNTIME_OUT" || true
  else
    : > "$RUNTIME_OUT"
  fi
}

restore_original_mode() {
  run_helper stop >/dev/null 2>&1 || true
  if [ "$ORIG_TYPE" = "manual" ] && [ -n "$ORIG_VALUE" ]; then
    run_helper mode manual "$ORIG_VALUE" >/dev/null 2>&1 || true
  elif [ -n "$ORIG_VALUE" ]; then
    run_helper mode auto "$ORIG_VALUE" >/dev/null 2>&1 || true
  fi
}

finish() {
  restore_original_mode
  capture_runtime_delta
  menu_state > "$STATUS_OUT" 2>&1 || true

  if /usr/bin/grep -Eqi 'address already in use|failed to listen TCP on (2081|9001)|failed to listen on address.*(2081|9001)' "$RUNTIME_OUT"; then
    mark_fail "Обнаружена локальная коллизия портов 2081/9001 (runtime race)."
  else
    mark_pass "В тестовом фрагменте runtime.log нет признаков bind/address already in use."
  fi

  if /usr/bin/grep -Eqi 'lookup .*no such host|i/o timeout|connection refused|connection reset|context deadline exceeded' "$RUNTIME_OUT"; then
    mark_warn "В runtime.log есть сетевые/DNS ошибки удалённых узлов; они сохранены в отчёте для разбора."
  fi

  if [ -n "$(listener_pids 2081)" ] || [ -n "$(listener_pids 9001)" ]; then
    mark_fail "После остановки остался listener на 2081 или 9001."
  else
    mark_pass "После теста localhost-порты AUTO Xray освобождены."
  fi

  log ""
  log "SUMMARY: PASS=$PASS WARN=$WARN FAIL=$FAIL"
  log "AUTO Xray оставлен в состоянии OFF; исходный выбранный режим восстановлен."
  log "Логи: $OUT_DIR"

  log "Архив для отправки: $ARCHIVE"
  (cd "$HOME/Desktop" && /usr/bin/zip -qry "$ARCHIVE" "$(/usr/bin/basename "$OUT_DIR")") >/dev/null 2>&1 || true

  log ""
  log "Готово. Пришлите ChatGPT файл $(/usr/bin/basename "$ARCHIVE")."
}

trap finish EXIT
trap 'exit 130' INT TERM

RUNTIME_START="$(runtime_line_count)"

log "AUTO Xray Catalina runtime self-test"
log "Started: $(/bin/date)"
log "Machine: $(/usr/bin/uname -m)"
log "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"
log ""

if [ ! -d "$APP_DIR" ]; then
  mark_fail "Не найдено приложение: $APP_DIR"
  exit 1
fi
if [ ! -f "$HELPER" ]; then
  mark_fail "Не найден helper: $HELPER"
  exit 1
fi
if [ "$(/usr/bin/uname -m)" != "x86_64" ]; then
  mark_fail "Тест предназначен для Intel x86_64."
  exit 1
fi
case "$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)" in
  10.15*) mark_pass "macOS Catalina обнаружена." ;;
  *) mark_warn "Система не Catalina 10.15.x; результаты совместимости будут вспомогательными." ;;
esac

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo unknown)"
log "Installed version: $APP_VERSION"

STATE="$(menu_state)"
if [ $? -ne 0 ] || [ -z "$STATE" ]; then
  mark_fail "menu-state не отвечает."
  exit 1
fi

HAS_URL="$(/usr/bin/printf '%s' "$STATE" | json_field 'j["hasURL"]')"
NODE_COUNT="$(/usr/bin/printf '%s' "$STATE" | json_field 'j["nodes"]')"
ORIG_TYPE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","type")')"
if [ "$ORIG_TYPE" = "manual" ]; then
  ORIG_VALUE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","node")')"
else
  ORIG_TYPE="auto"
  ORIG_VALUE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","group")')"
  [ -n "$ORIG_VALUE" ] || ORIG_VALUE="RF"
fi

if [ "$HAS_URL" != "true" ]; then
  mark_fail "Подписка не настроена. Сначала обновите подписку в меню AUTO Xray."
  exit 1
fi
if ! [ "$NODE_COUNT" -gt 0 ] 2>/dev/null; then
  mark_fail "Нет узлов для теста. Сначала обновите подписку."
  exit 1
fi
mark_pass "Подписка и список узлов доступны ($NODE_COUNT узлов)."

run_helper menu-nodes > "$NODES_OUT" 2>&1 || true
log ""
log "=== 1. Baseline OFF ==="
if run_helper stop >> "$REPORT" 2>&1; then
  mark_pass "AUTO Xray остановлен перед тестом."
else
  mark_warn "Команда stop вернула ошибку; продолжаю диагностику."
fi
DIRECT="$(probe_direct)"
if probe_ok "$DIRECT"; then
  mark_pass "Прямой интернет в OFF работает: $DIRECT"
else
  mark_warn "Прямой probe в OFF не прошёл: $DIRECT"
fi

try_auto_group() {
  local group="$1" output socks http
  if ! /usr/bin/grep -q "^${group}[[:space:]]" "$NODES_OUT" 2>/dev/null; then
    mark_warn "Группа $group отсутствует в подписке; пропуск."
    return 0
  fi

  log ""
  log "=== AUTO $group ==="
  output="$(run_helper mode auto "$group" 2>&1)"
  if [ $? -ne 0 ]; then
    mark_warn "Переключение на AUTO $group не удалось: $output"
    return 1
  fi

  STATE="$(menu_state)"
  if /usr/bin/printf '%s' "$STATE" | /usr/bin/grep -q '"on":true'; then
    mark_pass "AUTO $group: приложение осталось ON после переключения."
  else
    mark_warn "AUTO $group: после переключения состояние не ON."
    return 1
  fi

  socks="$(probe_socks)"
  http="$(probe_http)"
  if probe_ok "$socks"; then
    mark_pass "AUTO $group: SOCKS probe OK ($socks)."
  else
    mark_warn "AUTO $group: SOCKS probe failed ($socks)."
  fi
  if probe_ok "$http"; then
    mark_pass "AUTO $group: HTTP proxy probe OK ($http)."
  else
    mark_warn "AUTO $group: HTTP proxy probe failed ($http)."
  fi
}

log ""
log "=== 2. Start on RF ==="
if /usr/bin/grep -q '^RF[[:space:]]' "$NODES_OUT" 2>/dev/null; then
  run_helper mode auto RF >> "$REPORT" 2>&1 || true
elif /usr/bin/grep -q '^EU[[:space:]]' "$NODES_OUT" 2>/dev/null; then
  run_helper mode auto EU >> "$REPORT" 2>&1 || true
else
  FIRST_GROUP="$(/usr/bin/head -n 1 "$NODES_OUT" | /usr/bin/awk -F'\t' '{print $1}')"
  [ -n "$FIRST_GROUP" ] && run_helper mode auto "$FIRST_GROUP" >> "$REPORT" 2>&1 || true
fi

START_OUT="$(run_helper start 2>&1)"
if [ $? -eq 0 ]; then
  mark_pass "AUTO Xray включился: $START_OUT"
else
  mark_warn "AUTO Xray не смог стартовать на базовой группе: $START_OUT"
fi

try_auto_group RF || true
try_auto_group EU || true
try_auto_group WORLD || true

log ""
log "=== 3. Manual WORLD nodes ==="
WORLD_IDS="$(/usr/bin/awk -F'\t' '$1 == "WORLD" {print $2}' "$NODES_OUT" 2>/dev/null)"
if [ -z "$WORLD_IDS" ]; then
  mark_warn "Ручные WORLD-узлы отсутствуют."
else
  for node_id in $WORLD_IDS; do
    node_name="$(/usr/bin/awk -F'\t' -v id="$node_id" '$2 == id {print $3; exit}' "$NODES_OUT")"
    log "-- manual $node_id $node_name"
    OUT="$(run_helper mode manual "$node_id" 2>&1)"
    if [ $? -ne 0 ]; then
      mark_warn "Manual $node_name не переключился: $OUT"
      continue
    fi
    SOCKS_OUT="$(probe_socks)"
    if probe_ok "$SOCKS_OUT"; then
      mark_pass "Manual $node_name: SOCKS probe OK ($SOCKS_OUT)."
    else
      mark_warn "Manual $node_name: SOCKS probe failed ($SOCKS_OUT)."
    fi
  done
fi

log ""
log "=== 4. Watchdog / mode-switch concurrency ==="
if /usr/bin/grep -q '^RF[[:space:]]' "$NODES_OUT" 2>/dev/null && /usr/bin/grep -q '^EU[[:space:]]' "$NODES_OUT" 2>/dev/null; then
  run_helper mode auto RF >> "$REPORT" 2>&1 || true
  (
    i=0
    while [ "$i" -lt 12 ]; do
      /usr/bin/printf '[watchdog %02d] ' "$i" >> "$REPORT"
      run_helper ensure-proxy >> "$REPORT" 2>&1 || true
      i=$((i + 1))
      /bin/sleep 1
    done
  ) &
  WATCH_PID=$!

  i=0
  while [ "$i" -lt 3 ]; do
    run_helper mode auto EU >> "$REPORT" 2>&1 || mark_warn "Concurrency: EU switch failed on cycle $((i + 1))."
    run_helper mode auto RF >> "$REPORT" 2>&1 || mark_warn "Concurrency: RF switch failed on cycle $((i + 1))."
    i=$((i + 1))
  done
  wait "$WATCH_PID" 2>/dev/null || true

  if /usr/bin/grep -q 'BUSY' "$REPORT"; then
    mark_pass "Watchdog корректно уступал runtime lock (BUSY наблюдался)."
  else
    mark_warn "BUSY не наблюдался; гонка могла не воспроизвестись в этом запуске."
  fi
else
  mark_warn "Для concurrency-теста нужны одновременно RF и EU; тест пропущен."
fi

log ""
log "=== 5. Repeated ON/OFF ==="
i=1
while [ "$i" -le 3 ]; do
  if run_helper stop >> "$REPORT" 2>&1; then
    if [ -n "$(listener_pids 2081)" ] || [ -n "$(listener_pids 9001)" ]; then
      mark_fail "Cycle $i: после OFF остался listener."
    else
      mark_pass "Cycle $i: OFF освободил localhost-порты."
    fi
  else
    mark_fail "Cycle $i: stop завершился ошибкой."
  fi

  if run_helper start >> "$REPORT" 2>&1; then
    SOCKS_OUT="$(probe_socks)"
    if probe_ok "$SOCKS_OUT"; then
      mark_pass "Cycle $i: ON + SOCKS probe OK."
    else
      mark_warn "Cycle $i: ON, но SOCKS probe failed ($SOCKS_OUT)."
    fi
  else
    mark_warn "Cycle $i: start завершился ошибкой."
  fi
  i=$((i + 1))
done

exit 0
