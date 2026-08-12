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
for /f "tokens=1-5 delims=|" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resolve-v2rayNProxy.ps1" -DefaultHost "%DEFAULT_PROXY_HOST%" -DefaultPort %DEFAULT_PROXY_PORT%') do (
    set "PROXY_HOST=%%a"
    set "PROXY_PORT=%%b"
    set "PROXY_KIND=%%c"
    set "PROXY_URI_HOST=%%d"
    set "PROXY_SOURCE=%%e"
)

if not defined PROXY_HOST set "PROXY_HOST=%DEFAULT_PROXY_HOST%"
if not defined PROXY_PORT set "PROXY_PORT=%DEFAULT_PROXY_PORT%"
if not defined PROXY_KIND set "PROXY_KIND=socks"
if not defined PROXY_URI_HOST set "PROXY_URI_HOST=%PROXY_HOST%"
if not defined PROXY_SOURCE set "PROXY_SOURCE=default fallback"
set "PROXY_URL=socks5://%PROXY_URI_HOST%:%PROXY_PORT%"
set "HTTP_PROXY_URL=http://%PROXY_URI_HOST%:%PROXY_PORT%"

:: Apply the proxy only to this process tree.
set "ALL_PROXY=%PROXY_URL%"
set "all_proxy=%PROXY_URL%"

:: A mixed inbound accepts both HTTP and SOCKS on the same port.
if /i "%PROXY_KIND%"=="mixed" (
    set "HTTP_PROXY=%HTTP_PROXY_URL%"
    set "HTTPS_PROXY=%HTTP_PROXY_URL%"
    set "http_proxy=%HTTP_PROXY_URL%"
    set "https_proxy=%HTTP_PROXY_URL%"
    set "PROXY_ENVIRONMENT=SOCKS + HTTP/HTTPS"
) else (
    set "HTTP_PROXY="
    set "HTTPS_PROXY="
    set "http_proxy="
    set "https_proxy="
    set "PROXY_ENVIRONMENT=SOCKS only"
)

:: Keep local callbacks and services off the upstream proxy.
set "NO_PROXY=localhost,127.0.0.1,::1"
set "no_proxy=%NO_PROXY%"

call :render_header

:: ------------------------------------------------------------------
:: 1. Verify that the selected endpoint really speaks SOCKS5.
:: ------------------------------------------------------------------
call :step "1/3" "Verifying the v2rayN SOCKS5 endpoint"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-ProxyEndpoint.ps1" -ProxyHost "%PROXY_HOST%" -Port %PROXY_PORT% >nul 2>&1

if errorlevel 1 (
    call :error "The detected endpoint did not answer as SOCKS5." "Start v2rayN and verify its SOCKS/mixed inbound, then try again."
    exit /b 1
)

call :success "SOCKS5 handshake verified at %PROXY_HOST%:%PROXY_PORT%"

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
    call :step "3/3" "Testing OpenAI HTTPS through v2rayN"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-ProxyEndpoint.ps1" -ProxyHost "%PROXY_HOST%" -Port %PROXY_PORT% -TestUrl "https://api.openai.com/v1/models"
    if errorlevel 1 (
        call :error "The SOCKS5 endpoint is local, but outbound HTTPS failed." "Check the selected v2rayN node, routing rules, and DNS settings."
        exit /b 1
    )
    echo.
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
echo     INBOUND TYPE   %PROXY_KIND%
echo     DETECTED FROM  %PROXY_SOURCE%
echo     ENVIRONMENT    %PROXY_ENVIRONMENT%
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
