# Codex Gateway - v2rayN

当前正式版本：**v1.0.0**。项目版本的唯一来源是根目录中的 `VERSION` 文件，Git release tag 使用相同版本并加 `v` 前缀。

这是一个仅使用 Windows 自带 CMD 与 Windows PowerShell 的轻量 Gateway。它动态寻找当前安装的 ChatGPT / Codex Windows App，并让本次启动的应用进程树通过 v2rayN 访问网络。

默认选择策略是：安装了 `OpenAI.CodexBeta` 时优先启动 Beta；Beta 未安装时自动回退到 `OpenAI.Codex` Stable。项目不绑定 AppX 版本号，也不会修改有问题的 Stable 应用本身。

## 功能

- 动态读取 AppX 包，不依赖 `OpenAI.CodexBeta_26.x.x.x_x64_...` 一类固定目录。
- 优先从 AppX Manifest 获取真实 `Executable`，Manifest 不可用时才检查已知相对路径。
- 正确处理 `ChatGPT (Beta).exe` 中的空格和括号。
- 从运行中的 v2rayN 或其 core 配置自动发现本地 SOCKS/mixed inbound；默认回退为 `127.0.0.1:10808`。
- 启动前完成 SOCKS5 握手、AppX/文件检查和现有进程检查。
- 启动后等待并确认 WindowsApps 中的目标进程真正出现。
- `--check` 模式额外验证通过 SOCKS5 到 OpenAI 的 HTTPS，不启动应用。
- 每日写入轻量日志 `logs\gateway-YYYY-MM-DD.log`。
- 不修改 Windows 系统代理，不永久写入用户或系统环境变量。

## 文件结构

