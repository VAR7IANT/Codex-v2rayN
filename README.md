# Codex Gateway - v2rayN

当前项目版本：**v1.2.0**。根目录中的 `VERSION` 是 Gateway 运行时读取的版本来源。

这是一个仅使用 Windows 自带 CMD 与 Windows PowerShell 的轻量应用 Gateway。它为本次启动的应用进程设置本地代理环境，不修改 Windows 系统代理，也不永久写入用户或系统环境变量。

项目最初为 v2rayN 编写，因此保留了仓库名、BAT 文件名和启动器名称以兼容现有安装；Gateway 现在也支持 Clash、Mihomo、Clash Verge Rev 等提供本地 SOCKS5 或 mixed inbound 的客户端。

默认应用仍然是 ChatGPT / Codex。现在也可以在设置中通过 `.exe` 路径添加其他 Windows 应用，并将其中任意一个设为默认应用。

## 日常启动

双击 **Codex Gateway - v2rayN** 或运行：

```bat
Codex-v2rayN.bat
```

启动后会显示一个简短的等待入口，默认时长为 2 秒：

```text
[S] Settings    [Enter] Launch now
Auto launch in 2 seconds...
```

- 等待期间按 `S`：进入设置模式。
- 等待期间按 `Enter`：跳过等待，立即启动默认应用。
- 不按任何键：倒计时结束后自动启动默认应用。
- 非交互终端无法读取快捷键时：直接启动，不额外等待。

平时无需选择应用。Gateway 会记住默认应用，只有按 `S` 或主动运行 `--settings` 时才进入设置。

## 终端界面

Gateway 使用可重绘的自适应居中面板：宽窗口中保持紧凑的信息宽度，窄窗口中自动缩小。调整 Windows Terminal 的窗口宽度后，当前画面会按新宽度重新排版，而不是停留在输出时的位置。启动快捷键等待页和错误关闭页会即时响应缩放；检查或启动期间会在下一条状态更新时响应；设置输入期间也会持续检测缩放。标题、代理路由摘要和最终状态居中；步骤、路径与设置项在面板内部左对齐，便于快速扫描。中文全角字符会按双列宽度计算，因此中英文切换不会造成标题偏移或边框错位。

界面只使用 Windows 终端自带颜色和 Unicode 线条，不包含动画，也不需要字体或其他第三方依赖。若旧版控制台无法显示 Unicode 线条，建议使用 Windows Terminal 或 Windows 11 默认终端。

## 设置模式

可以在启动等待期间按 `S`，也可以直接运行：

```bat
Codex-v2rayN.bat --settings
```

设置界面支持：

- 通过数字将某个应用设为默认应用。
- 按 `A`，通过 `.exe` 文件路径添加应用。
- 按 `E`，修改自定义应用的名称、路径、参数或工作目录。
- 按 `D`，删除自定义应用。
- 按 `L`，在简体中文与 English 之间切换界面语言。
- 按 `T`，设置启动等待时长，单位为秒；允许 `0`–`60`，`0` 表示立即启动。
- 按 `P`，在自动检测代理端口与手动指定端口之间切换。
- 按 `Enter`，保存设置并启动当前默认应用。
- 按 `Q`，保存设置并退出，不启动应用。

内建的 `ChatGPT / Codex` Profile 不可删除。自定义应用配置保存在：

```text
%LOCALAPPDATA%\CodexGateway\apps.json
```

每次覆盖配置前会保留一个 `apps.json.bak`。配置与项目脚本分离，因此解压或升级 Gateway 不会覆盖用户的应用列表。

等待时长也保存在这个配置文件中。旧版 `apps.json` 没有该字段时会自动采用 2 秒，无需手动迁移。设置为 `0` 后仍可通过 `Codex-v2rayN.bat --settings` 再次进入设置。

## 语言选择

Gateway 内置两种界面语言：

- 简体中文：`zh-CN`
- English：`en-US`

首次运行跟随 Windows UI 语言；非中文系统默认使用 English。进入设置后按 `L` 可随时切换，选择会写入 `apps.json`，之后启动自动沿用，不会每次询问。

启动快捷键、设置菜单、三阶段状态、成功提示和主要错误原因都会随语言切换。包名、路径、协议名和底层 Windows/PowerShell 异常保留原始技术文本，方便排查。

## 添加自定义应用

在设置中按 `A`，然后粘贴 `.exe` 的完整路径。路径可以包含空格、括号和非 ASCII 字符，也可以把 EXE 文件拖入终端窗口。

每个自定义应用可以保存：

- 显示名称；
- executable 路径；
- 可选启动参数；
- 可选工作目录，留空时使用 executable 所在目录。

Gateway 会在启动前确认文件和工作目录确实存在，通过 `Get-CimInstance Win32_Process` 检查相同 executable 是否已经运行，并在启动后确认匹配的进程真正出现。

