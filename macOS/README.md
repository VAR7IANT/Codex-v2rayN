# GPT Gateway for macOS

A small macOS launcher for the unified OpenAI ChatGPT desktop app. It launches ChatGPT through a local V2Ray proxy at `127.0.0.1:10808` without permanently changing macOS system proxy settings.

## Default route

```text
ChatGPT.app
    |
    v
GPT Gateway process environment + Chromium proxy flag
    |
    v
socks5://127.0.0.1:10808
    |
    v
V2Ray
    |
    v
Internet / OpenAI
```

## Install

Open Terminal in this folder and run:

```bash
chmod +x GPT-Gateway.command Install-GPT-Gateway.sh
./Install-GPT-Gateway.sh
```

The installer creates:

```text
~/Applications/GPT Gateway.app
```

Then double-click **GPT Gateway** whenever you want to start ChatGPT through V2Ray.

## Requirements

- macOS 14 or newer.
- ChatGPT installed at `/Applications/ChatGPT.app` or `~/Applications/ChatGPT.app`.
- A local V2Ray-compatible SOCKS5 listener at `127.0.0.1:10808`.

The launcher also recognizes the older standalone `Codex.app` path as a fallback.

## What the launcher checks

1. Finds the ChatGPT desktop executable.
2. Refuses to continue when ChatGPT is already running, because an existing process cannot inherit the new proxy environment.
3. Performs an outbound HTTPS request through `socks5h://127.0.0.1:10808`.
4. Detects whether port `10808` also accepts HTTP proxy traffic (mixed inbound).
5. Starts ChatGPT directly with temporary proxy environment variables and an Electron/Chromium `--proxy-server` flag.

No persistent macOS proxy preference is modified.

## Check without launching

```bash
./GPT-Gateway.command --check
```

## Custom host or port

The defaults are intentionally fixed to the same endpoint as the Windows launcher, but you can override them for one launch:

```bash
GPT_GATEWAY_PROXY_HOST=127.0.0.1 \
GPT_GATEWAY_PROXY_PORT=10808 \
./GPT-Gateway.command
```

## Troubleshooting

Log file:

```text
~/Library/Logs/GPT-Gateway.log
```

If the launcher says ChatGPT is already running, use **ChatGPT > Quit ChatGPT** (or `Command-Q`) and launch GPT Gateway again.
