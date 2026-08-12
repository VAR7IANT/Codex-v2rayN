@echo off
setlocal EnableExtensions
title Codex Gateway - v2rayN

:: Use UTF-8 and a calm cyan-on-black console theme.
chcp 65001 >nul
color 0B

:: ------------------------------------------------------------------
:: Configuration
:: ------------------------------------------------------------------
set "DEFAULT_PROXY_HOST=127.0.0.1"
set "DEFAULT_PROXY_PORT=10808"

:: Detect the active v2rayN endpoint from its running portable/install path.
for /f "tokens=1-3 delims=|" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resolve-v2rayNProxy.ps1" -DefaultHost "%DEFAULT_PROXY_HOST%" -DefaultPort %DEFAULT_PROXY_PORT%') do (
    set "PROXY_HOST=%%a"
    set "PROXY_PORT=%%b"
    set "PROXY_SOURCE=%%c"
)

if not defined PROXY_HOST set "PROXY_HOST=%DEFAULT_PROXY_HOST%"
if not defined PROXY_PORT set "PROXY_PORT=%DEFAULT_PROXY_PORT%"
if not defined PROXY_SOURCE set "PROXY_SOURCE=default fallback"
set "PROXY_URL=socks5://%PROXY_HOST%:%PROXY_PORT%"

call :render_header

:: ------------------------------------------------------------------
:: 1. Check the local v2rayN SOCKS5 endpoint.
:: ------------------------------------------------------------------
call :step "1/3" "Checking the v2rayN proxy"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$client = [Net.Sockets.TcpClient]::new(); try { $task = $client.ConnectAsync('%PROXY_HOST%', %PROXY_PORT%); if (-not $task.Wait(1500) -or -not $client.Connected) { exit 1 } } catch { exit 1 } finally { $client.Dispose() }"

if errorlevel 1 (
    call :error "v2rayN proxy is not available." "Start v2rayN and verify SOCKS5 port %PROXY_PORT%, then try again."
    exit /b 1
)

call :success "Proxy online at %PROXY_HOST%:%PROXY_PORT%"

:: Apply the proxy only to this process tree.
set "ALL_PROXY=%PROXY_URL%"
set "all_proxy=%PROXY_URL%"

:: Avoid stale HTTP proxy values interfering with this launch.
set "HTTP_PROXY="
set "HTTPS_PROXY="
set "http_proxy="
set "https_proxy="

:: ------------------------------------------------------------------
:: 2. Locate the newest installed Codex Windows app package.
:: ------------------------------------------------------------------
call :step "2/3" "Finding the Codex Windows app"

for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$package = Get-AppxPackage OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1; if ($package) { $package.InstallLocation }"`) do (
    set "CODEX_DIR=%%i"
)

:: Restricted shells may not expose AppX registration. If Codex is already
:: running, its executable path provides a safe read-only fallback.
if not defined CODEX_DIR (
    for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$items = Get-Process ChatGPT -ErrorAction SilentlyContinue; foreach ($item in $items) { try { if ($item.Path -like '*OpenAI.Codex_*\app\ChatGPT.exe') { Split-Path (Split-Path $item.Path -Parent) -Parent; break } } catch {} }"`) do (
        set "CODEX_DIR=%%i"
    )
)

if not defined CODEX_DIR (
    call :error "OpenAI Codex was not found." "Install or repair the Codex Windows app, then try again."
    exit /b 1
)

set "CODEX_EXE=%CODEX_DIR%\app\ChatGPT.exe"

if not exist "%CODEX_EXE%" (
    call :error "The Codex executable is missing." "%CODEX_EXE%"
    exit /b 1
)

call :success "Codex installation found"

:: Optional non-launching health check for troubleshooting and validation.
if /i "%~1"=="--check" (
    color 0A
    echo   +----------------------------------------------------------------------+
    echo   ^|  CHECK COMPLETE                                                      ^|
    echo   ^|  The proxy and Codex installation are ready. Nothing was launched.   ^|
    echo   +----------------------------------------------------------------------+
    echo.
    exit /b 0
)

:: ------------------------------------------------------------------
:: 3. Launch Codex with the temporary proxy environment.
:: ------------------------------------------------------------------
call :step "3/3" "Starting a private Codex session"

:: A running instance cannot inherit this launcher's temporary environment.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$items = Get-Process ChatGPT -ErrorAction SilentlyContinue; foreach ($item in $items) { try { if ($item.Path -like '*OpenAI.Codex_*\app\ChatGPT.exe') { exit 1 } } catch {} }; exit 0"

if errorlevel 1 (
    call :error "Codex is already running." "Close every Codex window first so the new session can inherit the proxy."
    exit /b 1
)

start "" "%CODEX_EXE%"

if errorlevel 1 (
    call :error "Windows could not start Codex." "Try repairing the Codex app and launch again."
    exit /b 1
)

color 0A
echo        [OK] Codex process started
echo.
echo   +----------------------------------------------------------------------+
echo   ^|  READY                                                               ^|
echo   ^|  Codex is running through v2rayN. Windows proxy settings are safe.   ^|
echo   +----------------------------------------------------------------------+
echo.
timeout /t 3 /nobreak >nul
exit /b 0


:: ------------------------------------------------------------------
:: UI helpers
:: ------------------------------------------------------------------
:render_header
cls
echo.
echo   +----------------------------------------------------------------------+
echo   ^|                                                                      ^|
echo   ^|   CODEX GATEWAY                                                      ^|
echo   ^|   Private route through v2rayN                                       ^|
echo   ^|                                                                      ^|
echo   +----------------------------------------------------------------------+
echo.
echo     ENDPOINT       %PROXY_URL%
echo     DETECTED FROM  %PROXY_SOURCE%
echo     SESSION SCOPE  Current launch only
echo     WINDOWS PROXY  Unchanged
echo.
echo   ------------------------------------------------------------------------
echo.
exit /b 0

:step
echo   [%~1] %~2...
exit /b 0

:success
echo        [OK] %~1
echo.
exit /b 0

:error
color 0C
echo        [FAILED]
echo.
echo   +----------------------------------------------------------------------+
echo   ^|  LAUNCH STOPPED                                                      ^|
echo   +----------------------------------------------------------------------+
echo.
echo     %~1
echo     %~2
echo.
pause
exit /b 0
