@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Launcher.ps1" -Location Desktop
if errorlevel 1 (
    echo.
    echo Failed to create the desktop launcher.
    pause
    exit /b 1
)
echo.
echo The Codex Gateway shortcut is ready on your desktop.
pause