已有实例无法继承本次创建的代理环境，因此检测到相同应用正在运行时，Gateway 会要求先关闭它，而不会复用现有进程。

## 可选代理参数占位符

有些应用会读取 `ALL_PROXY`、`HTTP_PROXY` 和 `HTTPS_PROXY`；有些应用则需要自己的命令行代理参数。自定义应用的启动参数支持：

| 占位符 | 示例结果 |
|---|---|
| `{proxy_host}` | `127.0.0.1` |
| `{proxy_port}` | `10808` |
| `{socks_proxy}` | `socks5://127.0.0.1:10808` |
| `{http_proxy}` | `http://127.0.0.1:10808` |

示例：

```text
--proxy-server={socks_proxy}
```

Gateway 会在启动前使用实际检测到的 endpoint 替换这些占位符。参数内容不会显示在正常启动界面，也不会写入日志。不要把密码、token 或其他秘密直接写入应用参数配置。

环境变量和命令行参数是否生效最终取决于目标应用自身的代理支持；Gateway 不会注入或修改第三方应用代码。

## ChatGPT / Codex 自动选择

内建 Codex Profile 保留原有动态逻辑：

1. 默认优先查询 `OpenAI.CodexBeta`。
2. Beta 未安装时自动回退 `OpenAI.Codex` Stable。
3. 使用 `Get-AppxPackage` 获取当前包，不绑定版本目录。
4. 优先从 AppX Manifest 获取真实 executable。
5. Manifest 不可用时检查 `app\ChatGPT (Beta).exe` 或 `app\ChatGPT.exe` fallback。

`GatewayConfig.ps1` 中的 `AppPreference` 支持：

| 值 | 行为 |
|---|---|
| `PreferBeta` | Beta 优先，不存在时使用 Stable。 |
| `PreferStable` | Stable 优先，不存在时使用 Beta。 |
| `BetaOnly` | 只允许 Beta。 |
| `StableOnly` | 只允许 Stable。 |

## 只检查，不启动

```bat
Codex-v2rayN.bat --check
```

`--check` 不显示启动快捷键入口，也不会启动应用。它检查：

- v2rayN SOCKS5 handshake；
- 通过 SOCKS5 到配置的 HTTPS 健康检查地址；
- 当前默认应用配置；
- AppX 包或自定义 executable；
- executable 和工作目录是否存在。

OpenAI 健康检查返回 HTTP `401` 或 `403` 仍代表代理、TLS 和目标服务器可达；Gateway 不发送 API key、token 或 cookie。

## 代理作用域

mixed inbound 默认设置：

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

这些变量只存在于 Gateway PowerShell 进程及它启动的子进程中。项目不使用 `setx`，不修改 Windows 系统代理，不写注册表代理配置，也不会影响其他终端或应用。

## Endpoint 自动发现

Gateway 按以下顺序查找本地 endpoint：

1. 从运行中的 `v2rayN.exe`、`sing-box` 或 `xray` 定位 v2rayN 根目录。
2. 检查 `binConfigs\config.json` runtime inbound。
3. 检查 `guiConfigs\guiNConfig.json` GUI inbound。
4. 检查 Mihomo/Clash YAML 或 JSON 中的顶层 `mixed-port` 与 `socks-port`。
5. 识别 Clash、Mihomo、Clash Verge 相关进程；运行时探测少量常用端口 `7890`、`7891`、`7897`、`7898`。
6. 检查当前 Gateway 进程继承到的 loopback `ALL_PROXY`、`HTTPS_PROXY` 或 `HTTP_PROXY`，仅接受通过 SOCKS5 握手的端口。
7. 使用 `GatewayConfig.ps1` 中的 fallback：`127.0.0.1:10808`。

候选地址只接受 loopback。Gateway 会执行真实 SOCKS5 handshake，并探测同一端口是否支持 HTTP CONNECT，以识别 mixed inbound。

默认使用自动检测。设置界面按 `P` 后可以输入 `1`–`65535` 之间的端口，将 Gateway 固定到 `127.0.0.1:<端口>`；输入 `auto` 可恢复自动检测。手动模式不会在失败时偷偷回退到其他端口，因此报错中的地址就是实际检查的地址。

自动检测并不是扫描全部 65535 个端口。Gateway 会读取客户端已经配置的 inbound，或在识别到相关进程后探测一小组常用端口，再逐个执行 SOCKS5 handshake。这种方式更快，也避免误连到无关的本地服务。

Mihomo 官方配置中，`mixed-port` 同时支持 HTTP(S) 与 SOCKS5，`socks-port` 提供 SOCKS5。Gateway 当前要求目标端口至少支持 SOCKS5；只有 `port`（纯 HTTP）而没有 SOCKS/mixed inbound 的配置不会被选中。

