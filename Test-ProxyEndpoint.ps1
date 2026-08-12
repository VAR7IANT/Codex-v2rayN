[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProxyHost,
    [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
    [uri]$TestUrl
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ProxySupport.ps1')

if (-not (Test-Socks5Handshake -ProxyHost $ProxyHost -Port $Port)) {
    throw "The endpoint $ProxyHost`:$Port did not complete a SOCKS5 handshake."
}

Write-Output "SOCKS5 handshake verified at $ProxyHost`:$Port"

if ($TestUrl) {
    if ($TestUrl.Scheme -ne 'https') {
        throw 'The outbound health-check URL must use HTTPS.'
    }

    $targetPort = if ($TestUrl.IsDefaultPort) { 443 } else { $TestUrl.Port }
    $targetPath = $TestUrl.PathAndQuery
    if (-not $targetPath) { $targetPath = '/' }
    $statusCode = Test-HttpsThroughSocks5 -ProxyHost $ProxyHost -Port $Port -TargetHost $TestUrl.Host -TargetPort $targetPort -TargetPath $targetPath
    Write-Output "HTTPS reached $($TestUrl.Host) through v2rayN (HTTP $statusCode)"
}
