@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Install Codex Gateway - v2rayN
chcp 65001 >nul

set "INSTALL_LOCATION=Desktop"
set "UNINSTALL_ARGUMENT="

if "%~1"=="" goto run

if /i "%~1"=="--uninstall" (
    if not "%~2"=="" goto usage
    set "UNINSTALL_ARGUMENT=-Uninstall"
    goto run
)

if /i "%~1"=="--start-menu" (
    set "INSTALL_LOCATION=StartMenu"
    if "%~2"=="" goto run
    if /i "%~2"=="--uninstall" if "%~3"=="" (
        set "UNINSTALL_ARGUMENT=-Uninstall"
        goto run
    )
)

:usage
echo.
echo Usage: %~nx0 [--start-menu] [--uninstall]
echo.
exit /b 64

:run
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Launcher.ps1" -Location "%INSTALL_LOCATION%" %UNINSTALL_ARGUMENT%
set "INSTALL_EXIT=%ERRORLEVEL%"

if not "%INSTALL_EXIT%"=="0" (
    echo.
    echo Failed to update the Codex Gateway launcher. Exit code: %INSTALL_EXIT%
    pause
    exit /b %INSTALL_EXIT%
)

echo.
if defined UNINSTALL_ARGUMENT (
    echo Codex Gateway launcher removal completed.
) else (
    echo Codex Gateway launcher installation completed.
)
pause
exit /b 0