## 可调整配置

`GatewayConfig.ps1` 包含少量管理员级配置：

```powershell
AppPreference        = 'PreferBeta'
DefaultProxyHost     = '127.0.0.1'
DefaultProxyPort     = 10808
LaunchTimeoutSeconds = 15
```

一般用户不需要编辑该文件。应用列表和默认应用请通过设置界面管理。

## 安装启动器

桌面快捷方式：

```bat
Install-Launcher.bat
```

开始菜单快捷方式：

```bat
Install-Launcher.bat --start-menu
```

快捷方式名仍为 **Codex Gateway - v2rayN**，目标始终是当前目录中的 `Codex-v2rayN.bat`，不会绑定某个具体应用或 executable。

卸载桌面快捷方式：

```bat
Install-Launcher.bat --uninstall
```

卸载开始菜单快捷方式：

```bat
Install-Launcher.bat --start-menu --uninstall
```

卸载快捷方式不会删除应用配置、日志、项目、v2rayN 或任何目标应用。

## 文件结构

| 文件 | 职责 |
|---|---|
| `Codex-v2rayN.bat` | 薄入口：处理 `--check`、`--settings` 并调用 PowerShell。 |
| `Launch-CodexApp.ps1` | 快捷键入口、设置 UI、三阶段检查、启动与日志。 |
| `AppProfileSupport.ps1` | 用户应用配置、路径解析、自定义进程识别和参数占位符。 |
| `LocalizationSupport.ps1` | 语言检测、UTF-8 locale 加载和文本格式化。 |
| `locales\zh-CN.json` | 简体中文界面资源。 |
| `locales\en-US.json` | English 界面资源。 |
| `AppSupport.ps1` | Codex AppX、Manifest 和 WindowsApps 进程识别。 |
| `GatewayConfig.ps1` | endpoint、超时和 Codex 策略。 |
| `Resolve-v2rayNProxy.ps1` | 自动解析 v2rayN endpoint。 |
| `ProxySupport.ps1` | SOCKS5、mixed 和 TLS 检查。 |
| `Install-Launcher.bat/.ps1` | 安装与卸载快捷方式。 |
| `VERSION` | Gateway 版本。 |
| `assets\` | 图标资源。 |
| `tests\` | PowerShell 回归测试。 |

## 日志

```text
logs\gateway-YYYY-MM-DD.log
```

日志记录版本、模式、默认应用名称和类型、endpoint、最终 executable、启动结果和错误信息。不会记录完整环境变量、应用参数内容、token、API key、cookie 或密码。

## 常见问题

### v2rayN 未启动或端口改变

先启动 v2rayN 并确认 core 正常。Gateway 会自动读取运行配置；无法定位配置时使用 `GatewayConfig.ps1` 中的 fallback。错误会显示实际 endpoint 和检测来源。

### 应用已经运行

完全关闭该应用的现有实例再重试。已运行的进程无法继承本次 Gateway 环境，所以不会被直接复用。

### 自定义应用启动了但没有使用代理

确认目标应用是否支持 `ALL_PROXY`、`HTTP_PROXY` 或 `HTTPS_PROXY`。如果它要求自己的代理参数，请在设置中加入 `{socks_proxy}` 或 `{http_proxy}` 占位符。部分应用可能完全忽略环境变量和命令行代理选项。

### 自定义 EXE 被移动或卸载

启动时会显示不存在的实际路径。按 `S` 进入设置，使用 `E` 更新路径，或使用 `D` 删除该应用。

### 用户应用配置损坏

配置错误会显示 `%LOCALAPPDATA%\CodexGateway\apps.json` 的具体原因。可以恢复同目录的 `apps.json.bak`；也可以删除损坏的 JSON，让 Gateway 回到默认 Codex Profile。

### Beta 和 Stable 都未安装

内建 Codex Profile 会返回 AppX 错误。可以安装 `OpenAI.CodexBeta`/`OpenAI.Codex`，或者按 `S` 添加其他 EXE 并设为默认应用。

## Exit code

| Code | 含义 |
|---:|---|
| `0` | 启动、检查或设置退出成功。 |
| `1` | endpoint 或 SOCKS5 handshake 失败。 |
| `2` | Codex AppX 包不可用。 |
| `3` | executable 或工作目录不可用。 |
| `4` | 应用已经运行，或无法安全检查进程。 |
| `5` | `Start-Process` 失败。 |
| `6` | 启动后未观察到目标进程。 |
| `7` | HTTPS 健康检查失败。 |
| `8` | 日志不可写。 |
| `9` | Gateway 管理配置无效。 |
| `10` | 未预期错误。 |
| `11` | 用户应用 JSON 配置无效。 |
| `64` | BAT 参数错误。 |
