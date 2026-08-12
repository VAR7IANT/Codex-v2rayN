$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'ProxySupport.ps1')

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
}

function Write-JsonConfig {
    param([string]$Path, $Value)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexGatewayTests-' + [guid]::NewGuid().ToString('N'))
$serverProcess = $null
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Assert-Equal '127.0.0.1' (ConvertTo-LoopbackAddress '0.0.0.0') 'Wildcard IPv4 normalization failed.'
    Assert-Equal '::1' (ConvertTo-LoopbackAddress '::1') 'IPv6 loopback normalization failed.'
    Assert-Equal '[::1]' (Format-ProxyUriHost '::1') 'IPv6 URI formatting failed.'
    Assert-Equal $null (ConvertTo-LoopbackAddress '192.168.1.20') 'Non-loopback address was accepted.'

    $activePort = Get-FreePort
    $closedPort = Get-FreePort
    $serverScript = Join-Path $PSScriptRoot 'Mock-Socks5Server.ps1'
    $serverProcess = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serverScript`"", '-Port', $activePort, '-MaxConnections', 10
    ) -WindowStyle Hidden -PassThru

    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (Test-Socks5Handshake -ProxyHost '127.0.0.1' -Port $activePort -TimeoutMilliseconds 300) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    Assert-Equal $true $ready 'Mock SOCKS5 server did not start.'
    Assert-Equal $true (Test-HttpProxyHandshake -ProxyHost '127.0.0.1' -Port $activePort -Verbose) 'Mock mixed HTTP capability did not start.'

    $runtimeRoot = Join-Path $tempRoot 'runtime'
    Write-JsonConfig (Join-Path $runtimeRoot 'binConfigs\config.json') @{
        inbounds = @(
            @{ protocol = 'socks'; listen = '127.0.0.1'; port = $closedPort },
            @{ type = 'mixed'; listen = '0.0.0.0'; listen_port = $activePort }
        )
    }

    $resolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $runtimeRoot
    $parts = $resolved -split '\|', 5
    Assert-Equal '127.0.0.1' $parts[0] 'Resolver selected the wrong host.'
    Assert-Equal ([string]$activePort) $parts[1] 'Resolver did not skip the inactive first inbound.'
    Assert-Equal 'mixed' $parts[2] 'Resolver selected the wrong inbound type.'
    Assert-Equal '127.0.0.1' $parts[3] 'Resolver produced the wrong URI host.'
    if ($parts[4] -notmatch '\(active\)$') { throw 'Resolver did not label the active endpoint.' }

    & (Join-Path $projectRoot 'Test-ProxyEndpoint.ps1') -ProxyHost '127.0.0.1' -Port $activePort | Out-Null
    Assert-Equal $true (Test-HttpProxyHandshake -ProxyHost '127.0.0.1' -Port $activePort) 'Mixed HTTP capability was not detected.'

    $guiRoot = Join-Path $tempRoot 'gui'
    Write-JsonConfig (Join-Path $guiRoot 'guiConfigs\guiNConfig.json') @{
        Inbound = @(@{ Protocol = 'socks'; LocalPort = 23456 })
    }
    $guiResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $guiRoot
    $guiParts = $guiResolved -split '\|', 5
    Assert-Equal '23456' $guiParts[1] 'GUI fallback port was not read.'
    Assert-Equal 'socks' $guiParts[2] 'GUI fallback protocol was not read.'
    if ($guiParts[4] -notmatch '\(inactive\)$') { throw 'Inactive GUI endpoint was not labeled.' }

    $unsafeRoot = Join-Path $tempRoot 'unsafe'
    Write-JsonConfig (Join-Path $unsafeRoot 'binConfigs\config.json') @{
        inbounds = @(@{ type = 'mixed'; listen = '192.168.1.20'; listen_port = 9999 })
    }
    $unsafeResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $unsafeRoot -DefaultPort 34567
    $unsafeParts = $unsafeResolved -split '\|', 5
    Assert-Equal '127.0.0.1' $unsafeParts[0] 'Unsafe non-loopback listener was not rejected.'
    Assert-Equal '34567' $unsafeParts[1] 'Resolver did not use the safe fallback.'

    Write-Host 'All proxy resolver and SOCKS5 protocol tests passed.' -ForegroundColor Green
} finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
