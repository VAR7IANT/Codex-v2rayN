#!/bin/zsh
set -u

# GPT Gateway for macOS
# Launches the unified ChatGPT desktop app through a local V2Ray proxy
# without changing persistent macOS system proxy settings.

PROXY_HOST="${GPT_GATEWAY_PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${GPT_GATEWAY_PROXY_PORT:-10808}"
SOCKS_PROXY="socks5h://${PROXY_HOST}:${PROXY_PORT}"
CHROMIUM_SOCKS_PROXY="socks5://${PROXY_HOST}:${PROXY_PORT}"
HTTP_PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/GPT-Gateway.log"

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

show_error() {
  local message="$1"
  log "ERROR: $message"
  /usr/bin/osascript - "$message" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display dialog (item 1 of argv) with title "GPT Gateway" buttons {"OK"} default button "OK" with icon stop
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

if /usr/bin/pgrep -f "$APP_BIN" >/dev/null 2>&1; then
  show_error "ChatGPT is already running. Quit ChatGPT completely, then open GPT Gateway again so the new process can inherit the proxy."
  exit 1
fi

log "Checking SOCKS5 outbound access through ${PROXY_HOST}:${PROXY_PORT}"
if ! /usr/bin/curl -sS -o /dev/null --max-time 8 --proxy "$SOCKS_PROXY" "https://chatgpt.com/"; then
  show_error "V2Ray proxy check failed at ${PROXY_HOST}:${PROXY_PORT}. Make sure V2Ray is running and the SOCKS5 port is 10808."
  exit 1
fi
log "SOCKS5 HTTPS check passed"

# Always expose SOCKS to compatible child processes.
export ALL_PROXY="$SOCKS_PROXY"
export all_proxy="$SOCKS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"

# Some ChatGPT/Codex child components prefer HTTP(S)_PROXY. If the same
# V2Ray inbound is mixed and accepts HTTP CONNECT, expose those variables too.
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
  exit 0
fi

log "Launching ChatGPT with process-scoped proxy"
show_notification "Launching ChatGPT through V2Ray on ${PROXY_HOST}:${PROXY_PORT}"

# Launch the executable directly so it inherits the environment. The Chromium
# proxy flag additionally covers Electron/Chromium network traffic in the app.
exec "$APP_BIN" \
  --proxy-server="$CHROMIUM_PROXY" \
  --proxy-bypass-list="localhost;127.0.0.1;[::1]"
