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
TIMINGS_OUT="$OUT_DIR/timings.txt"
ARCHIVE="$OUT_DIR.zip"
PASS=0
WARN=0
FAIL=0
RUNTIME_START=0
ORIG_TYPE="auto"
ORIG_VALUE="RF"
AUTO_WORLD_OK=0
WORLD_MANUAL_OK=0
WORKING_AUTO_GROUP=""
TIMED_MS=0
TIMED_OUTPUT=""
FRESH_NODE_SNAPSHOT_READY=0

mkdir -p "$OUT_DIR"
: > "$REPORT"
: > "$TIMINGS_OUT"

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

monotonic_ms() {
  /usr/bin/ruby -e 'puts((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round)' 2>/dev/null
}

run_timed_helper() {
  local label="$1" tmp start end rc
  shift
  tmp="${TMPDIR:-/tmp}/auto-xray-selftest-timed-${UID:-0}-$$.txt"
  start="$(monotonic_ms)"
  run_helper "$@" >"$tmp" 2>&1
  rc=$?
  end="$(monotonic_ms)"
  TIMED_MS=$((end - start))
  TIMED_OUTPUT="$(/bin/cat "$tmp" 2>/dev/null || true)"
  /bin/rm -f "$tmp" >/dev/null 2>&1 || true
  /usr/bin/printf '%s\t%d\t%s\n' "$label" "$TIMED_MS" "$rc" >> "$TIMINGS_OUT"
  log "TIMING: $label = $TIMED_MS ms (rc=$rc)"
  return "$rc"
}

check_fast_stop() {
  local label="$1" ms="$2"
  if [ "$ms" -le 4000 ]; then
    mark_pass "$label: OFF за ${ms} ms."
  else
    mark_warn "$label: OFF занял ${ms} ms; целевой happy-path ≤ 4000 ms."
  fi
}

check_fast_start() {
  local label="$1" ms="$2"
  if [ "$ms" -le 8000 ]; then
    mark_pass "$label: ON за ${ms} ms."
  else
    mark_warn "$label: ON занял ${ms} ms; целевой happy-path ≤ 8000 ms (удалённый узел тоже может влиять)."
  fi
}

check_manual_switch_budget() {
  local label="$1" ms="$2"
  if [ "$ms" -gt 20000 ]; then
    mark_fail "$label: переключение заняло ${ms} ms; лимит неуспешного/ручного переключения 20 с превышен."
  elif [ "$ms" -gt 12000 ]; then
    mark_warn "$label: переключение заняло ${ms} ms; целевой бюджет ≤ 12000 ms."
  else
    log "Manual timing: $label = ${ms} ms."
  fi
}

