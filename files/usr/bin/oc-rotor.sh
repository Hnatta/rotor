#!/bin/sh
# oc-rotor.sh — Yacd-like ping dump + rotor (fixed Authorization quoting & clean output)
set -eu

# ====== ENV ======
CTRL="${CTRL:-http://127.0.0.1:9090}"
SECRET="${SECRET:-}"                                   # isi jika Clash pakai secret
GROUPS="${GROUPS:-SGR_ACTIVE IDN_ACTIVE WRD_ACTIVE}"   # untuk rotor

PING_URL="${PING_URL:-http://www.gstatic.com/generate_204}"  # plain URL

TIMEOUT_MS="${TIMEOUT_MS:-3000}"
STEP_SEC="${STEP_SEC:-1}"
RECHECK_SEC="${RECHECK_SEC:-30}"
FAIL_FAST_RETRIES="${FAIL_FAST_RETRIES:-3}"
FAIL_FAST_BACKOFF_SEC="${FAIL_FAST_BACKOFF_SEC:-1}"

MODEM_CMD="${MODEM_CMD:-/usr/bin/modem ip}"
MODEM_COOLDOWN_SEC="${MODEM_COOLDOWN_SEC:-10}"

# ====== Dump settings ======
DUMP_ON_START="${DUMP_ON_START:-0}"
DUMP_GROUP="${DUMP_GROUP:-}"
DUMP_PROXIES="${DUMP_PROXIES:-}"
DUMP_SORT="${DUMP_SORT:-1}"
DUMP_TIMEOUT_MS="${DUMP_TIMEOUT_MS:-5000}"

STATE_DIR="${STATE_DIR:-/tmp/oc-rotor}"
CYCLE_TOUCH_DIR="$STATE_DIR/.cycle"
IDX_FILE="$STATE_DIR/.idx"
LOG_TAG="${LOG_TAG:-oc-rotor}"

mkdir -p "$STATE_DIR" "$CYCLE_TOUCH_DIR"
[ -f "$IDX_FILE" ] || echo 0 > "$IDX_FILE"

log() {
  local ts; ts="$(date '+%F %T')"
  command -v logger >/dev/null 2>&1 && logger -t "$LOG_TAG" "$*"
  printf '%s %s\n' "$ts" "$*"
}

ok_file(){ echo "$STATE_DIR/$1.ok"; }
ts_now(){ date +%s; }
is_ok_cached(){
  local f; f="$(ok_file "$1")"
  [ -f "$f" ] || return 1
  [ "$RECHECK_SEC" -le 0 ] && return 0
  local now old; now="$(ts_now)"; old="$(cat "$f" 2>/dev/null || echo 0)"
  [ $((now - old)) -lt "$RECHECK_SEC" ] && return 0 || return 1
}
mark_ok(){ date +%s > "$(ok_file "$1")"; }
mark_fail(){ rm -f "$(ok_file "$1")" 2>/dev/null || true; }
touch_cycle(){ : > "$CYCLE_TOUCH_DIR/$1"; }
reset_cycle(){ rm -f "$CYCLE_TOUCH_DIR"/* 2>/dev/null || true; }
count_groups(){ set -- $GROUPS; echo $#; }
get_group_by_index(){
  local idx="$1" i=0
  for g in $GROUPS; do [ "$i" -eq "$idx" ] && { echo "$g"; return 0; }; i=$((i+1)); done
  set -- $GROUPS; echo "$1"
}
cycle_complete(){
  local need=0 have=0
  for g in $GROUPS; do need=$((need+1)); [ -e "$CYCLE_TOUCH_DIR/$g" ] && have=$((have+1)); done
  [ "$need" -gt 0 ] && [ "$have" -ge "$need" ]
}
any_ok_now(){
  for g in $GROUPS; do [ -f "$(ok_file "$g")" ] && return 0; done
  return 1
}

# ====== HTTP helpers (Authorization must be quoted) ======
curl_delay(){
  # arg1: nama proxy/grup yang bisa delay-test
  local name="$1" out maxs base
  base="$CTRL/proxies/$(printf '%s' "$name" | sed 's/ /%20/g')/delay"
  maxs=$(( (TIMEOUT_MS/1000) + 2 ))
  if [ -n "$SECRET" ]; then
    out="$(curl -sS --max-time "$maxs" -H "Authorization: Bearer $SECRET" -G \
          --data-urlencode "url=$PING_URL" \
          --data-urlencode "timeout=$TIMEOUT_MS" \
          "$base" 2>/dev/null || true)"
  else
    out="$(curl -sS --max-time "$maxs" -G \
          --data-urlencode "url=$PING_URL" \
          --data-urlencode "timeout=$TIMEOUT_MS" \
          "$base" 2>/dev/null || true)"
  fi
  printf '%s' "$out" | grep -q '"delay"'
}

has_jq(){ command -v jq >/dev/null 2>&1; }

dump_one(){
  # arg1=name, arg2=timeout_ms
  local name="$1" tmo="${2:-$DUMP_TIMEOUT_MS}" out maxs base delay
  base="$CTRL/proxies/$(printf '%s' "$name" | sed 's/ /%20/g')/delay"
  maxs=$(( (tmo/1000) + 2 ))
  if [ -n "$SECRET" ]; then
    out="$(curl -sS --max-time "$maxs" -H "Authorization: Bearer $SECRET" -G \
          --data-urlencode "url=$PING_URL" \
          --data-urlencode "timeout=$tmo" \
          "$base" 2>/dev/null || true)"
  else
    out="$(curl -sS --max-time "$maxs" -G \
          --data-urlencode "url=$PING_URL" \
          --data-urlencode "timeout=$tmo" \
          "$base" 2>/dev/null || true)"
  fi
  delay="$(printf '%s' "$out" | sed -n 's/.*"delay":\([0-9][0-9]*\).*/\1/p')"
  if [ -n "$delay" ]; then
    printf "%s,%s\n" "$delay" "$name"
  else
    printf "fail,%s\n" "$name"
  fi
}

