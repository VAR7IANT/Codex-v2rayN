[CmdletBinding()]
param(
    [ValidateSet('Launch', 'Check')]
    [string]$Mode = 'Launch'
)

$ErrorActionPreference = 'Stop'

$ExitCode = @{
    Success = 0
    ProxyEndpoint = 1
    AppPackage = 2
    Executable = 3
    AlreadyRunning = 4
    LaunchFailed = 5
    LaunchNotObserved = 6
    HttpsCheck = 7
    Logging = 8
    Configuration = 9
    Unexpected = 10
}

function Write-GatewayLog {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $safeMessage = $Message -replace '[\r\n]+', ' '
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level.ToUpperInvariant(), $safeMessage
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Write-Header {
    param(
        [Parameter(Mandatory)]$Proxy,
        [Parameter(Mandatory)][string]$GatewayVersion
    )

    $socksUrl = 'socks5://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port
    $environmentLabel = if ($Proxy.Kind -eq 'mixed') { 'SOCKS + HTTP/HTTPS' } else { 'SOCKS only' }

    Clear-Host
    Write-Host ''
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |                                                                      |' -ForegroundColor Cyan
    Write-Host '  |   CODEX GATEWAY                                                      |' -ForegroundColor Cyan
    Write-Host '  |   Private route through v2rayN                                       |' -ForegroundColor Cyan
    Write-Host '  |                                                                      |' -ForegroundColor Cyan
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('    GATEWAY VERSION {0}' -f $GatewayVersion) -ForegroundColor Cyan
    Write-Host ('    ENDPOINT       {0}' -f $socksUrl) -ForegroundColor Cyan
    Write-Host ('    INBOUND TYPE   {0}' -f $Proxy.Kind) -ForegroundColor Cyan
    Write-Host ('    DETECTED FROM  {0}' -f $Proxy.Source) -ForegroundColor Cyan
    Write-Host ('    ENVIRONMENT    {0}' -f $environmentLabel) -ForegroundColor Cyan
    Write-Host '    SESSION SCOPE  Current launch only' -ForegroundColor Cyan
    Write-Host '    WINDOWS PROXY  Unchanged' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Step {
    param([string]$Number, [string]$Message)
    Write-Host ("  [{0}] {1}..." -f $Number, $Message) -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host ("       [OK] {0}" -f $Message) -ForegroundColor Green
}

function Write-Failure {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string[]]$Detail = @()
    )

    Write-Host '       [FAILED]' -ForegroundColor Red
    Write-Host ''
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Red
    Write-Host '  |  GATEWAY STOPPED                                                     |' -ForegroundColor Red
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Red
    Write-Host ''
    Write-Host ("    {0}" -f $Reason) -ForegroundColor Red
    foreach ($line in $Detail) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host ("    {0}" -f $line) -ForegroundColor Cyan
        }
    }
    Write-Host ''
}

function Set-SessionProxyEnvironment {
    param([Parameter(Mandatory)]$Proxy)

    $socksUrl = 'socks5://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port
    $httpUrl = 'http://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port

    $env:ALL_PROXY = $socksUrl
    $env:all_proxy = $socksUrl

    if ($Proxy.Kind -eq 'mixed') {
        $env:HTTP_PROXY = $httpUrl
        $env:HTTPS_PROXY = $httpUrl
        $env:http_proxy = $httpUrl
        $env:https_proxy = $httpUrl
    } else {
        Remove-Item -LiteralPath Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:http_proxy, Env:https_proxy -ErrorAction SilentlyContinue
    }

    $env:NO_PROXY = 'localhost,127.0.0.1,::1'
    $env:no_proxy = 'localhost,127.0.0.1,::1'
}

function Show-AppSelection {
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Executable
    )

    Write-Success ("Selected {0}" -f $Selection.Variant)
    Write-Host ("       Variant:       {0}" -f $Selection.Variant) -ForegroundColor Cyan
    Write-Host ("       Version:       {0}" -f $Selection.Package.Version) -ForegroundColor Cyan
    Write-Host ("       Package Name:  {0}" -f $Selection.Package.Name) -ForegroundColor Cyan
    Write-Host ("       Executable:    {0}" -f $Executable.Path) -ForegroundColor Cyan
    Write-Host ("       Resolved From: {0}" -f $Executable.Source) -ForegroundColor Cyan
    Write-Host ''
}

