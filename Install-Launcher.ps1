[CmdletBinding()]
param(
    [ValidateSet('Desktop', 'StartMenu')]
    [string]$Location = 'Desktop',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$gatewayPath = Join-Path $projectRoot 'Codex-v2rayN.bat'
$iconPath = Join-Path $projectRoot 'assets\Codex-v2rayN.ico'
$shortcutName = 'Codex Gateway - v2rayN.lnk'
$destination = if ($Location -eq 'StartMenu') {
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
} else {
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
}
$shortcutPath = Join-Path $destination $shortcutName

if ([string]::IsNullOrWhiteSpace($destination) -or -not (Test-Path -LiteralPath $destination -PathType Container)) {
    throw "The $Location shortcut directory is unavailable: $destination"
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host 'Launcher shortcut removed:' -ForegroundColor Green
        Write-Host $shortcutPath
    } else {
        Write-Host 'Launcher shortcut is not installed:' -ForegroundColor Cyan
        Write-Host $shortcutPath
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $gatewayPath -PathType Leaf)) {
    throw "Gateway entry point not found: $gatewayPath"
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    throw "Launcher icon not found: $iconPath"
}

$shell = $null
$shortcut = $null
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $env:ComSpec
    $shortcut.Arguments = '/d /c ""{0}""' -f $gatewayPath
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Description = 'Launch the default Gateway application with a session-only v2rayN proxy'
    $shortcut.WindowStyle = 1
    $shortcut.Save()
} finally {
    if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
    throw "The shortcut was not created: $shortcutPath"
}

Write-Host 'Launcher shortcut created:' -ForegroundColor Green
Write-Host $shortcutPath
Write-Host 'Target gateway:' -ForegroundColor Cyan
Write-Host $gatewayPath