| 文件 | 职责 |
|---|---|
| `Codex-v2rayN.bat` | 最薄入口：解析 `--check` 并调用 PowerShell。 |
| `Launch-CodexApp.ps1` | 三阶段 UI、会话代理环境、健康检查、启动流程与日志。 |
| `GatewayConfig.ps1` | 集中配置 Beta/Stable 策略、fallback endpoint 和超时。 |
| `VERSION` | 项目版本号的唯一来源。 |
| `AppSupport.ps1` | AppX 包选择、Manifest executable 解析、CIM 进程识别与启动验证。 |
| `Resolve-v2rayNProxy.ps1` | 从运行中的 v2rayN/core 配置解析并选择 endpoint。 |
| `ProxySupport.ps1` | SOCKS5、HTTP mixed 探测和 SOCKS5/TLS 健康检查。 |
| `Test-ProxyEndpoint.ps1` | 可单独调用的 endpoint 检查工具。 |
| `Install-Launcher.bat/.ps1` | 安装或卸载桌面/开始菜单快捷方式。 |
| `assets\` | 快捷方式图标。 |
| `tests\` | 无第三方依赖的 PowerShell 测试。 |

## 安装启动器

双击：

```bat
Install-Launcher.bat
```

默认在桌面创建名为 **Codex Gateway - v2rayN** 的快捷方式。快捷方式始终调用当前项目目录中的 `Codex-v2rayN.bat`，不会绑定 Beta 或 Stable 的具体 exe。

如需安装到开始菜单，在命令行运行：

```bat
Install-Launcher.bat --start-menu
```

项目目录移动后，请重新运行安装脚本，以便快捷方式指向新位置。

## 正常启动

1. 启动 v2rayN，并确保本地 SOCKS 或 mixed inbound 可用。
2. 完全关闭已经运行的 ChatGPT / Codex Beta 与 Stable。
3. 双击 **Codex Gateway - v2rayN**，或运行：

```bat
Codex-v2rayN.bat
```

Gateway 会依次显示：

1. `[1/3]` v2rayN SOCKS5 handshake。
2. `[2/3]` 实际选择的 Variant、版本、Package Name 与 Executable。
3. `[3/3]` 现有实例检查、启动和进程出现验证。

## 只检查，不启动

```bat
Codex-v2rayN.bat --check
```

该模式只检查：

- v2rayN SOCKS5 endpoint；
- 通过该 SOCKS5 endpoint 到 OpenAI 的 HTTPS；
- 可用的 AppX 包；
- 最终 executable 是否存在。

HTTP `401`、`403` 或其他有效 HTTP 状态仍代表 HTTPS/TLS 与代理路由可达；健康检查不会发送 token、API key 或 cookie。

## Beta / Stable 选择逻辑

编辑 `GatewayConfig.ps1` 顶部唯一的 `AppPreference` 值：

```powershell
$GatewayConfig = [ordered]@{
    AppPreference = 'PreferBeta'
    # ...
}
```

支持四种策略：

| 值 | 行为 |
|---|---|
| `PreferBeta` | 默认。Beta 已安装则用 Beta，否则用 Stable。 |
| `PreferStable` | Stable 已安装则用 Stable，否则用 Beta。 |
| `BetaOnly` | 只允许 Beta；未安装则停止。 |
| `StableOnly` | 只允许 Stable；未安装则停止。 |

选择完成后，Gateway 通过 `Get-AppxPackage` 获取当前安装位置，通过 AppX Manifest 获取实际 executable。只有 Manifest 无法解析或其中路径不存在时，才使用 `app\ChatGPT (Beta).exe` 或 `app\ChatGPT.exe` fallback。不会写死任何版本目录。

## 代理工作原理

Gateway 在自己的 PowerShell 进程内设置下列环境变量，随后由新启动的 ChatGPT / Codex 子进程继承：

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

当 endpoint 仅支持 SOCKS5 时，只设置 `ALL_PROXY/all_proxy`，并清除 Gateway 当前进程中继承来的 HTTP proxy 变量；当检测为 mixed inbound 时，同一端口同时用于 SOCKS5 与 HTTP/HTTPS。

这些变量的作用域仅限 Gateway 及其新启动的子进程。脚本不调用 Windows 系统代理设置，不使用 `setx`，不写注册表中的用户代理配置，也不会污染其他终端或应用。Gateway 进程退出后，它自身的临时环境随之消失；已启动应用保留启动时继承的副本。

## Endpoint 自动发现

解析顺序如下：

1. 从运行中的 `v2rayN.exe`、`sing-box`、`xray` 或 `mihomo` 反查 v2rayN 根目录。
2. 检查 `binConfigs\config.json` 中的 runtime inbound。
3. 检查 `guiConfigs\guiNConfig.json` 中的 GUI inbound。
4. 使用 `GatewayConfig.ps1` 中的 fallback：`127.0.0.1:10808`。

候选地址只接受本机 loopback。Gateway 会对候选端口执行真实 SOCKS5 handshake，并额外探测是否也支持 HTTP CONNECT，以识别 mixed inbound。

## 日志

日志位于：

```text
logs\gateway-YYYY-MM-DD.log
```

记录启动时间、模式、endpoint、包名、版本、最终 executable、启动/检查结果与错误消息。日志不枚举或记录完整环境变量，也不记录 token、API key、cookie 或密码。`logs\` 已加入 `.gitignore`。

## 常见问题

### ChatGPT / Codex 已在运行怎么办？

完全退出所有 Beta 和 Stable 实例（包括可能仍在后台运行的进程），再运行 Gateway。已有进程无法继承本次创建的代理环境，所以 Gateway 会停止，而不会复用它。

进程识别优先使用 `Get-CimInstance Win32_Process` 的 `ExecutablePath`/`CommandLine` 与 `WindowsApps\OpenAI.CodexBeta_*`、`WindowsApps\OpenAI.Codex_*` 匹配。权限不足导致路径为空时，会对已知应用进程名采用保守检测，并在错误信息中说明识别依据。

### v2rayN 未启动怎么办？

先启动 v2rayN，确认 core 与所选节点正常，再重试。错误会显示实际检测的主机、端口和来源。

### 10808 变化怎么办？

正常情况下 Gateway 会从运行中的 v2rayN 配置自动读取新端口。如果配置路径无法发现，可修改 `GatewayConfig.ps1` 中的：

```powershell
DefaultProxyHost = '127.0.0.1'
DefaultProxyPort = 10808
```

### Beta / Stable 都没安装怎么办？

安装 `OpenAI.CodexBeta` 或 `OpenAI.Codex` Windows App。Gateway 不会下载、修复或替换应用包；选择策略不允许的包也不会被启动。

### Manifest 解析失败怎么办？

Gateway 会在日志中记录 Manifest 错误并检查对应 Variant 的已知路径。如果 fallback 文件也不存在，会显示包名、安装目录、Manifest 候选和最终检查的路径，然后退出。

### `--check` 的 OpenAI HTTPS 失败怎么办？

先确认 `[1/3]` SOCKS5 handshake 已成功，再检查 v2rayN 当前节点、路由规则、DNS 和 TLS 拦截设置。日志中会保留目标 URL、endpoint 和具体异常。

## 卸载启动器

卸载桌面快捷方式：

```bat
Install-Launcher.bat --uninstall
```

卸载开始菜单快捷方式：

```bat
Install-Launcher.bat --start-menu --uninstall
```

这只删除对应的 `.lnk`，不会删除项目文件、日志、v2rayN 或 ChatGPT / Codex。

## Exit code

| Code | 含义 |
|---:|---|
| `0` | 启动或检查成功。 |
| `1` | endpoint 解析或 SOCKS5 handshake 失败。 |
| `2` | AppX 包不可用。 |
| `3` | executable 不存在或无法解析。 |
| `4` | 已有实例，或无法安全完成进程检查。 |
| `5` | `Start-Process` 失败。 |
| `6` | 启动后未观察到目标进程。 |
| `7` | `--check` 的 OpenAI HTTPS 失败。 |
| `8` | 日志目录或文件不可写。 |
| `9` | 配置无效。 |
| `10` | 未预期错误。 |
| `64` | BAT 参数错误。 |
