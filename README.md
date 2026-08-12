# Codex via v2rayN Launcher

A lightweight Windows launcher that starts OpenAI Codex through a v2rayN SOCKS5 proxy without changing your system-wide proxy settings.

## Default proxy

- Host: `127.0.0.1`
- Port: `10808`
- URL: `socks5://127.0.0.1:10808`

The launcher normally discovers the current endpoint automatically. These values are only the fallback when no running v2rayN configuration can be read.

## Features

- Presents a clean three-stage launch screen with clear success and error states.
- Uses a dedicated, high-resolution Windows launcher icon.
- Detects the running v2rayN installation path and current SOCKS/mixed port automatically.
- Checks whether the v2rayN SOCKS5 port is reachable before launch.
- Automatically finds the newest installed `OpenAI.Codex` Windows app.
- Applies the proxy only to this Codex launch.
- Clears stale `HTTP_PROXY` and `HTTPS_PROXY` values for the launched process tree.
- Does not permanently change Windows environment variables or system proxy settings.

## Install the launcher

Double-click `Install-Launcher.bat`. It creates a **Codex Gateway** shortcut on the Windows desktop using `assets/Codex-v2rayN.ico`.

Windows batch files cannot embed custom icons directly. The generated shortcut is the launcher that carries the custom icon and starts `Codex-v2rayN.bat`.

## Usage

1. Start v2rayN.
2. Make sure its SOCKS5 port is `10808`.
3. Close any Codex windows that are already running.
4. Double-click the **Codex Gateway** desktop shortcut.
5. Wait for all three checks to complete.

To verify the proxy and Codex installation without launching the app, run:

```bat
Codex-v2rayN.bat --check
```

## Proxy endpoint detection

The launcher resolves the endpoint in this order:

1. Active core configuration at `binConfigs/config.json` beside the running `v2rayN.exe`.
2. v2rayN GUI configuration at `guiConfigs/guiNConfig.json`.
3. The default fallback in `Codex-v2rayN.bat`.

This supports portable v2rayN folders and custom local ports without storing an installation path in the launcher.

To change the fallback endpoint, edit:

```bat
set "DEFAULT_PROXY_HOST=127.0.0.1"
set "DEFAULT_PROXY_PORT=10808"
```

## How it works

```text
Codex Windows App
        |
        v
ALL_PROXY=socks5://127.0.0.1:10808
        |
        v
v2rayN
        |
        v
Current proxy node
        |
        v
Internet / OpenAI
```

## Notes

This launcher only affects the Codex process tree started from it. Closing that Codex session removes the temporary proxy environment with the process; no permanent Windows network settings are changed.

Codex must be closed before a proxied launch. An already-running process cannot inherit the temporary proxy variables, so the launcher stops with a clear message instead of reporting a misleading success.
