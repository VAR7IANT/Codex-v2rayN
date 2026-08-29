[CmdletBinding()]
param(
    [string]$DefaultHost = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$DefaultPort = 10808,
    [string]$V2rayNRoot,
    [ValidateSet('Text', 'Object')][string]$OutputFormat = 'Text'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ProxySupport.ps1')
$script:ResolverWarnings = [Collections.Generic.List[string]]::new()

function New-ProxyCandidate {
    param(
        [AllowNull()][string]$Address,
        [AllowNull()]$Port,
        [AllowNull()][string]$Kind,
        [string]$Source
    )

    $normalizedAddress = ConvertTo-LoopbackAddress $Address
    if (-not $normalizedAddress) {
        return $null
    }

    try {
        $normalizedPort = [int]$Port
    } catch {
        return $null
    }

    if ($normalizedPort -lt 1 -or $normalizedPort -gt 65535) {
        return $null
    }

    $normalizedKind = if ($Kind) { $Kind.ToLowerInvariant() } else { 'socks' }
    if ($normalizedKind -notin @('socks', 'mixed')) {
        return $null
    }

    [pscustomobject]@{
        Host = $normalizedAddress
        Port = $normalizedPort
        Kind = $normalizedKind
        UriHost = Format-ProxyUriHost $normalizedAddress
        Source = $Source
    }
}

function Get-RuntimeCandidates {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($inbound in @($config.inbounds)) {
            $kind = if ($inbound.type) { $inbound.type } else { $inbound.protocol }
            $port = if ($inbound.listen_port) { $inbound.listen_port } else { $inbound.port }
            New-ProxyCandidate -Address $inbound.listen -Port $port -Kind $kind -Source 'v2rayN runtime config'
        }
    } catch {
        $script:ResolverWarnings.Add("Could not read runtime config '$ConfigPath': $($_.Exception.Message)")
        return
    }
}

function Get-GuiCandidates {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($inbound in @($config.Inbound)) {
            New-ProxyCandidate -Address $DefaultHost -Port $inbound.LocalPort -Kind $inbound.Protocol -Source 'v2rayN GUI config'
        }
    } catch {
        $script:ResolverWarnings.Add("Could not read GUI config '$ConfigPath': $($_.Exception.Message)")
        return
    }
}

function Find-V2rayNRoot {
    param([string]$ExecutablePath)

    if (-not $ExecutablePath) {
        return $null
    }

    $current = Split-Path -Parent $ExecutablePath
    for ($depth = 0; $depth -lt 6 -and $current; $depth++) {
        if ((Test-Path -LiteralPath (Join-Path $current 'v2rayN.exe')) -or
            (Test-Path -LiteralPath (Join-Path $current 'guiConfigs')) -or
            (Test-Path -LiteralPath (Join-Path $current 'binConfigs'))) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            break
        }
        $current = $parent
    }

    return $null
}

function Get-DetectedRoots {
    if ($V2rayNRoot) {
        if (Test-Path -LiteralPath $V2rayNRoot) {
            return (Resolve-Path -LiteralPath $V2rayNRoot).Path
        }
        $script:ResolverWarnings.Add("The supplied v2rayN root does not exist: $V2rayNRoot")
        return
    }

    $roots = [Collections.Generic.List[string]]::new()
    foreach ($processName in @('v2rayN', 'sing-box', 'xray', 'mihomo')) {
        foreach ($process in @(Get-Process $processName -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending)) {
            $path = $null
            try { $path = $process.Path } catch {
                $script:ResolverWarnings.Add("Could not read the executable path for process $($process.Id) ($processName): $($_.Exception.Message)")
                continue
            }
            $root = Find-V2rayNRoot $path
            if ($root -and -not $roots.Contains($root)) {
                $roots.Add($root)
            }
        }
    }

    return $roots
}

$candidates = [Collections.Generic.List[object]]::new()
foreach ($root in @(Get-DetectedRoots)) {
    foreach ($candidate in @(Get-RuntimeCandidates (Join-Path $root 'binConfigs\config.json'))) {
        if ($candidate) { $candidates.Add($candidate) }
    }
    foreach ($candidate in @(Get-GuiCandidates (Join-Path $root 'guiConfigs\guiNConfig.json'))) {
        if ($candidate) { $candidates.Add($candidate) }
    }
}

$fallbackHost = ConvertTo-LoopbackAddress $DefaultHost
if (-not $fallbackHost) { $fallbackHost = '127.0.0.1' }
$fallback = New-ProxyCandidate -Address $fallbackHost -Port $DefaultPort -Kind 'socks' -Source 'default fallback'
$candidates.Add($fallback)

$uniqueCandidates = @($candidates | Group-Object Host, Port | ForEach-Object { $_.Group[0] })
$selected = $uniqueCandidates | Where-Object {
    Test-Socks5Handshake -ProxyHost $_.Host -Port $_.Port -TimeoutMilliseconds 700
} | Select-Object -First 1

if ($selected) {
    $selected.Kind = if (Test-HttpProxyHandshake -ProxyHost $selected.Host -Port $selected.Port) { 'mixed' } else { 'socks' }
    $selected.Source += ' (active)'
} elseif ($uniqueCandidates.Count -gt 0) {
    $selected = $uniqueCandidates[0]
    $selected.Source += ' (inactive)'
}

$selected | Add-Member -NotePropertyName Warnings -NotePropertyValue @($script:ResolverWarnings) -Force

if ($OutputFormat -eq 'Object') {
    return $selected
}

'{0}|{1}|{2}|{3}|{4}' -f $selected.Host, $selected.Port, $selected.Kind, $selected.UriHost, $selected.Source
