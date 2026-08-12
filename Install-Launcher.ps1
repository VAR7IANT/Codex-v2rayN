[CmdletBinding()]
param(
    [ValidateSet('Desktop', 'Project')]
    [string]$Location = 'Desktop'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcherPath = Join-Path $projectRoot 'Codex-v2rayN.bat'
$iconPath = Join-Path $projectRoot 'assets\Codex-v2rayN.ico'

if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Launcher not found: $launcherPath"
}

if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Icon not found: $iconPath"
}

$destination = if ($Location -eq 'Desktop') {
    [Environment]::GetFolderPath('Desktop')
} else {
    $projectRoot
}

$shortcutPath = Join-Path $destination 'Codex Gateway.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $env:ComSpec
$shortcut.Arguments = '/d /c ""{0}""' -f $launcherPath
$shortcut.WorkingDirectory = $projectRoot
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = 'Launch Codex through the local v2rayN SOCKS5 proxy'
$shortcut.WindowStyle = 1
$shortcut.Save()

Write-Host "Launcher shortcut created:" -ForegroundColor Green
Write-Host $shortcutPath
