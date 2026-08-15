# GPT Gateway for macOS

A macOS-only launcher that starts the ChatGPT desktop app through a local V2Ray proxy without changing the persistent macOS system proxy.

## Download

Do **not** use GitHub's whole-branch `Download ZIP` for normal installation.

Download this versioned package instead:

```text
dist/GPT-Gateway-macOS-v2.1.0.zip
```

That exact ZIP is generated and then re-extracted/tested by the macOS ARM64 CI job before it is committed to the branch.

## Default proxy

```text
127.0.0.1:10808
socks5h://127.0.0.1:10808
```

## Architecture

This branch contains no Windows BAT, PowerShell, Windows proxy helper, Windows test, or Windows icon code.

`GPT Gateway.app` uses a real Mach-O executable as `CFBundleExecutable`. It does not use a shell script or AppleScript applet as the application entry point.

The launcher is built as a Universal Mach-O containing:

```text
arm64 x86_64
```

The app also sets:

```text
LSRequiresNativeExecution = true
```

On the macOS ARM64 CI runner, both the raw launcher and the launcher copied into the final application bundle must report:

```text
arch=arm64 translated=0
```

before the package is accepted.

## Install

Extract `GPT-Gateway-macOS-v2.1.0.zip`, open Terminal in the extracted `GPT-Gateway-macOS-v2.1.0` folder, then run:

```bash
zsh Install-GPT-Gateway.sh
```

The installer automatically restores executable permissions if the ZIP extractor removed them. It also verifies the launcher SHA-256, checks the `arm64` slice, installs the app, signs the local bundle ad-hoc, clears quarantine from the generated app, and performs a native-execution self-test.

The installed app is:

```text
~/Applications/GPT Gateway.app
```

Then completely quit ChatGPT with `Command-Q` and open **GPT Gateway**.

## What CI tests

The macOS workflow does more than compile the project:

1. zsh, Python, and C syntax checks
2. Universal `arm64 + x86_64` Mach-O build
3. native Apple-silicon runtime self-test (`translated=0`)
4. a local mock SOCKS5 server
5. a real `curl` request through that SOCKS5 server
6. process-scoped `ALL_PROXY` injection into a fake ChatGPT executable
7. Chromium `--proxy-server` argument injection
8. complete `.app` installation
9. `Info.plist`, architecture, and code-sign validation
10. creation of the versioned ZIP
11. re-extraction of that exact ZIP followed by a second full installation and native self-test

## What happens on launch

1. the native `GPTGatewayLauncher` starts
2. it runs the bundled `gateway.zsh`
3. the script finds `ChatGPT.app`
4. it checks V2Ray through `127.0.0.1:10808`
5. it exports process-scoped SOCKS5 proxy variables
6. if port `10808` also accepts HTTP proxy traffic, HTTP/HTTPS variables are enabled too
7. ChatGPT starts with the proxy environment and Chromium proxy argument
8. GPT Gateway exits

No persistent macOS network preference is modified.

## Check without launching ChatGPT

```bash
"$HOME/Applications/GPT Gateway.app/Contents/MacOS/GPTGatewayLauncher" --check
```

## Verify native execution

```bash
"$HOME/Applications/GPT Gateway.app/Contents/MacOS/GPTGatewayLauncher" --native-self-test
```

On Apple silicon, expected output is:

```text
arch=arm64 translated=0
```

## Logs

```text
~/Library/Logs/GPT-Gateway.log
```

## Requirements

- macOS 14 or newer for the current ChatGPT desktop app
- Apple silicon or Intel Mac supported by the installed ChatGPT build
- ChatGPT.app installed in `/Applications` or `~/Applications`
- V2Ray SOCKS5 or mixed inbound listening on `127.0.0.1:10808`
