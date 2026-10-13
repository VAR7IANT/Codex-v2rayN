# Codex Gateway - v2rayN

**Current version: v1.2.0.** The root `VERSION` file is the version source read at runtime.

Codex Gateway is a lightweight, application-scoped proxy launcher using only the CMD and Windows PowerShell built into Windows. It sets local proxy environment variables for the launched process without changing Windows system proxy settings or permanently modifying user/system environment variables.

Originally built for v2rayN, it retains the repository name, BAT name, and launcher name for compatibility. It now also supports Clash, Mihomo, Clash Verge Rev, and other local clients exposing a SOCKS5 or mixed inbound.

The built-in default application is ChatGPT / Codex. You can add other Windows applications by their `.exe` paths and select any of them as the default.

## Daily Launch

Double-click **Codex Gateway - v2rayN**, or run:

```bat
Codex-v2rayN.bat
```

By default, a short two-second launch prompt appears:

```text
[S] Settings    [Enter] Launch now
Auto launch in 2 seconds...
```

- Press `S` to enter Settings.
- Press `Enter` to skip the countdown and launch the default app immediately.
- Press nothing to launch it when the countdown ends.
- In a noninteractive terminal, launch immediately without waiting for keyboard input.

The Gateway remembers your default app, so normal launches require no app selection. Use `S` or `--settings` to change settings.

## Terminal Interface

Gateway uses a centered, responsive terminal panel. It maintains a compact reading width in wide windows and contracts in narrow ones. Resizing Windows Terminal reflows the current screen: the launch prompt and closing error screen respond immediately, checking/launching views update on the next status event, and the settings interface continues monitoring resizes.

Titles, proxy-route summaries, and final status are centered; steps, paths, and settings align left within the panel. Full-width Chinese characters are counted as two columns, keeping alignment consistent between Chinese and English.

The UI uses only built-in terminal colors and Unicode box-drawing characters. It has no animations, additional fonts, or third-party UI dependencies. Use Windows Terminal or the Windows 11 default terminal if an older console cannot display Unicode lines.

## Settings

Press `S` during the launch prompt, or run:

```bat
Codex-v2rayN.bat --settings
```

Available controls:

- Number keys: select a default application
- `A`: add an application by its `.exe` path
- `E`: edit a custom app's name, path, arguments, or working directory
- `D`: delete a custom application
- `L`: switch between Simplified Chinese and English
- `T`: configure the launch delay in seconds (`0`–`60`; `0` launches immediately)
- `P`: switch between automatic proxy-port discovery and a manually configured port
- `Enter`: save settings and launch the default app
- `Q`: save settings and exit without launching

The built-in `ChatGPT / Codex` profile cannot be deleted.

Custom application settings are stored at:

```text
%LOCALAPPDATA%\CodexGateway\apps.json
```

An `apps.json.bak` backup is retained before overwriting settings. Because configuration lives outside the project folder, unpacking or upgrading Gateway does not overwrite the saved app list.

The launch delay is stored in the same file. Existing `apps.json` files without a delay automatically use two seconds. Even if the delay is set to zero, `--settings` remains available.

## Language Selection

Gateway includes two UI languages:

- Simplified Chinese: `zh-CN`
- English: `en-US`

The first run follows the Windows UI language; non-Chinese systems default to English. Press `L` in Settings to switch languages. The choice persists in `apps.json` and is reused automatically.

Launch prompts, settings, three-stage status views, success messages, and major error messages follow the selected language. Package names, paths, protocol names, and underlying Windows/PowerShell error text remain unchanged for troubleshooting.

## Add a Custom Application

Press `A` in Settings and paste a full `.exe` path. Paths may contain spaces, parentheses, and non-ASCII characters. You can also drag an executable into the terminal.

