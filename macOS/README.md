# GPT Gateway for macOS

A small macOS launcher for the unified OpenAI ChatGPT desktop app. It launches ChatGPT through a local V2Ray proxy at `127.0.0.1:10808` without permanently changing macOS system proxy settings.

## Default route

```text
ChatGPT.app
    |
    v
GPT Gateway process environment
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

## macOS app experience

The installer creates a normal macOS AppleScript applet instead of using a shell script as the app bundle's main executable:

- **GPT Gateway.app** appears like a regular application and can be pinned to the Dock.
- The wrapper is generated locally with macOS `osacompile` and does not intentionally depend on Rosetta.
- On Apple silicon, the installer checks the generated applet executable for `arm64` support and reports the result.
- A custom high-resolution Gateway icon is generated locally from the included SVG artwork.
- Native macOS notifications show proxy-check and launch status.
- Native macOS error alerts explain failures instead of silently closing.
- After ChatGPT starts successfully, GPT Gateway exits so its temporary Dock icon disappears and only ChatGPT remains running.
- No Homebrew, Python, ImageMagick, or Xcode dependency is required for the wrapper/icon installation.

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

Then double-click **GPT Gateway**, or drag it into the Dock, whenever you want to start ChatGPT through V2Ray.

Re-running the installer safely replaces the generated GPT Gateway wrapper with the latest version from this folder.

## Requirements

- macOS 14 or newer.
- ChatGPT installed at `/Applications/ChatGPT.app` or `~/Applications/ChatGPT.app`.
- A local V2Ray-compatible SOCKS5 listener at `127.0.0.1:10808`.

The launcher also recognizes the older standalone `Codex.app` path as a fallback.

## What the launcher checks

1. Finds the ChatGPT desktop executable.
2. Refuses to continue when ChatGPT is already running, because an existing process cannot inherit the new proxy environment.
3. Performs an outbound HTTPS request through `socks5h://127.0.0.1:10808`; DNS resolution stays on the proxy path.
4. Detects whether port `10808` also accepts HTTP proxy traffic (mixed inbound).
5. Exposes process-scoped proxy environment variables to the new ChatGPT process.
6. Starts ChatGPT directly, verifies the process survived startup, then exits GPT Gateway.

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

If macOS asks to install Rosetta for GPT Gateway, do not install Rosetta just for this wrapper. Update `Install-GPT-Gateway.sh` to the latest branch version and rerun the installer so the applet-based wrapper is rebuilt.

If Finder keeps showing an old icon after reinstalling, relaunch Finder or remove/re-add GPT Gateway from the Dock. The launcher itself is unaffected.
