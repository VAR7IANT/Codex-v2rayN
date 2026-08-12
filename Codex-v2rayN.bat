@echo off
setlocal EnableExtensions
title Codex via v2rayN

:: UTF-8
chcp 65001 >nul

:: -------- Configuration --------
set "PROXY_HOST=127.0.0.1"
set "PROXY_PORT=10808"
set "PROXY_URL=socks5://%PROXY_HOST%:%PROXY_PORT%"

:: -------- UI --------
cls
echo.
echo   ==========================================================
echo                 CODEX  via  v2rayN
echo   ==========================================================
echo.
echo   Proxy : %PROXY_URL%
echo   Mode  : Temporary ^(this launch only^)
echo.

:: -------- Check v2rayN proxy --------
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ok = Test-NetConnection '%PROXY_HOST%' -Port %PROXY_PORT% -InformationLevel Quiet; if (-not $ok) { exit 1 }"

if errorlevel 1 (
    echo   [X] v2rayN proxy is not available on %PROXY_HOST%:%PROXY_PORT%
    echo.
    echo       Please start v2rayN and confirm the SOCKS port.
    echo.
    pause
    exit /b 1
)

echo   [OK] v2rayN proxy is online.

:: -------- Set temporary proxy for this process tree --------
set "ALL_PROXY=%PROXY_URL%"
set "all_proxy=%PROXY_URL%"

:: Avoid stale HTTP proxy values interfering with this launch
set "HTTP_PROXY="
set "HTTPS_PROXY="
set "http_proxy="
set "https_proxy="

:: -------- Locate Codex Windows App --------
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Get-AppxPackage OpenAI.Codex ^| Sort-Object Version -Descending ^| Select-Object -First 1; if ($p) { $p.InstallLocation }"`) do (
    set "CODEX_DIR=%%i"
)

if not defined CODEX_DIR (
    echo   [X] OpenAI Codex Windows App was not found.
    echo.
    echo       Install or repair Codex, then try again.
    echo.
    pause
    exit /b 1
)

set "CODEX_EXE=%CODEX_DIR%\app\ChatGPT.exe"

if not exist "%CODEX_EXE%" (
    echo   [X] Codex executable was not found:
    echo       %CODEX_EXE%
    echo.
    pause
    exit /b 1
)

echo   [OK] Codex found.
echo.
echo   Launching...
echo.

start "" "%CODEX_EXE%"

if errorlevel 1 (
    echo   [X] Failed to launch Codex.
    echo.
    pause
    exit /b 1
)

echo   [OK] Codex launched through v2rayN.
echo.
timeout /t 2 /nobreak >nul
exit /b 0