Each custom application stores a display name, executable path, optional arguments, and optional working directory (defaults to the executable's directory).

Before launching, Gateway verifies the executable and working directory, checks for another process using the same executable with `Get-CimInstance Win32_Process`, and verifies that the expected process appears after startup.

An existing process cannot inherit the proxy environment of this new launch. When the app is already running, Gateway asks you to close it instead of reusing it.

## Optional Proxy Argument Placeholders

Some applications honor `ALL_PROXY`, `HTTP_PROXY`, and `HTTPS_PROXY`; others require their own proxy command-line flags. Custom arguments support:

| Placeholder | Example substitution |
|---|---|
| `{proxy_host}` | `127.0.0.1` |
| `{proxy_port}` | `10808` |
| `{socks_proxy}` | `socks5://127.0.0.1:10808` |
| `{http_proxy}` | `http://127.0.0.1:10808` |

Example:

```text
--proxy-server={socks_proxy}
```

The placeholders resolve to the actual detected endpoint before launch. Argument contents are not displayed during normal startup or written to logs. Do not store passwords, tokens, or other secrets in application arguments.

Whether proxy environment variables or command-line flags work depends on the target application's own support. Gateway does not inject or modify third-party application code.

## Automatic ChatGPT / Codex Selection

The built-in Codex profile retains its dynamic discovery:

1. Prefer `OpenAI.CodexBeta` by default.
2. Fall back automatically to `OpenAI.Codex` Stable if Beta is absent.
3. Query the installed package dynamically with `Get-AppxPackage`, without hardcoding a versioned directory.
4. Prefer the actual executable declared by the AppX Manifest.
5. If the Manifest cannot be used, check `app\ChatGPT (Beta).exe` or `app\ChatGPT.exe`.

`AppPreference` in `GatewayConfig.ps1` supports:

| Value | Behavior |
|---|---|
| `PreferBeta` | Beta first, then Stable |
| `PreferStable` | Stable first, then Beta |
| `BetaOnly` | Beta only |
| `StableOnly` | Stable only |

## Check Without Launching

```bat
Codex-v2rayN.bat --check
```

`--check` does not show the launch prompt or start an application. It checks the v2rayN SOCKS5 handshake, an HTTPS health-check destination through SOCKS5, the default application profile, the AppX package or custom executable, and whether executable/working-directory paths exist.

An OpenAI health-check response of HTTP `401` or `403` still confirms that the proxy, TLS, and remote server are reachable. Gateway does not send API keys, tokens, or cookies.

## Proxy Scope

For a mixed inbound, the default environment is:

```text
ALL_PROXY=socks5://127.0.0.1:10808
all_proxy=socks5://127.0.0.1:10808
HTTP_PROXY=http://127.0.0.1:10808
HTTPS_PROXY=http://127.0.0.1:10808
http_proxy=http://127.0.0.1:10808
https_proxy=http://127.0.0.1:10808
NO_PROXY=localhost,127.0.0.1,::1
no_proxy=localhost,127.0.0.1,::1
```

These variables exist only in the Gateway PowerShell process and its child processes. Gateway does not use `setx`, alter Windows system proxy settings, write registry proxy configuration, or affect unrelated terminals/applications.

## Automatic Endpoint Discovery

Gateway discovers local endpoints in this order:

1. Locate the v2rayN root from running `v2rayN.exe`, `sing-box`, or `xray` processes.
2. Check the runtime inbound in `binConfigs\config.json`.
3. Check the GUI inbound in `guiConfigs\guiNConfig.json`.
4. Check top-level `mixed-port` and `socks-port` in Mihomo/Clash YAML or JSON.
5. Recognize Clash/Mihomo/Clash Verge processes and probe a small set of common ports: `7890`, `7891`, `7897`, `7898`.
6. Check inherited loopback `ALL_PROXY`, `HTTPS_PROXY`, and `HTTP_PROXY`, accepting only ports that pass a SOCKS5 handshake.
7. Use the `GatewayConfig.ps1` fallback: `127.0.0.1:10808`.

Only loopback addresses are accepted. Gateway performs a real SOCKS5 handshake and checks whether the same port supports HTTP CONNECT to identify a mixed inbound.

Automatic discovery is the default. Press `P` in Settings to set a port from `1` to `65535`, pinned to `127.0.0.1:<port>`; enter `auto` to restore discovery. Manual mode does not secretly fall back to another port, so a reported failure always names the endpoint actually tested.

Discovery does not scan all 65,535 ports. It reads configured inbounds or, when a compatible client process is detected, checks a small list of common ports and tests the candidates with SOCKS5 handshakes.

In Mihomo, `mixed-port` supports HTTP(S) and SOCKS5, while `socks-port` exposes SOCKS5. Gateway requires at least SOCKS5 support; a `port`-only, HTTP-only configuration is not selected.

## Administrator Configuration

`GatewayConfig.ps1` exposes a few advanced settings:

```powershell
AppPreference        = 'PreferBeta'
DefaultProxyHost     = '127.0.0.1'
DefaultProxyPort     = 10808
LaunchTimeoutSeconds = 15
```

Most users should manage the application list and default app through Settings instead of editing this file.

## Install Launcher Shortcuts

Desktop shortcut:

```bat
Install-Launcher.bat
```

Start Menu shortcut:

```bat
Install-Launcher.bat --start-menu
```

The shortcut remains named **Codex Gateway - v2rayN** and points to `Codex-v2rayN.bat` in the current directory, never to a specific target application or executable.

Remove the desktop shortcut:

```bat
Install-Launcher.bat --uninstall
```

Remove the Start Menu shortcut:

```bat
Install-Launcher.bat --start-menu --uninstall
```

Removing shortcuts does not delete application configuration, logs, the project, v2rayN, or any launched application.

## File Layout

| File | Responsibility |
|---|---|
| `Codex-v2rayN.bat` | Thin entry point for `--check`, `--settings`, and PowerShell |
| `Launch-CodexApp.ps1` | Launch hotkey prompt, settings UI, three-stage checks, process launch, and logging |
| `AppProfileSupport.ps1` | User app configuration, path resolution, process detection, and argument placeholders |
| `LocalizationSupport.ps1` | Language detection, UTF-8 locale loading, and text formatting |
| `locales\zh-CN.json` | Simplified Chinese UI resources |
| `locales\en-US.json` | English UI resources |
| `AppSupport.ps1` | Codex AppX, Manifest, and WindowsApps process detection |
| `GatewayConfig.ps1` | Endpoint, timeouts, and Codex selection policy |
| `Resolve-v2rayNProxy.ps1` | v2rayN endpoint discovery |
| `ProxySupport.ps1` | SOCKS5, mixed inbound, and TLS checks |
| `Install-Launcher.bat/.ps1` | Install/remove shortcuts |
| `VERSION` | Gateway version |
| `assets\` | Icon assets |
| `tests\` | PowerShell regression tests |

## Logs

```text
logs\gateway-YYYY-MM-DD.log
```

Logs record version, operating mode, default app name/type, endpoint, final executable, launch result, and errors. They do **not** record complete environment variables, application arguments, tokens, API keys, cookies, or passwords.

## Troubleshooting

### v2rayN is stopped or its port changed

Launch v2rayN and verify that its core is running. Gateway tries to read the runtime configuration and falls back to `GatewayConfig.ps1` when the configuration cannot be found. Errors display the endpoint and discovery source.

### The application is already running

Exit existing instances fully and retry. Existing processes cannot inherit the new Gateway environment.

### The custom application launches without a proxy

Check whether it supports `ALL_PROXY`, `HTTP_PROXY`, or `HTTPS_PROXY`. If it requires a command-line flag, add `{socks_proxy}` or `{http_proxy}` to its configured arguments. Some applications ignore both environment variables and command-line proxy options.

### Custom executable moved or uninstalled

The missing path is reported during launch. Press `S` to open Settings, then `E` to update the path or `D` to remove the app.

### Application configuration is corrupted

Errors identify the problem in `%LOCALAPPDATA%\CodexGateway\apps.json`. Restore `apps.json.bak` from the same directory, or delete the invalid JSON to return to the default Codex profile.

### Neither Beta nor Stable is installed

The built-in profile reports an AppX error. Install `OpenAI.CodexBeta` or `OpenAI.Codex`, or press `S` to add another executable and make it the default.

## Exit Codes

| Code | Meaning |
|---:|---|
| `0` | Launch, check, or settings exit succeeded |
| `1` | Endpoint or SOCKS5 handshake failed |
| `2` | Codex AppX package unavailable |
| `3` | Executable or working directory unavailable |
| `4` | Application already running or process safety check failed |
| `5` | `Start-Process` failed |
| `6` | Target process not observed after launch |
| `7` | HTTPS health check failed |
| `8` | Cannot write logs |
| `9` | Invalid Gateway administrator configuration |
| `10` | Unexpected error |
| `11` | Invalid user application JSON configuration |
| `64` | Invalid BAT arguments |
