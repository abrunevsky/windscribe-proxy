#!/bin/bash
# SwiftBar plugin: VPN Proxy controller with caching & functions
# Reads COMPOSE_DIR from ~/.config/swiftbar-vpn/config
# Refresh interval: every 30s (file name ends with *.30s.sh)
# shellcheck disable=SC2155,SC2086,SC2046

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin"

# ========= CONFIG & GLOBALS =========
CONFIG_FILE="$HOME/.config/swiftbar-vpn/config"

# Defaults (will be set after resolve_config)
COMPOSE_DIR=""
COMPOSE_FILE=""
CACHE_DIR="$HOME/.cache/swiftbar-vpn"
STATE_FILE="$CACHE_DIR/state.txt"
IP_CACHE_FILE="$CACHE_DIR/ip_cache.txt"
FORCE_FILE="$CACHE_DIR/force_refresh"
TTL_SECONDS=1800        # IP cache TTL: 30 minutes
SOCKS_ADDR="127.0.0.1:8888"
W_SERVICE="windscribe-vpn"
S_SERVICE="socks5-via-vpn"

# ========= MAIN =========
main() {
  # Load COMPOSE_DIR from config and validate it
  if ! resolve_config; then
    # Show a friendly warning in SwiftBar and exit
    echo "⚠️ Configure VPN plugin"
    echo "---"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "Config file not found:"
      echo "$CONFIG_FILE"
      echo "---"
      echo "Open config folder | shell=/usr/bin/open param1=\"$HOME/.config\" terminal=false"
      echo "Show example | shell=/usr/bin/osascript param1=-e param2='display dialog \"Create file: $CONFIG_FILE\\n\\nContent:\\nCOMPOSE_DIR=\\\"/absolute/path/to/project-root\\\"\" buttons {\"OK\"} default button 1 with title \"SwiftBar VPN\"' terminal=false"
    else
      echo "Invalid COMPOSE_DIR in:"
      echo "$CONFIG_FILE"
      echo "---"
      echo "Current value: ${COMPOSE_DIR:-<empty>}"
      echo "Expected file: ${COMPOSE_DIR:-<empty>}/docker-compose.yml"
      echo "---"
      echo "Open config… | shell=/usr/bin/open param1=-e param2=\"$CONFIG_FILE\" terminal=false"
    fi
    exit 0
  fi

  # Pull environment from .env (needed for proxy auth)
  if [ -f "$COMPOSE_DIR/.env" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' "$COMPOSE_DIR/.env" | xargs)
  fi

  ensure_cache_dir

  local state count yellow
  state="$(get_current_state)"      # active|stopped|degraded
  yellow="$(has_yellow)"            # 1|0
  count="$(get_running_count)"      # number of active-ish containers

  # IP cache: refresh when forced OR state changes OR TTL expires
  read_cached_ips
  if [ -f "$FORCE_FILE" ] || needs_refresh_ip "$state" || cache_expired "$IP_CACHE_FILE" "$TTL_SECONDS"; then
    refresh_ips "$state"
    rm -f "$FORCE_FILE" 2>/dev/null || true
  fi

  # ===== Top line =====
  if [ "$state" = "active" ]; then
    [ "$yellow" = "1" ] && echo "🟡 Proxy VPN" || echo "🟢 ${proxy_ip:-–}"
  else
    echo "🔴 Proxy VPN"
  fi

  echo "---"

  # ===== Controls =====
  # Restart = down + up (consistent clean restart)
  restart_line="shell=/bin/bash param1=-lc param2='cd \"$COMPOSE_DIR\" && docker compose -f \"$COMPOSE_FILE\" down && docker compose -f \"$COMPOSE_FILE\" up -d' terminal=false refresh=true"

  if [ "$state" = "stopped" ]; then
    echo "Start | $restart_line"
    echo "Show last logs | shell=/usr/bin/osascript param1=-e param2='tell application \"Terminal\" to do script \"cd $COMPOSE_DIR; docker compose -f $COMPOSE_FILE logs --tail=200\"' terminal=false refresh=true"
  else
    echo "Restart | $restart_line"
    echo "Stop | shell=/bin/bash param1=-lc param2='cd \"$COMPOSE_DIR\" && docker compose -f \"$COMPOSE_FILE\" stop' terminal=false refresh=true"
  fi

  echo "---"
  # Logs (AppleScript → Terminal)
  echo "Logs | shell=/usr/bin/osascript param1=-e param2='tell application \"Terminal\" to do script \"cd $COMPOSE_DIR; docker compose -f $COMPOSE_FILE logs -f --tail=200\"' terminal=false refresh=true"

  echo "---"
  echo "Host IP: ${ext_ip:-unknown}"
  echo "VPN IP: ${proxy_ip:-–}"
  print_ws_account_info

  echo "---"
  echo "Refresh IP now | shell=/bin/bash param1=-lc param2='mkdir -p \"$CACHE_DIR\"; : > \"$FORCE_FILE\"' terminal=false refresh=true"
}

# ========= HELPERS =========

# Read COMPOSE_DIR from CONFIG_FILE and verify docker-compose.yml exists
resolve_config() {
  COMPOSE_DIR=""
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi

  # Validate
  if [ -z "${COMPOSE_DIR:-}" ]; then
    return 1
  fi
  if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    return 1
  fi

  COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
  return 0
}

ensure_cache_dir() {
  mkdir -p "$CACHE_DIR"
}

# Count containers in states running|restarting|paused
get_running_count() {
  docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' 2>/dev/null \
    | grep -E 'running|restarting|paused' | wc -l | tr -d ' '
}

# active|stopped|degraded (degraded = has paused/restarting but no running)
get_current_state() {
  local states running paused restarting
  states="$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' 2>/dev/null)"
  running=$(echo "$states" | grep -c 'running' || true)
  paused=$(echo "$states" | grep -c 'paused' || true)
  restarting=$(echo "$states" | grep -c 'restarting' || true)

  if [ "$running" -gt 0 ]; then
    echo "active"
  elif [ "$paused" -gt 0 ] || [ "$restarting" -gt 0 ]; then
    echo "degraded"
  else
    echo "stopped"
  fi
}

# Yellow indicator when paused|restarting is present
has_yellow() {
  docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' 2>/dev/null \
    | grep -Eq 'paused|restarting' && echo 1 || echo 0
}

# Cross-platform mtime (macOS stat -f, Linux stat -c)
file_mtime() {
  local f="$1"
  if [ ! -f "$f" ]; then echo 0; return; fi
  if stat -f "%m" "$f" >/dev/null 2>&1; then
    stat -f "%m" "$f"
  else
    stat -c "%Y" "$f"
  fi
}

cache_expired() {
  local f="$1" ttl="$2"
  [ ! -f "$f" ] && return 0
  local now
  now=$(date +%s)
  local mtime
  mtime=$(file_mtime "$f")
  local age=$((now - mtime))
  [ "$age" -ge "$ttl" ]
}

read_cached_ips() {
  ext_ip=""; proxy_ip=""
  if [ -f "$IP_CACHE_FILE" ]; then
    IFS='|' read -r ext_ip proxy_ip < "$IP_CACHE_FILE"
  fi
}

needs_refresh_ip() {
  # refresh if state changed since last time
  local current="$1"
  local prev="unknown"
  [ -f "$STATE_FILE" ] && prev=$(cat "$STATE_FILE")
  [ "$current" != "$prev" ]
}

refresh_ips() {
  local state="$1"
  # host public IP
  ext_ip=$(curl -s --max-time 3 https://ifconfig.me)

  # default for proxy_ip
  proxy_ip="–"

  # Only attempt proxy when containers are up (active/degraded)
  if [ "$state" = "active" ] || [ "$state" = "degraded" ]; then
    # Quick TCP check that SOCKS is listening on host side
    if nc -z 127.0.0.1 "${SOCKS_ADDR##*:}" >/dev/null 2>&1; then

      # (Optional) check Windscribe status inside container; skip if not instant
      if docker ps --format '{{.Names}}' | grep -qx "$W_SERVICE"; then
        ws_status="$(docker exec "$W_SERVICE" sh -lc 'windscribe status 2>/dev/null' || true)"
        # If status contains "Connected", more likely to get correct VPN IP
        if printf '%s' "$ws_status" | grep -qi "connected"; then
          :
        fi
      fi

      # Do the proxied curl
      if [[ -n "$PROXY_USER" && -n "$PROXY_PASSWORD" ]]; then
        proxy_ip=$(curl -s --max-time 6 -x "socks5h://$PROXY_USER:$PROXY_PASSWORD@$SOCKS_ADDR" https://ifconfig.me 2>/dev/null)
      else
        proxy_ip=$(curl -s --max-time 6 -x "socks5h://$SOCKS_ADDR" https://ifconfig.me 2>/dev/null)
      fi

      # If curl failed, keep "–"
      [ -z "$proxy_ip" ] && proxy_ip="–"
    fi
  fi

  echo "${ext_ip:-unknown}|${proxy_ip:-–}" > "$IP_CACHE_FILE"
  echo -n "$state" > "$STATE_FILE"
}


# Print raw output of `windscribe account` (skipping the header line)
print_ws_account_info() {
  if docker ps --format '{{.Names}}' | grep -qx "$W_SERVICE"; then
    docker exec "$W_SERVICE" sh -c "windscribe account 2>/dev/null" \
      | tail -n +2 \
      | sed 's/\x1B\[[0-9;]*[A-Za-z]//g' \
      | while IFS= read -r line; do
          echo "$line"
        done
  else
    echo "Container not running"
  fi
}

# ========= RUN =========
main