yacd_dump(){
  local list="" tmp="/tmp/oc_dump.$$"
  : > "$tmp"
  # arg1 bisa nama grup (butuh jq) atau daftar yang dipisah koma
  if [ -n "${1:-}" ] && printf '%s' "$1" | grep -q ','; then
    DUMP_PROXIES="$(printf '%s' "$1" | tr ',' ' ')"
  elif [ -n "${1:-}" ] && [ -z "$DUMP_GROUP" ]; then
    DUMP_GROUP="$1"
  fi

  if [ -n "$DUMP_GROUP" ] && has_jq; then
    if [ -n "$SECRET" ]; then
      list="$(curl -sS -H "Authorization: Bearer $SECRET" "$CTRL/proxies/$DUMP_GROUP" | jq -r '.all[]' 2>/dev/null || true)"
    else
      list="$(curl -sS "$CTRL/proxies/$DUMP_GROUP" | jq -r '.all[]' 2>/dev/null || true)"
    fi
  fi
  [ -z "$list" ] && [ -n "$DUMP_PROXIES" ] && list="$DUMP_PROXIES"
  if [ -z "$list" ]; then
    echo "Tidak ada daftar proxy untuk dump. Set DUMP_GROUP (butuh jq) atau DUMP_PROXIES."
    return 1
  fi

  echo "== Dump ping (url=$PING_URL, timeout=${DUMP_TIMEOUT_MS}ms) =="
  for name in $list; do dump_one "$name" "$DUMP_TIMEOUT_MS" >> "$tmp"; done

  if [ "$DUMP_SORT" = "1" ]; then
    { grep -v '^fail,' "$tmp" | sort -n -t, -k1,1; grep '^fail,' "$tmp"; } | while IFS=, read -r d n; do
      if [ "$d" = "fail" ]; then printf "%-40s  %s\n" "$n" "fail"
      else printf "%-40s  %s ms\n" "$n" "$d"
      fi
    done
  else
    while IFS=, read -r d n; do
      [ "$d" = "fail" ] && printf "%-40s  %s\n" "$n" "fail" || printf "%-40s  %s ms\n" "$n" "$d"
    done < "$tmp"
  fi
  rm -f "$tmp"
}

# ---------- CLI: "dump" ----------
if [ "${1:-}" = "dump" ]; then
  shift || true
  yacd_dump "${1:-}" || true
  exit 0
fi

# ---------- Optional dump once ----------
[ "$DUMP_ON_START" = "1" ] && yacd_dump "" || true

# ---------- Rotor loop ----------
log "Start rotor: groups=[$GROUPS], step=${STEP_SEC}s, recheck=${RECHECK_SEC}s, timeout=${TIMEOUT_MS}ms"
reset_cycle
while :; do
  N="$(count_groups)"
  IDX="$(cat "$IDX_FILE" 2>/dev/null || echo 0)"
  [ "$IDX" -ge "$N" ] && IDX=0
  G="$(get_group_by_index "$IDX")"

  if is_ok_cached "$G"; then
    touch_cycle "$G"
    IDX=$((IDX+1)); echo "$IDX" > "$IDX_FILE"
    sleep "$STEP_SEC"
    if cycle_complete && any_ok_now; then :; elif cycle_complete; then
      log "ALERT: Semua grup gagal. Menjalankan: $MODEM_CMD"
      sh -c "$MODEM_CMD" || log "Gagal menjalankan MODEM_CMD: $MODEM_CMD"
      for x in $GROUPS; do mark_fail "$x"; done
      reset_cycle
      sleep "$MODEM_COOLDOWN_SEC"
    fi
    continue
  fi

  touch_cycle "$G"
  n=0
  while :; do
    if curl_delay "$G"; then
      mark_ok "$G"; log "OK: $G"; break
    else
      mark_fail "$G"; n=$((n+1)); log "FAIL: $G (retry $n/$FAIL_FAST_RETRIES)"
      [ "$n" -lt "$FAIL_FAST_RETRIES" ] && { sleep "$FAIL_FAST_BACKOFF_SEC"; continue; }
      break
    fi
  done

  if cycle_complete && any_ok_now; then :; elif cycle_complete; then
    log "ALERT: Semua grup gagal. Menjalankan: $MODEM_CMD"
    sh -c "$MODEM_CMD" || log "Gagal menjalankan MODEM_CMD: $MODEM_CMD"
    for x in $GROUPS; do mark_fail "$x"; done
    reset_cycle
    sleep "$MODEM_COOLDOWN_SEC"
  fi

  IDX=$((IDX+1)); echo "$IDX" > "$IDX_FILE"
  sleep "$STEP_SEC"
done
