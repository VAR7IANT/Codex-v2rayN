# GPT Gateway for macOS

A clean macOS-only launcher that starts the ChatGPT desktop app through a local V2Ray SOCKS5 proxy without changing the persistent macOS system proxy.

## Default proxy

```text
127.0.0.1:10808
socks5h://127.0.0.1:10808
```

## Why this version is different

This branch contains no Windows BAT or PowerShell launcher code. The application bundle uses a real native Mach-O executable as `CFBundleExecutable` instead of a shell script or AppleScript applet.

The native launcher is built and verified on a GitHub macOS runner as a Universal binary containing both `arm64` and `x86_64`. The generated app also sets `LSRequiresNativeExecution=true`, so Apple-silicon Macs do not use Rosetta for GPT Gateway.

## Project layout

```text
Install-GPT-Gateway.sh        macOS installer
src/GPTGatewayLauncher.c      native app entry point
src/gateway.zsh               V2Ray and ChatGPT launch logic
assets/GPT-Gateway.svg        icon source
build/GPTGatewayLauncher      verified Universal Mach-O binary
.github/workflows/test.yml    macOS build and validation
```

## Install

Download the complete `agent/macos-gpt-gateway` branch ZIP after the GitHub macOS build has passed, extract it, open Terminal in the extracted folder, and run:

```bash
chmod +x Install-GPT-Gateway.sh
./Install-GPT-Gateway.sh
```

The installer creates:

```text
~/Applications/GPT Gateway.app
```

Then completely quit ChatGPT with `Command-Q` and open **GPT Gateway**.

## What happens on launch

1. GPT Gateway starts through its native Universal Mach-O executable
2. The launcher runs the bundled `gateway.zsh`
3. The script finds `/Applications/ChatGPT.app`
4. It verifies V2Ray connectivity through `127.0.0.1:10808`
5. It exports process-scoped SOCKS5 proxy variables
6. If port `10808` also supports HTTP CONNECT, HTTP/HTTPS proxy variables are added automatically
7. ChatGPT starts as a child process with the proxy environment
8. GPT Gateway exits

No persistent macOS network preference is modified.

## Check the proxy without launching ChatGPT

After installation:

```bash
"$HOME/Applications/GPT Gateway.app/Contents/MacOS/GPTGatewayLauncher" --check
```

## Verify native architecture

```bash
file "$HOME/Applications/GPT Gateway.app/Contents/MacOS/GPTGatewayLauncher"
lipo -archs "$HOME/Applications/GPT Gateway.app/Contents/MacOS/GPTGatewayLauncher"
defaults read "$HOME/Applications/GPT Gateway.app/Contents/Info" LSRequiresNativeExecution
```

Expected architecture output contains both:

```text
arm64 x86_64
```

and `LSRequiresNativeExecution` should return `1`.

## Logs

```text
~/Library/Logs/GPT-Gateway.log
```

## Requirements

- macOS 12 or newer
- Apple silicon or Intel Mac
- ChatGPT.app installed in `/Applications` or `~/Applications`
- V2Ray SOCKS5 or mixed inbound listening on `127.0.0.1:10808`
