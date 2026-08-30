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
$authServerProcess = $null
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Assert-Equal '127.0.0.1' (ConvertTo-LoopbackAddress '0.0.0.0') 'Wildcard IPv4 normalization failed.'
    Assert-Equal '::1' (ConvertTo-LoopbackAddress '::1') 'IPv6 loopback normalization failed.'
    Assert-Equal '[::1]' (Format-ProxyUriHost '::1') 'IPv6 URI formatting failed.'
    Assert-Equal $null (ConvertTo-LoopbackAddress '192.168.1.20') 'Non-loopback address was accepted.'

    $activePort = Get-FreePort
    do {
        $closedPort = Get-FreePort
    } while ($closedPort -eq $activePort)
    $serverScript = Join-Path $PSScriptRoot 'Mock-Socks5Server.ps1'
    $serverProcess = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serverScript`"", '-Port', $activePort, '-MaxConnections', 100
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

    $authPort = Get-FreePort
    $authReadyPath = Join-Path $tempRoot 'auth-server.ready'
    $authServerProcess = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serverScript`"", '-Port', $authPort,
        '-MaxConnections', 2, '-AuthenticationMethod', 2, '-ReadyPath', "`"$authReadyPath`""
    ) -WindowStyle Hidden -PassThru
    for ($attempt = 0; $attempt -lt 30 -and -not (Test-Path -LiteralPath $authReadyPath); $attempt++) {
        Start-Sleep -Milliseconds 100
    }
    Assert-Equal $true (Test-Path -LiteralPath $authReadyPath) 'Authentication mock server did not start.'
    Assert-Equal $false (Test-Socks5Handshake -ProxyHost '127.0.0.1' -Port $authPort) 'Unsupported SOCKS5 authentication method was accepted.'
    try {
        Test-HttpsThroughSocks5 -ProxyHost '127.0.0.1' -Port $authPort -TargetHost 'example.com' -TimeoutMilliseconds 1000 | Out-Null
        throw 'HTTPS probe accepted an unsupported SOCKS5 authentication method.'
    } catch {
        if ($_.Exception.Message -notmatch 'unsupported SOCKS5 authentication method') {
            throw
        }
    }

    $runtimeRoot = Join-Path $tempRoot 'runtime'
    Write-JsonConfig (Join-Path $runtimeRoot 'binConfigs\config.json') @{
        inbounds = @(
            @{ protocol = 'socks'; listen = '127.0.0.1'; port = $closedPort },
            @{ type = 'mixed'; listen = '0.0.0.0'; listen_port = $activePort }
        )
    }

    $resolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $runtimeRoot -SkipMihomoDiscovery
    $parts = $resolved -split '\|', 5
    Assert-Equal '127.0.0.1' $parts[0] 'Resolver selected the wrong host.'
    Assert-Equal ([string]$activePort) $parts[1] 'Resolver did not skip the inactive first inbound.'
    Assert-Equal 'mixed' $parts[2] 'Resolver selected the wrong inbound type.'
    Assert-Equal '127.0.0.1' $parts[3] 'Resolver produced the wrong URI host.'
    if ($parts[4] -notmatch '\(active\)$') { throw 'Resolver did not label the active endpoint.' }

    $manualResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $runtimeRoot -DefaultPort $activePort -OverridePort $closedPort
    $manualParts = $manualResolved -split '\|', 5
    Assert-Equal ([string]$closedPort) $manualParts[1] 'Manual port did not override automatic candidates.'
    Assert-Equal 'user configured port (inactive)' $manualParts[4] 'Manual port source was not reported.'

    $mihomoRoot = Join-Path $tempRoot 'mihomo'
    $emptyV2rayRoot = Join-Path $tempRoot 'empty-v2rayn'
    New-Item -ItemType Directory -Path $mihomoRoot, $emptyV2rayRoot -Force | Out-Null
    $mihomoConfigPath = Join-Path $mihomoRoot 'config.yaml'
    $mihomoYaml = "mixed-port: $activePort`nsocks-port: $closedPort`nproxy-groups:`n  - name: test`n"
    [IO.File]::WriteAllText($mihomoConfigPath, $mihomoYaml, [Text.UTF8Encoding]::new($false))
    $mihomoResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $emptyV2rayRoot -MihomoConfigPath $mihomoConfigPath -DefaultPort $closedPort
    $mihomoParts = $mihomoResolved -split '\|', 5
    Assert-Equal ([string]$activePort) $mihomoParts[1] 'Resolver did not read the Mihomo mixed-port.'
    Assert-Equal 'mixed' $mihomoParts[2] 'Mihomo mixed-port capability was not detected.'
    Assert-Equal 'Clash/Mihomo config (active)' $mihomoParts[4] 'Mihomo config source was not reported.'

    $savedAllProxy = $env:ALL_PROXY
    try {
        $env:ALL_PROXY = "socks5://127.0.0.1:$activePort"
        Assert-Equal $true (Test-Socks5Handshake -ProxyHost '127.0.0.1' -Port $activePort -TimeoutMilliseconds 300) 'Mock endpoint was unavailable before environment discovery.'
        $environmentResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $emptyV2rayRoot -DefaultPort $closedPort -SkipMihomoDiscovery -OutputFormat Object
        $environmentDiagnostic = "Resolver did not use the active process proxy environment. Source=$($environmentResolved.Source); Warnings=$(@($environmentResolved.Warnings) -join '; ')"
        Assert-Equal $activePort $environmentResolved.Port $environmentDiagnostic
        Assert-Equal 'process proxy environment (active)' $environmentResolved.Source 'Process proxy environment source was not reported.'
    } finally {
        $env:ALL_PROXY = $savedAllProxy
    }

    $fallbackRoot = Join-Path $tempRoot 'fallback'
    Write-JsonConfig (Join-Path $fallbackRoot 'binConfigs\config.json') @{
        inbounds = @(@{ protocol = 'socks'; listen = '127.0.0.1'; port = $closedPort })
    }
    $fallbackResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $fallbackRoot -DefaultPort $activePort -SkipMihomoDiscovery
    $fallbackParts = $fallbackResolved -split '\|', 5
    Assert-Equal ([string]$activePort) $fallbackParts[1] 'Resolver did not try the active default endpoint after stale configuration.'
    Assert-Equal 'default fallback (active)' $fallbackParts[4] 'Resolver did not report the active default fallback source.'

    & (Join-Path $projectRoot 'Test-ProxyEndpoint.ps1') -ProxyHost '127.0.0.1' -Port $activePort | Out-Null
    Assert-Equal $true (Test-HttpProxyHandshake -ProxyHost '127.0.0.1' -Port $activePort) 'Mixed HTTP capability was not detected.'

    $guiRoot = Join-Path $tempRoot 'gui'
    Write-JsonConfig (Join-Path $guiRoot 'guiConfigs\guiNConfig.json') @{
        Inbound = @(@{ Protocol = 'socks'; LocalPort = 23456 })
    }
    $guiResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $guiRoot -DefaultPort $closedPort -SkipMihomoDiscovery
    $guiParts = $guiResolved -split '\|', 5
    Assert-Equal '23456' $guiParts[1] 'GUI fallback port was not read.'
    Assert-Equal 'socks' $guiParts[2] 'GUI fallback protocol was not read.'
    if ($guiParts[4] -notmatch '\(inactive\)$') { throw 'Inactive GUI endpoint was not labeled.' }

    $unsafeRoot = Join-Path $tempRoot 'unsafe'
    Write-JsonConfig (Join-Path $unsafeRoot 'binConfigs\config.json') @{
        inbounds = @(@{ type = 'mixed'; listen = '192.168.1.20'; listen_port = 9999 })
    }
    $unsafeResolved = & (Join-Path $projectRoot 'Resolve-v2rayNProxy.ps1') -V2rayNRoot $unsafeRoot -DefaultPort 34567 -SkipMihomoDiscovery
    $unsafeParts = $unsafeResolved -split '\|', 5
    Assert-Equal '127.0.0.1' $unsafeParts[0] 'Unsafe non-loopback listener was not rejected.'
    Assert-Equal '34567' $unsafeParts[1] 'Resolver did not use the safe fallback.'

    Write-Host 'All proxy resolver and SOCKS5 protocol tests passed.' -ForegroundColor Green
} finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }
    if ($authServerProcess -and -not $authServerProcess.HasExited) {
        Stop-Process -Id $authServerProcess.Id -Force
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
