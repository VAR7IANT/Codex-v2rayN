# Codex via v2rayN Launcher

A lightweight Windows launcher that starts OpenAI Codex through a v2rayN SOCKS5 proxy without changing your system-wide proxy settings.

## Default proxy

- Host: `127.0.0.1`
- Port: `10808`
- URL: `socks5://127.0.0.1:10808`

## Features

- Checks whether the v2rayN SOCKS5 port is reachable before launch.
- Automatically finds the installed `OpenAI.Codex` Windows app.
- Applies the proxy only to this Codex launch.
- Clears stale `HTTP_PROXY` / `HTTPS_PROXY` values for the launched process tree.
- Does not permanently change Windows environment variables or system proxy settings.

## Usage

1. Start v2rayN.
2. Make sure the SOCKS5 port is `10808`.
3. Double-click `Codex-v2rayN.bat`.
4. Codex will launch using the current v2rayN node.

## Change the proxy port

Edit these lines near the top of `Codex-v2rayN.bat`:

```bat
set "PROXY_HOST=127.0.0.1"
set "PROXY_PORT=10808"
```

## How it works

```text
Codex Windows App
        ↓
ALL_PROXY=socks5://127.0.0.1:10808
        ↓
v2rayN
        ↓
Current proxy node
        ↓
Internet / OpenAI
```

## Notes

This launcher only affects the Codex process tree started from it. Closing that Codex session removes the temporary proxy environment with the process; no permanent Windows network settings are changed.
