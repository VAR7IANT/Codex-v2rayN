#!/bin/zsh
set -eu

PROXY_HOST="${GPT_GATEWAY_PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${GPT_GATEWAY_PROXY_PORT:-10808}"
CHECK_URL="${GPT_GATEWAY_CHECK_URL:-https://chatgpt.com/}"
SOCKS_PROXY="socks5h://${PROXY_HOST}:${PROXY_PORT}"
SOCKS_CHROMIUM="socks5://${PROXY_HOST}:${PROXY_PORT}"
HTTP_PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
SKIP_UI="${GPT_GATEWAY_SKIP_UI:-}"

LOG_DIR="${GPT_GATEWAY_LOG_DIR:-$HOME/Library/Logs}"
LOG_FILE="$LOG_DIR/GPT-Gateway.log"
mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

notify() {
  if [[ -n "$SKIP_UI" ]]; then
    return 0
  fi
  /usr/bin/osascript - "$1" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 1 of argv) with title "GPT Gateway"
end run
APPLESCRIPT
}

alert() {
  local message="$1"
  log "ERROR: $message"
  if [[ -n "$SKIP_UI" ]]; then
    printf 'GPT Gateway: %s\n' "$message" >&2
    return 0
  fi
  /usr/bin/osascript - "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display alert "GPT Gateway" message (item 1 of argv) as critical buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

find_chatgpt() {
  if [[ -n "${GPT_GATEWAY_APP_BIN:-}" ]]; then
    if [[ -x "$GPT_GATEWAY_APP_BIN" ]]; then
      printf '%s\n' "$GPT_GATEWAY_APP_BIN"
      return 0
    fi
    return 1
  fi

  local candidate
  for candidate in \
    "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" \
    "$HOME/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

log "------------------------------------------------------------"
log "GPT Gateway starting"
log "Proxy: $SOCKS_PROXY"
log "Check URL: $CHECK_URL"

APP_BIN="$(find_chatgpt || true)"
if [[ -z "$APP_BIN" ]]; then
  alert "ChatGPT.app was not found in /Applications or ~/Applications."
  exit 1
fi

if /usr/bin/pgrep -f "$APP_BIN" >/dev/null 2>&1; then
  alert "ChatGPT is already running. Quit it completely with Command-Q, then open GPT Gateway again."
  exit 1
fi

notify "Checking V2Ray on ${PROXY_HOST}:${PROXY_PORT}…"

if ! /usr/bin/curl \
  --silent \
  --show-error \
  --output /dev/null \
  --max-time 10 \
  --proxy "$SOCKS_PROXY" \
  "$CHECK_URL"; then
  alert "V2Ray could not reach ChatGPT through ${PROXY_HOST}:${PROXY_PORT}. Check that V2Ray is running and port ${PROXY_PORT} is a SOCKS5 or mixed inbound."
  exit 1
fi

export ALL_PROXY="$SOCKS_PROXY"
export all_proxy="$SOCKS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"

CHROMIUM_PROXY="$SOCKS_CHROMIUM"
if /usr/bin/curl \
  --silent \
  --show-error \
  --output /dev/null \
  --max-time 5 \
  --proxy "$HTTP_PROXY_URL" \
  "$CHECK_URL"; then
  export HTTP_PROXY="$HTTP_PROXY_URL"
  export HTTPS_PROXY="$HTTP_PROXY_URL"
  export http_proxy="$HTTP_PROXY_URL"
  export https_proxy="$HTTP_PROXY_URL"
  CHROMIUM_PROXY="$HTTP_PROXY_URL"
  log "Proxy mode: mixed HTTP/SOCKS"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy 2>/dev/null || true
  log "Proxy mode: SOCKS5"
fi

if [[ "${1:-}" == "--check" ]]; then
  printf 'GPT Gateway check passed\nProxy: %s\nApp: %s\n' "$SOCKS_PROXY" "$APP_BIN"
  notify "V2Ray check passed"
  exit 0
fi

log "Launching: $APP_BIN"

"$APP_BIN" \
  --proxy-server="$CHROMIUM_PROXY" \
  --proxy-bypass-list="localhost;127.0.0.1;[::1]" \
  >> "$LOG_FILE" 2>&1 &

APP_PID=$!
sleep 1

if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
  alert "ChatGPT exited immediately after launch. See ~/Library/Logs/GPT-Gateway.log."
  exit 1
fi

log "ChatGPT started successfully (pid $APP_PID)"
notify "ChatGPT is running through V2Ray ${PROXY_HOST}:${PROXY_PORT}"
exit 0
