[CmdletBinding()]
param(
    [string]$DefaultHost = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$DefaultPort = 10808,
    [ValidateRange(1, 65535)][Nullable[int]]$OverridePort,
    [string]$V2rayNRoot,
    [string[]]$MihomoConfigPath = @(),
    [switch]$SkipMihomoDiscovery,
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
    foreach ($processName in @('v2rayN', 'sing-box', 'xray')) {
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

function Get-MihomoConfigCandidates {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return
    }

    try {
        $content = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
        $values = @{}
        if ([IO.Path]::GetExtension($ConfigPath) -ieq '.json') {
            $config = $content | ConvertFrom-Json -ErrorAction Stop
            $values['mixed-port'] = $config.'mixed-port'
            $values['socks-port'] = $config.'socks-port'
        } else {
            foreach ($key in @('mixed-port', 'socks-port')) {
                $pattern = '(?m)^(?:\uFEFF)?' + [regex]::Escape($key) + '\s*:\s*["'']?(?<port>\d{1,5})["'']?\s*(?:#.*)?$'
                $match = [regex]::Match($content, $pattern)
                if ($match.Success) { $values[$key] = $match.Groups['port'].Value }
            }
        }

        foreach ($key in @('mixed-port', 'socks-port')) {
            if ($null -eq $values[$key]) { continue }
            $kind = if ($key -eq 'mixed-port') { 'mixed' } else { 'socks' }
            New-ProxyCandidate -Address $DefaultHost -Port $values[$key] -Kind $kind -Source 'Clash/Mihomo config'
        }
    } catch {
        $script:ResolverWarnings.Add("Could not read Clash/Mihomo config '$ConfigPath': $($_.Exception.Message)")
    }
}

function Get-MihomoConfigPaths {
    $paths = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    function Add-ConfigPath {
        param([AllowNull()][string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
        if (-not [IO.Path]::IsPathRooted($expanded)) { return }
        if ($seen.Add($expanded)) { $paths.Add($expanded) }
    }

    foreach ($path in @($MihomoConfigPath)) { Add-ConfigPath $path }
    Add-ConfigPath $env:CLASH_CONFIG_FILE

    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $roaming = [Environment]::GetFolderPath('ApplicationData')
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    foreach ($path in @(
        (Join-Path $userProfile '.config\mihomo\config.yaml'),
        (Join-Path $userProfile '.config\clash\config.yaml'),
        (Join-Path $roaming 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml'),
        (Join-Path $roaming 'io.github.clash-verge-rev.clash-verge-rev\clash-verge-check.yaml'),
        (Join-Path $roaming 'clash-verge\clash-verge.yaml'),
        (Join-Path $local 'mihomo\config.yaml'),
        (Join-Path $local 'clash\config.yaml')
    )) { Add-ConfigPath $path }

    try {
        foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '(?i)(clash|mihomo|verge)' })) {
            $commandLine = [string]$process.CommandLine
            $executablePath = [string]$process.ExecutablePath
            $processDirectory = if ([string]::IsNullOrWhiteSpace($executablePath)) { $null } else { Split-Path -Parent $executablePath }
            if ($commandLine -match '(?i)(?:^|\s)(?:-f|--config)(?:=|\s+)(?:"([^"]+)"|''([^'']+)''|(\S+))') {
                $configArgument = @($Matches[1], $Matches[2], $Matches[3]) | Where-Object { $_ } | Select-Object -First 1
                if ($configArgument -and -not [IO.Path]::IsPathRooted($configArgument) -and $processDirectory) {
                    $configArgument = Join-Path $processDirectory $configArgument
                }
                Add-ConfigPath $configArgument
            }
            if ($commandLine -match '(?i)(?:^|\s)(?:-d|--dir)(?:=|\s+)(?:"([^"]+)"|''([^'']+)''|(\S+))') {
                $directory = @($Matches[1], $Matches[2], $Matches[3]) | Where-Object { $_ } | Select-Object -First 1
                if ($directory -and -not [IO.Path]::IsPathRooted($directory) -and $processDirectory) {
                    $directory = Join-Path $processDirectory $directory
                }
                if ($directory) { Add-ConfigPath (Join-Path $directory 'config.yaml') }
            }
            if (-not [string]::IsNullOrWhiteSpace($executablePath)) {
                Add-ConfigPath (Join-Path (Split-Path -Parent $executablePath) 'config.yaml')
            }
        }
    } catch {
        $script:ResolverWarnings.Add("Could not inspect Clash/Mihomo process command lines: $($_.Exception.Message)")
    }

    return $paths
}

function Test-MihomoProcessRunning {
    return [bool]@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)(clash|mihomo|verge)' } | Select-Object -First 1)
}

function Get-ActiveEnvironmentProxyCandidates {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('ALL_PROXY', 'all_proxy', 'HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($value) -or -not $seen.Add($value)) { continue }
        try {
            $uri = [uri]$value
            if ($uri.Scheme -notin @('socks', 'socks5', 'socks5h', 'http', 'https')) { continue }
            $proxyHost = ConvertTo-LoopbackAddress $uri.Host
            if (-not $proxyHost -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { continue }
            if (Test-Socks5Handshake -ProxyHost $proxyHost -Port $uri.Port -TimeoutMilliseconds 300) {
                New-ProxyCandidate -Address $proxyHost -Port $uri.Port -Kind 'socks' -Source 'process proxy environment'
            }
        } catch {
            $script:ResolverWarnings.Add("Ignored invalid process proxy setting '$name': $($_.Exception.Message)")
        }
    }
}

$candidates = [Collections.Generic.List[object]]::new()
if ($null -ne $OverridePort) {
    $override = New-ProxyCandidate -Address $DefaultHost -Port $OverridePort -Kind 'socks' -Source 'user configured port'
    if ($override) { $candidates.Add($override) }
} else {
    foreach ($root in @(Get-DetectedRoots)) {
        foreach ($candidate in @(Get-RuntimeCandidates (Join-Path $root 'binConfigs\config.json'))) {
            if ($candidate) { $candidates.Add($candidate) }
        }
        foreach ($candidate in @(Get-GuiCandidates (Join-Path $root 'guiConfigs\guiNConfig.json'))) {
            if ($candidate) { $candidates.Add($candidate) }
        }
    }

    if (-not $SkipMihomoDiscovery) {
        foreach ($configPath in @(Get-MihomoConfigPaths)) {
            foreach ($candidate in @(Get-MihomoConfigCandidates $configPath)) {
                if ($candidate) { $candidates.Add($candidate) }
            }
        }

        if (Test-MihomoProcessRunning) {
            foreach ($commonPort in @(7890, 7891, 7897, 7898)) {
                if (Test-Socks5Handshake -ProxyHost $DefaultHost -Port $commonPort -TimeoutMilliseconds 300) {
                    $candidate = New-ProxyCandidate -Address $DefaultHost -Port $commonPort -Kind 'socks' -Source 'common Clash/Mihomo port'
                    if ($candidate) { $candidates.Add($candidate) }
                }
            }
        }
    }

    foreach ($candidate in @(Get-ActiveEnvironmentProxyCandidates)) {
        if ($candidate) { $candidates.Add($candidate) }
    }

    $fallbackHost = ConvertTo-LoopbackAddress $DefaultHost
    if (-not $fallbackHost) { $fallbackHost = '127.0.0.1' }
    $fallback = New-ProxyCandidate -Address $fallbackHost -Port $DefaultPort -Kind 'socks' -Source 'default fallback'
    $candidates.Add($fallback)
}

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