record_menu_refresh_timing() {
  local label="$1"
  if run_timed_helper "${label}-menu-state" menu-state; then
    if [ "$TIMED_MS" -gt 3000 ]; then
      mark_warn "$label: обновление состояния меню заняло ${TIMED_MS} ms."
    else
      log "UI timing: $label menu-state = ${TIMED_MS} ms."
    fi
  else
    mark_warn "$label: menu-state завершился ошибкой за ${TIMED_MS} ms."
  fi
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
  local start
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

fresh_group_exists() {
  [ "$FRESH_NODE_SNAPSHOT_READY" -eq 1 ] || return 1
  /usr/bin/awk -F'\t' -v group="$1" '$1 == group && $2 != "" { found=1; exit } END { exit(found ? 0 : 1) }' "$NODES_OUT"
}

fresh_node_exists() {
  local group="$1" node_id="$2"
  [ "$FRESH_NODE_SNAPSHOT_READY" -eq 1 ] || return 1
  /usr/bin/awk -F'\t' -v group="$group" -v id="$node_id" \
    '$1 == group && $2 == id { found=1; exit } END { exit(found ? 0 : 1) }' "$NODES_OUT"
}

fresh_node_name() {
  local group="$1" node_id="$2"
  /usr/bin/awk -F'\t' -v group="$group" -v id="$node_id" \
    '$1 == group && $2 == id { print $3; exit }' "$NODES_OUT"
}

fresh_group_nodes() {
  local group="$1"
  /usr/bin/awk -F'\t' -v group="$group" '$1 == group && $2 != "" { print $2 }' "$NODES_OUT"
}

fresh_group_count() {
  local group="$1"
  /usr/bin/awk -F'\t' -v group="$group" '$1 == group && $2 != "" { n++ } END { print n + 0 }' "$NODES_OUT"
}

preferred_fresh_group() {
  if fresh_group_exists RF; then
    echo RF
  elif fresh_group_exists EU; then
    echo EU
  elif fresh_group_exists WORLD; then
    echo WORLD
  else
    echo ""
  fi
}

refresh_node_snapshot() {
  local expected_count="$1" tmp snapshot_count duplicate_ids malformed
  tmp="${TMPDIR:-/tmp}/auto-xray-fresh-nodes-${UID:-0}-$$.txt"
  if ! run_helper menu-nodes > "$tmp" 2>>"$REPORT"; then
    /bin/rm -f "$tmp" >/dev/null 2>&1 || true
    mark_fail "Не удалось получить список узлов сразу после обновления подписки."
    return 1
  fi

  snapshot_count="$(/usr/bin/awk -F'\t' 'NF >= 4 && $1 ~ /^(RF|EU|WORLD)$/ && $2 != "" { n++ } END { print n + 0 }' "$tmp")"
  malformed="$(/usr/bin/awk -F'\t' 'NF < 4 || $1 !~ /^(RF|EU|WORLD)$/ || $2 == "" { print NR ":" $0 }' "$tmp")"
  duplicate_ids="$(/usr/bin/awk -F'\t' 'NF >= 2 && $2 != "" { print $2 }' "$tmp" | /usr/bin/sort | /usr/bin/uniq -d)"

  if [ -n "$malformed" ]; then
    log "Некорректные строки свежего menu-nodes:"
    /usr/bin/printf '%s\n' "$malformed" >> "$REPORT"
    /bin/rm -f "$tmp" >/dev/null 2>&1 || true
    mark_fail "Свежий список узлов содержит некорректные строки."
    return 1
  fi
  if [ -n "$duplicate_ids" ]; then
    log "Повторяющиеся id в свежем menu-nodes:"
    /usr/bin/printf '%s\n' "$duplicate_ids" >> "$REPORT"
    /bin/rm -f "$tmp" >/dev/null 2>&1 || true
    mark_fail "Свежий список узлов содержит повторяющиеся id."
    return 1
  fi
  if ! [ "$expected_count" -eq "$snapshot_count" ] 2>/dev/null; then
    /bin/rm -f "$tmp" >/dev/null 2>&1 || true
    mark_fail "menu-state сообщает $expected_count узлов, а свежий menu-nodes после update содержит $snapshot_count."
    return 1
  fi
  if [ "$snapshot_count" -le 0 ]; then
    /bin/rm -f "$tmp" >/dev/null 2>&1 || true
    mark_fail "Свежий список узлов после update пуст."
    return 1
  fi

  /bin/mv "$tmp" "$NODES_OUT"
  FRESH_NODE_SNAPSHOT_READY=1
  mark_pass "Зафиксирован свежий snapshot подписки: $snapshot_count узлов; RF=$(fresh_group_count RF), EU=$(fresh_group_count EU), WORLD=$(fresh_group_count WORLD)."
  return 0
}

restore_original_mode() {
  local fallback
  run_helper stop >/dev/null 2>&1 || true
  if [ "$ORIG_TYPE" = "manual" ] && [ -n "$ORIG_VALUE" ]; then
    if fresh_node_exists RF "$ORIG_VALUE" || fresh_node_exists EU "$ORIG_VALUE" || fresh_node_exists WORLD "$ORIG_VALUE"; then
      run_helper mode manual "$ORIG_VALUE" >/dev/null 2>&1 || true
    else
      fallback="$(preferred_fresh_group)"
      [ -n "$fallback" ] && run_helper mode auto "$fallback" >/dev/null 2>&1 || true
    fi
  elif [ -n "$ORIG_VALUE" ] && fresh_group_exists "$ORIG_VALUE"; then
    run_helper mode auto "$ORIG_VALUE" >/dev/null 2>&1 || true
  else
    fallback="$(preferred_fresh_group)"
    [ -n "$fallback" ] && run_helper mode auto "$fallback" >/dev/null 2>&1 || true
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
  log "AUTO Xray оставлен в состоянии OFF; исходный выбранный режим восстановлен только если он существует в свежей подписке."
  log "Свежий snapshot узлов: $NODES_OUT"
  log "Логи: $OUT_DIR"
  log "Тайминги: $TIMINGS_OUT"

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
ORIG_TYPE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","type")')"
if [ "$ORIG_TYPE" = "manual" ]; then
  ORIG_VALUE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","node")')"
else
  ORIG_TYPE="auto"
  ORIG_VALUE="$(/usr/bin/printf '%s' "$STATE" | json_field 'j.dig("mode","group")')"
  [ -n "$ORIG_VALUE" ] || ORIG_VALUE="RF"
fi

if [ "$HAS_URL" != "true" ]; then
  mark_fail "Подписка не настроена: авто-тест не может начать с обязательного обновления подписки."
  exit 1
fi

log ""
log "=== 1. Refresh subscription ==="
log "Перед проверкой узлов принудительно обновляю сохранённую подписку."
if run_timed_helper "subscription-update" update; then
  /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
  mark_pass "Подписка обновлена перед остальными авто-тестами за ${TIMED_MS} ms."
else
  /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
  mark_fail "Обновление подписки завершилось ошибкой за ${TIMED_MS} ms; тесты на устаревшем списке узлов не запускаются."
  exit 1
fi

STATE="$(menu_state)"
if [ $? -ne 0 ] || [ -z "$STATE" ]; then
  mark_fail "После обновления подписки menu-state не отвечает."
  exit 1
fi
NODE_COUNT="$(/usr/bin/printf '%s' "$STATE" | json_field 'j["nodes"]')"
if ! [ "$NODE_COUNT" -gt 0 ] 2>/dev/null; then
  mark_fail "После обновления подписки нет узлов для теста."
  exit 1
fi
if ! refresh_node_snapshot "$NODE_COUNT"; then
  exit 1
fi

log ""
log "Свежие WORLD-узлы после update:"
if fresh_group_exists WORLD; then
  /usr/bin/awk -F'\t' '$1 == "WORLD" { printf "  %s\t%s\t%s\n", $2, $3, $4 }' "$NODES_OUT" | /usr/bin/tee -a "$REPORT"
else
  log "  отсутствуют"
fi

log ""
log "=== 2. Baseline OFF ==="
if run_timed_helper "baseline-stop" stop; then
  /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
  mark_pass "AUTO Xray остановлен перед тестом."
  check_fast_stop "Baseline" "$TIMED_MS"
  record_menu_refresh_timing "baseline-off"
else
  /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
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
  if ! fresh_group_exists "$group"; then
    mark_warn "Группа $group отсутствует в свежей подписке после update; пропуск."
    return 0
  fi

  log ""
  log "=== AUTO $group ==="
  if run_timed_helper "mode-auto-$group" mode auto "$group"; then
    output="$TIMED_OUTPUT"
    if [ "$TIMED_MS" -gt 10000 ]; then
      mark_warn "AUTO $group: переключение заняло ${TIMED_MS} ms; целевой happy-path ≤ 10000 ms."
    else
      mark_pass "AUTO $group: переключение за ${TIMED_MS} ms."
    fi
  else
    output="$TIMED_OUTPUT"
    mark_warn "Переключение на AUTO $group не удалось за ${TIMED_MS} ms: $output"
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
    [ -n "$WORKING_AUTO_GROUP" ] || WORKING_AUTO_GROUP="$group"
    [ "$group" = "RF" ] && WORKING_AUTO_GROUP="RF"
    [ "$group" = "WORLD" ] && AUTO_WORLD_OK=1
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
log "=== 3. Start on fresh baseline group ==="
FIRST_GROUP="$(preferred_fresh_group)"
if [ -z "$FIRST_GROUP" ]; then
  mark_fail "В свежей подписке нет ни одной тестируемой группы."
  exit 1
fi
run_helper mode auto "$FIRST_GROUP" >> "$REPORT" 2>&1 || true

if run_timed_helper "base-start" start; then
  START_OUT="$TIMED_OUTPUT"
  mark_pass "AUTO Xray включился на свежей группе $FIRST_GROUP: $START_OUT"
  check_fast_start "Базовый старт" "$TIMED_MS"
  record_menu_refresh_timing "base-on"
else
  START_OUT="$TIMED_OUTPUT"
  mark_warn "AUTO Xray не смог стартовать на свежей группе $FIRST_GROUP за ${TIMED_MS} ms: $START_OUT"
fi

try_auto_group RF || true
try_auto_group EU || true
try_auto_group WORLD || true

prepare_manual_baseline() {
  local node_id="$1" group state socks
  group="$WORKING_AUTO_GROUP"
  if [ -z "$group" ] || ! fresh_group_exists "$group"; then
    group="$(preferred_fresh_group)"
  fi
  if [ -z "$group" ]; then
    mark_warn "Manual baseline $node_id: нет свежей AUTO-группы для baseline."
    return 1
  fi

  run_helper stop >> "$REPORT" 2>&1 || true
  if ! run_helper mode auto "$group" >> "$REPORT" 2>&1; then
    mark_warn "Manual baseline $node_id: не удалось выбрать свежую AUTO $group."
    return 1
  fi
  if ! run_timed_helper "manual-baseline-$node_id" start; then
    /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
    mark_warn "Manual baseline $node_id: AUTO $group не запустился за ${TIMED_MS} ms."
    return 1
  fi
  state="$(menu_state)"
  if ! /usr/bin/printf '%s' "$state" | /usr/bin/grep -q '"on":true'; then
    mark_warn "Manual baseline $node_id: AUTO $group не подтверждает ON."
    return 1
  fi
  socks="$(probe_socks)"
  if ! probe_ok "$socks"; then
    mark_warn "Manual baseline $node_id: AUTO $group не прошёл SOCKS probe ($socks)."
    return 1
  fi
  return 0
}

log ""
log "=== 4. Manual WORLD nodes from fresh subscription snapshot ==="
WORLD_IDS="$(fresh_group_nodes WORLD)"
if [ -z "$WORLD_IDS" ]; then
  mark_warn "В свежей подписке после update нет ручных WORLD-узлов; секция пропущена."
else
  for node_id in $WORLD_IDS; do
    if ! fresh_node_exists WORLD "$node_id"; then
      mark_fail "WORLD id $node_id отсутствует в свежем snapshot; тест этого id запрещён."
      continue
    fi
    node_name="$(fresh_node_name WORLD "$node_id")"
    log "-- fresh manual WORLD: $node_id $node_name"

    if ! prepare_manual_baseline "$node_id"; then
      mark_warn "Manual $node_name: тест узла пропущен, потому что не удалось восстановить известный рабочий AUTO baseline."
      continue
    fi

    if run_timed_helper "mode-manual-$node_id" mode manual "$node_id"; then
      OUT="$TIMED_OUTPUT"
      check_manual_switch_budget "Manual $node_name" "$TIMED_MS"
      STATE="$(menu_state)"
      if ! /usr/bin/printf '%s' "$STATE" | /usr/bin/grep -q '"on":true'; then
        mark_warn "Manual $node_name: команда вернула успех, но состояние не ON; probe не выполняю."
        continue
      fi
      SOCKS_OUT="$(probe_socks)"
      if probe_ok "$SOCKS_OUT"; then
        WORLD_MANUAL_OK=$((WORLD_MANUAL_OK + 1))
        mark_pass "Manual $node_name: SOCKS probe OK ($SOCKS_OUT)."
      else
        mark_warn "Manual $node_name: SOCKS probe failed ($SOCKS_OUT)."
      fi
    else
      OUT="$TIMED_OUTPUT"
      check_manual_switch_budget "Manual $node_name failure" "$TIMED_MS"
      mark_warn "Manual $node_name не переключился за ${TIMED_MS} ms: $OUT"
      STATE="$(menu_state)"
      if /usr/bin/printf '%s' "$STATE" | /usr/bin/grep -q '"on":true'; then
        log "Manual $node_name: после ошибки rollback оставил приложение ON."
      else
        mark_warn "Manual $node_name: после ошибки rollback не оставил приложение ON; следующий узел начнётся с нового baseline."
      fi
    fi
  done
fi

if [ "$WORLD_MANUAL_OK" -gt 0 ] && [ "$AUTO_WORLD_OK" -ne 1 ]; then
  mark_fail "AUTO WORLD не работает, хотя хотя бы один свежий ручной WORLD-узел прошёл probe. Это ошибка AUTO-переключения, а не только удалённого узла."
elif [ "$WORLD_MANUAL_OK" -gt 0 ] && [ "$AUTO_WORLD_OK" -eq 1 ]; then
  mark_pass "AUTO WORLD использовал рабочий узел из свежей подписки при наличии доступного WORLD-кандидата."
fi

log ""
log "=== 5. Watchdog / mode-switch concurrency ==="
if fresh_group_exists RF && fresh_group_exists EU; then
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
  mark_warn "Для concurrency-теста нужны одновременно свежие RF и EU; тест пропущен."
fi

log ""
log "=== 6. Repeated ON/OFF ==="
if [ -n "$WORKING_AUTO_GROUP" ] && fresh_group_exists "$WORKING_AUTO_GROUP"; then
  run_helper stop >> "$REPORT" 2>&1 || true
  run_helper mode auto "$WORKING_AUTO_GROUP" >> "$REPORT" 2>&1 || true
else
  WORKING_AUTO_GROUP="$(preferred_fresh_group)"
  run_helper stop >> "$REPORT" 2>&1 || true
  [ -n "$WORKING_AUTO_GROUP" ] && run_helper mode auto "$WORKING_AUTO_GROUP" >> "$REPORT" 2>&1 || true
fi

i=1
while [ "$i" -le 3 ]; do
  if run_timed_helper "cycle-$i-stop" stop; then
    /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
    check_fast_stop "Cycle $i" "$TIMED_MS"
    if [ -n "$(listener_pids 2081)" ] || [ -n "$(listener_pids 9001)" ]; then
      mark_fail "Cycle $i: после OFF остался listener."
    else
      mark_pass "Cycle $i: OFF освободил localhost-порты."
    fi
  else
    /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
    mark_fail "Cycle $i: stop завершился ошибкой."
  fi

  if run_timed_helper "cycle-$i-start" start; then
    /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
    check_fast_start "Cycle $i" "$TIMED_MS"
    SOCKS_OUT="$(probe_socks)"
    if probe_ok "$SOCKS_OUT"; then
      mark_pass "Cycle $i: ON + SOCKS probe OK."
    else
      mark_warn "Cycle $i: ON, но SOCKS probe failed ($SOCKS_OUT)."
    fi
  else
    /usr/bin/printf '%s\n' "$TIMED_OUTPUT" >> "$REPORT"
    mark_warn "Cycle $i: start завершился ошибкой за ${TIMED_MS} ms."
  fi
  i=$((i + 1))
done

exit 0