function Invoke-CodexGateway {
    try {
        . (Join-Path $PSScriptRoot 'GatewayConfig.ps1')
        . (Join-Path $PSScriptRoot 'ProxySupport.ps1')
        . (Join-Path $PSScriptRoot 'AppSupport.ps1')

        if (-not $GatewayConfig) {
            throw 'GatewayConfig.ps1 did not define $GatewayConfig.'
        }
        if ([string]$GatewayConfig.GatewayVersion -notmatch '^\d+\.\d+\.\d+$') {
            throw "VERSION must contain a semantic version such as 1.0.0: '$($GatewayConfig.GatewayVersion)'"
        }
        if ($GatewayConfig.AppPreference -notin @('PreferBeta', 'PreferStable', 'BetaOnly', 'StableOnly')) {
            throw "Invalid AppPreference '$($GatewayConfig.AppPreference)' in GatewayConfig.ps1."
        }
        if ([string]::IsNullOrWhiteSpace([string]$GatewayConfig.DefaultProxyHost)) {
            throw 'DefaultProxyHost must not be empty in GatewayConfig.ps1.'
        }
        if ([int]$GatewayConfig.DefaultProxyPort -lt 1 -or [int]$GatewayConfig.DefaultProxyPort -gt 65535) {
            throw "DefaultProxyPort must be between 1 and 65535: $($GatewayConfig.DefaultProxyPort)"
        }
        if ([int]$GatewayConfig.ProxyProbeTimeoutMs -lt 100 -or [int]$GatewayConfig.ProxyProbeTimeoutMs -gt 30000) {
            throw "ProxyProbeTimeoutMs must be between 100 and 30000: $($GatewayConfig.ProxyProbeTimeoutMs)"
        }
        if ([int]$GatewayConfig.LaunchTimeoutSeconds -lt 1 -or [int]$GatewayConfig.LaunchTimeoutSeconds -gt 60) {
            throw "LaunchTimeoutSeconds must be between 1 and 60: $($GatewayConfig.LaunchTimeoutSeconds)"
        }
        $configuredHealthUri = [uri]$GatewayConfig.HealthCheckUrl
        if (-not $configuredHealthUri.IsAbsoluteUri -or $configuredHealthUri.Scheme -ne 'https') {
            throw "HealthCheckUrl must be an absolute HTTPS URL: $($GatewayConfig.HealthCheckUrl)"
        }
    } catch {
        Write-Failure -Reason 'Gateway configuration could not be loaded.' -Detail @($_.Exception.Message)
        return $ExitCode.Configuration
    }

    try {
        $logsDirectory = Join-Path $PSScriptRoot 'logs'
        if (-not (Test-Path -LiteralPath $logsDirectory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $logsDirectory -Force)
        }
        $script:LogPath = Join-Path $logsDirectory ('gateway-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
        Write-GatewayLog -Level Info -Message ("Gateway started. Version={0}; Mode={1}; AppPreference={2}" -f $GatewayConfig.GatewayVersion, $Mode, $GatewayConfig.AppPreference)
    } catch {
        Write-Failure -Reason 'The gateway log could not be created.' -Detail @(
            "Log directory: $PSScriptRoot\logs",
            $_.Exception.Message
        )
        return $ExitCode.Logging
    }

    try {
        $proxy = & (Join-Path $PSScriptRoot 'Resolve-v2rayNProxy.ps1') `
            -DefaultHost $GatewayConfig.DefaultProxyHost `
            -DefaultPort $GatewayConfig.DefaultProxyPort `
            -OutputFormat Object
        if (-not $proxy) {
            throw 'The proxy resolver returned no endpoint.'
        }
        Set-SessionProxyEnvironment -Proxy $proxy
        Write-GatewayLog -Level Info -Message ("Proxy endpoint={0}:{1}; Kind={2}; Source={3}" -f $proxy.Host, $proxy.Port, $proxy.Kind, $proxy.Source)
        foreach ($warning in @($proxy.Warnings)) {
            Write-GatewayLog -Level Warning -Message $warning
        }
    } catch {
        Write-Failure -Reason 'The v2rayN endpoint could not be resolved.' -Detail @(
            "Fallback: $($GatewayConfig.DefaultProxyHost):$($GatewayConfig.DefaultProxyPort)",
            $_.Exception.Message
        )
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.ProxyEndpoint
    }

    Write-Header -Proxy $proxy -GatewayVersion $GatewayConfig.GatewayVersion

    Write-Step -Number '1/3' -Message 'Verifying the v2rayN SOCKS5 endpoint'
    if (-not (Test-Socks5Handshake -ProxyHost $proxy.Host -Port $proxy.Port -TimeoutMilliseconds $GatewayConfig.ProxyProbeTimeoutMs)) {
        $message = "SOCKS5 handshake failed at $($proxy.Host):$($proxy.Port)."
        Write-Failure -Reason $message -Detail @(
            'Start v2rayN and verify that its SOCKS/mixed inbound is listening.',
            "Detected from: $($proxy.Source)"
        )
        Write-GatewayLog -Level Error -Message $message
        return $ExitCode.ProxyEndpoint
    }
    Write-Success ("SOCKS5 handshake verified at {0}:{1}" -f $proxy.Host, $proxy.Port)
    Write-GatewayLog -Level Info -Message 'SOCKS5 handshake succeeded.'
    Write-Host ''

    Write-Step -Number '2/3' -Message 'Finding the ChatGPT / Codex Windows app'
    try {
        $selection = Get-InstalledCodexPackage -Preference $GatewayConfig.AppPreference
        Write-GatewayLog -Level Info -Message ("Package detected. Variant={0}; Name={1}; Version={2}; FullName={3}" -f $selection.Variant, $selection.Package.Name, $selection.Package.Version, $selection.Package.PackageFullName)
    } catch {
        Write-Failure -Reason 'No usable ChatGPT / Codex AppX package could be selected.' -Detail @(
            $_.Exception.Message,
            'Install the eligible Beta or Stable Windows app and try again.'
        )
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.AppPackage
    }

    try {
        $executable = Resolve-CodexExecutable -Package $selection.Package -Variant $selection.Variant
        Write-GatewayLog -Level Info -Message ("Executable={0}; Source={1}" -f $executable.Path, $executable.Source)
        if ($executable.ManifestError) {
            Write-GatewayLog -Level Warning -Message ("Manifest resolution failed; fallback used. Error={0}" -f $executable.ManifestError)
        }
    } catch {
        Write-Failure -Reason 'The selected package executable could not be found.' -Detail @(
            "Variant: $($selection.Variant)",
            "Package: $($selection.Package.Name)",
            "Install location: $($selection.Package.InstallLocation)",
            $_.Exception.Message
        )
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.Executable
    }
    Show-AppSelection -Selection $selection -Executable $executable

    if ($Mode -eq 'Check') {
        Write-Step -Number '3/3' -Message 'Testing OpenAI HTTPS through v2rayN'
        try {
            $testUri = $configuredHealthUri
            $targetPort = if ($testUri.IsDefaultPort) { 443 } else { $testUri.Port }
            $targetPath = if ($testUri.PathAndQuery) { $testUri.PathAndQuery } else { '/' }
            $statusCode = Test-HttpsThroughSocks5 -ProxyHost $proxy.Host -Port $proxy.Port `
                -TargetHost $testUri.Host -TargetPort $targetPort -TargetPath $targetPath
            Write-Success ("HTTPS reached {0} through v2rayN (HTTP {1})" -f $testUri.Host, $statusCode)
            Write-GatewayLog -Level Info -Message ("HTTPS health check succeeded. Host={0}; Status={1}" -f $testUri.Host, $statusCode)
        } catch {
            Write-Failure -Reason 'OpenAI HTTPS could not be reached through v2rayN.' -Detail @(
                "Endpoint: $($proxy.Host):$($proxy.Port)",
                "URL: $($GatewayConfig.HealthCheckUrl)",
                $_.Exception.Message
            )
            Write-GatewayLog -Level Error -Message ("HTTPS health check failed. $($_.Exception.Message)")
            return $ExitCode.HttpsCheck
        }

        Write-Host ''
        Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Green
        Write-Host '  |  CHECK COMPLETE                                                      |' -ForegroundColor Green
        Write-Host '  |  Proxy, OpenAI HTTPS, package, and executable checks passed.         |' -ForegroundColor Green
        Write-Host '  |  Nothing was launched.                                               |' -ForegroundColor Green
        Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Green
        Write-Host ''
        Write-GatewayLog -Level Info -Message 'Check completed successfully; app was not launched.'
        return $ExitCode.Success
    }

    Write-Step -Number '3/3' -Message 'Starting a private ChatGPT / Codex session'
    try {
        $running = @(Get-RunningCodexProcess)
    } catch {
        Write-Failure -Reason 'Running ChatGPT / Codex instances could not be checked safely.' -Detail @($_.Exception.Message)
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.AlreadyRunning
    }

    if ($running.Count -gt 0) {
        $details = @('Close every Beta and Stable instance before using Gateway. Existing processes cannot inherit this session proxy.')
        foreach ($group in @($running | Group-Object ExecutablePath, Identification)) {
            $sample = $group.Group[0]
            $displayPath = if ($sample.ExecutablePath) { $sample.ExecutablePath } else { '<unavailable due to process access restrictions>' }
            $processIds = @($group.Group.ProcessId | Sort-Object) -join ', '
            $processNames = @($group.Group.Name | Sort-Object -Unique) -join ', '
            $details += "PIDs $processIds`: $processNames; Path: $displayPath; Identified by: $($sample.Identification)"
        }
        Write-Failure -Reason 'ChatGPT / Codex is already running.' -Detail $details
        Write-GatewayLog -Level Error -Message ("Launch blocked by running process IDs: {0}" -f (($running.ProcessId) -join ', '))
        return $ExitCode.AlreadyRunning
    }

    try {
        $started = Start-Process -FilePath $executable.Path `
            -WorkingDirectory (Split-Path -Parent $executable.Path) -PassThru
        Write-GatewayLog -Level Info -Message ("Start-Process returned PID={0}" -f $started.Id)
    } catch {
        Write-Failure -Reason 'Windows could not start the selected executable.' -Detail @(
            "Executable: $($executable.Path)",
            $_.Exception.Message
        )
        Write-GatewayLog -Level Error -Message ("Start-Process failed. $($_.Exception.Message)")
        return $ExitCode.LaunchFailed
    }

    try {
        $observed = Wait-CodexProcessStart -ExistingProcessId @() -ExpectedExecutable $executable.Path `
            -TimeoutSeconds $GatewayConfig.LaunchTimeoutSeconds
    } catch {
        Write-Failure -Reason 'The launch was requested, but process verification failed.' -Detail @(
            "Executable: $($executable.Path)",
            $_.Exception.Message
        )
        Write-GatewayLog -Level Error -Message ("Process verification error. $($_.Exception.Message)")
        return $ExitCode.LaunchNotObserved
    }

    if (-not $observed) {
        $message = "No ChatGPT / Codex process appeared within $($GatewayConfig.LaunchTimeoutSeconds) seconds."
        Write-Failure -Reason $message -Detail @(
            "Executable: $($executable.Path)",
            "Start-Process PID: $($started.Id)",
            'Check Windows Event Viewer or repair the selected AppX package.'
        )
        Write-GatewayLog -Level Error -Message $message
        return $ExitCode.LaunchNotObserved
    }

    Write-Success ("{0} process verified (PID {1})" -f $selection.Variant, $observed.ProcessId)
    Write-Host ''
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Green
    Write-Host '  |  READY                                                               |' -ForegroundColor Green
    Write-Host '  |  ChatGPT / Codex is running with the v2rayN session environment.     |' -ForegroundColor Green
    Write-Host '  |  Windows proxy settings remain unchanged.                            |' -ForegroundColor Green
    Write-Host '  +----------------------------------------------------------------------+' -ForegroundColor Green
    Write-Host ''
    Write-GatewayLog -Level Info -Message ("Launch succeeded. Variant={0}; ObservedPID={1}" -f $selection.Variant, $observed.ProcessId)
    return $ExitCode.Success
}

try {
    $result = Invoke-CodexGateway
    exit $result
} catch {
    if ($script:LogPath) {
        try { Write-GatewayLog -Level Error -Message ("Unexpected error. $($_.Exception.Message)") } catch {}
    }
    Write-Failure -Reason 'An unexpected gateway error occurred.' -Detail @($_.Exception.Message)
    exit $ExitCode.Unexpected
}
