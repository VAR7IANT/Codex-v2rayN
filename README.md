# Codex via v2rayN Launcher

A lightweight Windows launcher that starts OpenAI Codex through a v2rayN SOCKS5 proxy without changing your system-wide proxy settings.

## macOS GPT Gateway

A macOS companion launcher is now available under [`macOS/`](macOS/README.md). It starts the unified `ChatGPT.app` through a local V2Ray proxy while keeping the proxy scoped to that launch.

Default macOS endpoint:

- Host: `127.0.0.1`
- Port: `10808`
- SOCKS URL: `socks5://127.0.0.1:10808`

The macOS installer creates `~/Applications/GPT Gateway.app`, which can be opened like a normal app. See [`macOS/README.md`](macOS/README.md) for install and troubleshooting instructions.

## Default proxy

- Host: `127.0.0.1`
- Port: `10808`
- URL: `socks5://127.0.0.1:10808`

The launcher normally discovers the current endpoint automatically. These values are only the fallback when no running v2rayN configuration can be read.

## Features

- Presents a clean three-stage launch screen with clear success and error states.
- Uses a dedicated, high-resolution Windows launcher icon.
- Detects the running v2rayN installation path and current SOCKS/mixed port automatically.
- Completes a real SOCKS5 handshake instead of trusting an open TCP port.
- Tests outbound HTTPS through the selected v2rayN node in `--check` mode using a native SOCKS5/TLS probe with certificate validation.
- Automatically finds the newest installed `OpenAI.Codex` Windows app.
- Applies the proxy only to this Codex launch.
- Sets proxy environment variables according to the detected SOCKS or mixed inbound and clears incompatible stale values.
- Does not permanently change Windows environment variables or system proxy settings.

## Install the launcher

Double-click `Install-Launcher.bat`. It creates a **Codex Gateway** shortcut on the Windows desktop using `assets/Codex-v2rayN.ico`.

Windows batch files cannot embed custom icons directly. The generated shortcut is the launcher that carries the custom icon and starts `Codex-v2rayN.bat`.

## Usage

1. Start v2rayN.
2. Close any Codex windows that are already running.
3. Double-click the **Codex Gateway** desktop shortcut.
4. Wait for all three checks to complete.

To verify the proxy and Codex installation without launching the app, run:

```bat
Codex-v2rayN.bat --check
```

## Proxy endpoint detection

The launcher resolves the endpoint in this order:

1. Active core configuration at `binConfigs/config.json` beside the running `v2rayN.exe` or proxy core.
2. v2rayN GUI configuration at `guiConfigs/guiNConfig.json`.
3. The default fallback in `Codex-v2rayN.bat`.

This supports portable v2rayN folders and custom local ports without storing an installation path in the launcher.

When several SOCKS/mixed inbounds are configured, the launcher performs a SOCKS5 handshake and selects the first active endpoint. It also probes the selected port for HTTP proxy support so a modern mixed inbound is recognized even when the GUI labels it as SOCKS. Only loopback listeners are accepted; non-local addresses are rejected. IPv4 and IPv6 loopback addresses are supported.

For a `mixed` inbound, the launcher sets `ALL_PROXY`, `HTTP_PROXY`, and `HTTPS_PROXY`. For a SOCKS-only inbound, it sets `ALL_PROXY` and clears stale HTTP proxy variables. Local callbacks are excluded with `NO_PROXY`.

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

The environment variables route the desktop process and compatible child processes. Codex sandbox networking has its own configuration and permission controls; see the [official OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) for `features.network_proxy` and permission-profile network settings.
