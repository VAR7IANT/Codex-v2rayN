@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Codex Gateway - v2rayN
chcp 65001 >nul
color 0B

set "GATEWAY_MODE=Launch"

if "%~1"=="" goto run
if /i "%~1"=="--check" (
    if not "%~2"=="" goto usage
    set "GATEWAY_MODE=Check"
    goto run
)

:usage
color 0C
echo.
echo Usage: %~nx0 [--check]
echo.
exit /b 64

:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-CodexApp.ps1" -Mode "%GATEWAY_MODE%"
set "GATEWAY_EXIT=%ERRORLEVEL%"

if not "%GATEWAY_EXIT%"=="0" (
    echo Press any key to close this window.
    pause >nul
)

exit /b %GATEWAY_EXIT%
