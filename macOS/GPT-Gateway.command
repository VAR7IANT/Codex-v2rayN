#!/bin/zsh
set -u

# GPT Gateway for macOS
# Launches ChatGPT through a local V2Ray proxy without permanently changing
# macOS system proxy settings.

PROXY_HOST="${GPT_GATEWAY_PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${GPT_GATEWAY_PROXY_PORT:-10808}"
SOCKS_PROXY="socks5h://${PROXY_HOST}:${PROXY_PORT}"
CHROMIUM_SOCKS_PROXY="socks5://${PROXY_HOST}:${PROXY_PORT}"
HTTP_PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/GPT-Gateway.log"

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

show_error() {
  local message="$1"
  log "ERROR: $message"
  /usr/bin/osascript - "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display alert "GPT Gateway" message (item 1 of argv) as critical buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

show_notification() {
  local message="$1"
  /usr/bin/osascript - "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 1 of argv) with title "GPT Gateway"
end run
APPLESCRIPT
}

find_chatgpt_binary() {
  local candidate
  for candidate in \
    "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" \
    "$HOME/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" \
    "/Applications/Codex.app/Contents/MacOS/Codex" \
    "$HOME/Applications/Codex.app/Contents/MacOS/Codex"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

log "------------------------------------------------------------"
log "GPT Gateway starting"
log "Proxy: ${SOCKS_PROXY}"

APP_BIN="$(find_chatgpt_binary || true)"
if [[ -z "$APP_BIN" ]]; then
  show_error "ChatGPT was not found. Install ChatGPT.app in /Applications, then try again."
  exit 1
fi
log "App binary: $APP_BIN"

# A running instance cannot inherit this launcher's temporary environment.
if /usr/bin/pgrep -f "$APP_BIN" >/dev/null 2>&1; then
  show_error "ChatGPT is already running. Quit ChatGPT completely, then open GPT Gateway again so the new process can inherit the proxy."
  exit 1
fi

show_notification "Checking V2Ray on ${PROXY_HOST}:${PROXY_PORT}…"
log "Checking SOCKS5 outbound access through ${PROXY_HOST}:${PROXY_PORT}"

# socks5h keeps hostname resolution inside the proxy path.
if ! /usr/bin/curl -sS -o /dev/null --max-time 8 --proxy "$SOCKS_PROXY" "https://chatgpt.com/"; then
  show_error "V2Ray proxy check failed at ${PROXY_HOST}:${PROXY_PORT}. Make sure V2Ray is running and its SOCKS5 or mixed inbound is listening on port ${PROXY_PORT}."
  exit 1
fi
log "SOCKS5 HTTPS check passed"

# Always expose SOCKS to compatible child processes.
export ALL_PROXY="$SOCKS_PROXY"
export all_proxy="$SOCKS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"

# If the same V2Ray inbound also accepts HTTP CONNECT, expose HTTP(S) proxy
# variables as well. Otherwise keep the launch SOCKS-only.
CHROMIUM_PROXY="$CHROMIUM_SOCKS_PROXY"
if /usr/bin/curl -sS -o /dev/null --max-time 5 --proxy "$HTTP_PROXY_URL" "https://chatgpt.com/"; then
  export HTTP_PROXY="$HTTP_PROXY_URL"
  export HTTPS_PROXY="$HTTP_PROXY_URL"
  export http_proxy="$HTTP_PROXY_URL"
  export https_proxy="$HTTP_PROXY_URL"
  export WSS_PROXY="$HTTP_PROXY_URL"
  export wss_proxy="$HTTP_PROXY_URL"
  CHROMIUM_PROXY="$HTTP_PROXY_URL"
  log "Detected mixed HTTP/SOCKS inbound on port ${PROXY_PORT}"
else
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy WSS_PROXY wss_proxy 2>/dev/null || true
  log "Detected SOCKS-only inbound on port ${PROXY_PORT}"
fi

if [[ "${1:-}" == "--check" ]]; then
  log "Check complete; nothing launched"
  printf '\nGPT Gateway check passed.\nProxy: %s\nApp: %s\n' "$SOCKS_PROXY" "$APP_BIN"
  show_notification "V2Ray check passed. ChatGPT was not launched."
  exit 0
fi

log "Launching ChatGPT with process-scoped proxy"

# Start ChatGPT as a child so it inherits this process environment, then let
# GPT Gateway itself exit. This makes the temporary Gateway Dock icon disappear
# while ChatGPT keeps running with the inherited proxy configuration.
"$APP_BIN" \
  --proxy-server="$CHROMIUM_PROXY" \
  --proxy-bypass-list="localhost;127.0.0.1;[::1]" \
  >> "$LOG_FILE" 2>&1 &
APP_PID=$!

sleep 1
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
  show_error "ChatGPT exited immediately after launch. Open ~/Library/Logs/GPT-Gateway.log for details."
  exit 1
fi

log "ChatGPT started successfully (pid ${APP_PID})"
show_notification "ChatGPT is running through V2Ray ${PROXY_HOST}:${PROXY_PORT}."
exit 0
