$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexGatewayUiTests-' + [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $tempRoot 'apps.json'

try {
    $output = @('L', '1', '', 'Q') |
        & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $projectRoot 'Launch-CodexApp.ps1') -Mode Settings -UserAppsPath $configPath 2>&1 |
        Out-String

    if ($LASTEXITCODE -ne 0) { throw "Settings UI process returned $LASTEXITCODE." }
    $lines = @($output -split '\r?\n')
    $titleLine = $lines | Where-Object { $_.Trim() -eq 'CODEX GATEWAY' } | Select-Object -First 1
    if (-not $titleLine -or ($titleLine.Length - $titleLine.TrimStart().Length) -lt 3) { throw 'Gateway title was not centered.' }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -in @('L', '1', 'Q')) { continue }
        if ($line -notmatch '^\s{2,}') { throw "Output escaped the centered panel: $line" }
    }
    $firstInputIndex = [Array]::IndexOf($lines, 'L')
    if ($firstInputIndex -gt 0) {
        foreach ($line in @($lines[0..($firstInputIndex - 1)])) {
            if ($line.Length -gt 80) { throw "English UI line exceeded the centered panel width: $line" }
        }
    }
    if ($output -notmatch 'CODEX GATEWAY SETTINGS') { throw 'English settings title was not rendered.' }
    if ($output -notmatch '\[P\].*Proxy port') { throw 'Proxy menu was not rendered.' }
    if ($output -match '\+[-]+\+') { throw 'Legacy ASCII box layout was rendered.' }

    $stored = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($stored.Language -ne 'zh-CN') { throw 'UI language selection was not persisted.' }

    $stored.Language = 'en-US'
    $stored.ProxyPortOverride = 1
    $failureJson = $stored | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath, $failureJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $failureOutput = @('x') |
        & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $projectRoot 'Launch-CodexApp.ps1') -Mode Check -UserAppsPath $configPath -PauseOnError 2>&1 |
        Out-String
    if ($LASTEXITCODE -ne 1) { throw "Failure UI process returned $LASTEXITCODE instead of 1." }
    if ($failureOutput -notmatch 'GATEWAY STOPPED') { throw 'Centered failure panel was not rendered.' }
    if ($failureOutput -notmatch 'Press any key to close this window') { throw 'Centered close prompt was not rendered by PowerShell.' }
    foreach ($line in @($failureOutput -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -eq 'x') { continue }
        if ($line -notmatch '^\s{2,}') { throw "Failure output escaped the centered panel: $line" }
        if ($line.Length -gt 80) { throw "Failure output exceeded the centered panel width: $line" }
    }

    . (Join-Path $projectRoot 'Launch-CodexApp.ps1')
    $script:testConsoleWidth = 100
    function Get-UiConsoleWidth { return $script:testConsoleWidth }
    function Test-UiInteractive { return $true }
    $resizeOutput = & {
        Start-UiFrame
        Write-UiLine -Text 'RESIZE-MARKER' -Color White
        $script:testConsoleWidth = 60
        if (-not (Sync-UiLayout)) { throw 'A console width change did not trigger a UI redraw.' }
    } 6>&1 | Out-String
    $markerLines = @($resizeOutput -split '\r?\n' | Where-Object { $_ -match 'RESIZE-MARKER' })
    if ($markerLines.Count -ne 2) { throw "Expected the retained UI line to render twice, found $($markerLines.Count)." }
    if (($markerLines[0].Length - $markerLines[0].TrimStart().Length) -ne 12) { throw 'Initial 100-column layout margin was incorrect.' }
    if (($markerLines[1].Length - $markerLines[1].TrimStart().Length) -ne 2) { throw 'Resized 60-column layout was not recentered.' }
    if ($script:UiFrame.Count -ne 1) { throw 'Responsive redraw duplicated retained UI records.' }

    Write-Host 'All centered terminal UI tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
