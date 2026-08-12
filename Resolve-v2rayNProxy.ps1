[CmdletBinding()]
param(
    [string]$DefaultHost = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int]$DefaultPort = 10808
)

$ErrorActionPreference = 'Stop'

function Normalize-ListenHost {
    param([AllowNull()][string]$HostValue)

    if ([string]::IsNullOrWhiteSpace($HostValue) -or
        $HostValue -in @('0.0.0.0', '::', '[::]')) {
        return '127.0.0.1'
    }

    return $HostValue.Trim('[', ']')
}

function Get-RuntimeInbound {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($inbound in @($config.inbounds)) {
            $kind = if ($inbound.type) { $inbound.type } else { $inbound.protocol }
            if ($kind -notin @('socks', 'mixed')) {
                continue
            }

            $port = if ($inbound.listen_port) { $inbound.listen_port } else { $inbound.port }
            if ($port -and [int]$port -ge 1 -and [int]$port -le 65535) {
                return [pscustomobject]@{
                    Host = Normalize-ListenHost $inbound.listen
                    Port = [int]$port
                }
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Get-GuiInbound {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        foreach ($inbound in @($config.Inbound)) {
            if ($inbound.Protocol -notin @('socks', 'mixed')) {
                continue
            }

            if ($inbound.LocalPort -and [int]$inbound.LocalPort -ge 1 -and [int]$inbound.LocalPort -le 65535) {
                return [pscustomobject]@{
                    Host = $DefaultHost
                    Port = [int]$inbound.LocalPort
                }
            }
        }
    } catch {
        return $null
    }

    return $null
}

$v2rayNProcess = Get-Process v2rayN -ErrorAction SilentlyContinue |
    Where-Object { $_.Path } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

if ($v2rayNProcess) {
    $v2rayNRoot = Split-Path -Parent $v2rayNProcess.Path

    $runtime = Get-RuntimeInbound (Join-Path $v2rayNRoot 'binConfigs\config.json')
    if ($runtime) {
        '{0}|{1}|v2rayN runtime config' -f $runtime.Host, $runtime.Port
        exit 0
    }

    $gui = Get-GuiInbound (Join-Path $v2rayNRoot 'guiConfigs\guiNConfig.json')
    if ($gui) {
        '{0}|{1}|v2rayN GUI config' -f $gui.Host, $gui.Port
        exit 0
    }
}

'{0}|{1}|default fallback' -f $DefaultHost, $DefaultPort
