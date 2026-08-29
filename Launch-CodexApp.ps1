[CmdletBinding()]
param(
    [ValidateSet('Launch', 'Check', 'Settings')]
    [string]$Mode = 'Launch',
    [string]$UserAppsPath
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
    UserConfiguration = 11
}

function T {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Position = 1)][object[]]$Values = @()
    )
    if (Get-Command Get-GatewayText -ErrorAction SilentlyContinue) {
        return Get-GatewayText -Key $Key -Values $Values
    }
    return $Key
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
        [Parameter(Mandatory)][string]$GatewayVersion,
        [Parameter(Mandatory)][string]$ApplicationName
    )

    $socksUrl = 'socks5://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port
    $environmentLabel = if ($Proxy.Kind -eq 'mixed') { 'SOCKS + HTTP/HTTPS' } else { 'SOCKS only' }

    Clear-Host
    Write-Host ''
    Write-Host '  CODEX GATEWAY' -ForegroundColor Cyan
    Write-Host ('  {0}' -f (T 'Subtitle')) -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('    {0}: {1}' -f (T 'GatewayVersion'), $GatewayVersion) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'DefaultApp'), $ApplicationName) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'Endpoint'), $socksUrl) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'InboundType'), $Proxy.Kind) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'DetectedFrom'), $Proxy.Source) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'Environment'), $environmentLabel) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'SessionScope'), (T 'CurrentLaunchOnly')) -ForegroundColor Cyan
    Write-Host ('    {0}: {1}' -f (T 'WindowsProxy'), (T 'Unchanged')) -ForegroundColor Cyan
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

    Write-Host ('       {0}' -f (T 'Failed')) -ForegroundColor Red
    Write-Host ''
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Red
    Write-Host ('  {0}' -f (T 'GatewayStopped')) -ForegroundColor Red
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Red
    Write-Host ''
    Write-Host ("    {0}" -f $Reason) -ForegroundColor Red
    foreach ($line in $Detail) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host ("    {0}" -f $line) -ForegroundColor Cyan
        }
    }
    Write-Host ''
}

function Wait-ForStartupAction {
    param(
        [Parameter(Mandatory)][string]$DefaultApplicationName,
        [ValidateRange(0, 60)][int]$DelaySeconds = 2
    )

    Clear-Host
    Write-Host ''
    Write-Host '  CODEX GATEWAY' -ForegroundColor Cyan
    Write-Host ('  {0}' -f (T 'Subtitle')) -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('  {0}' -f (T 'DefaultApplication' @($DefaultApplicationName))) -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('  {0}' -f (T 'StartupKeys')) -ForegroundColor Cyan
    Write-Host ('  {0}' -f (T 'AutoLaunch' @($DelaySeconds))) -ForegroundColor Cyan

    if ($DelaySeconds -eq 0) {
        return 'Launch'
    }

    try {
        if ([Console]::IsInputRedirected) {
            return 'Launch'
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($DelaySeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::S) {
                    return 'Settings'
                }
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    return 'Launch'
                }
            }
            Start-Sleep -Milliseconds 50
        }
    } catch {
        # Non-interactive hosts cannot expose console key state; launch immediately.
        return 'Launch'
    }
    return 'Launch'
}

function Pause-SettingsScreen {
    [void](Read-Host (T 'PressEnter'))
}

function Add-GatewayCustomApplication {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    Write-Host ''
    Write-Host (T 'AddTitle') -ForegroundColor Cyan
    Write-Host (T 'AddHint') -ForegroundColor Cyan
    $pathInput = Read-Host (T 'ExecutableBlankCancels')
    if ([string]::IsNullOrWhiteSpace($pathInput)) {
        return $Configuration
    }
    $executablePath = ConvertTo-CustomExecutablePath -InputPath $pathInput
    $suggestedName = [IO.Path]::GetFileNameWithoutExtension($executablePath)
    $name = Read-Host (T 'DisplayNamePrompt' @($suggestedName))
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $suggestedName
    }
    $arguments = Read-Host (T 'ArgumentsOptional')
    $workingDirectory = Read-Host (T 'WorkingDirectoryDefault' @((Split-Path -Parent $executablePath)))

    $newApp = [pscustomobject]@{
        Id = 'custom-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        Name = $name.Trim()
        ExecutablePath = $executablePath
        Arguments = [string]$arguments
        WorkingDirectory = [string]$workingDirectory
    }
    $Configuration.Apps = @($Configuration.Apps) + @($newApp)

    $makeDefault = Read-Host (T 'SetDefaultPrompt')
    if ([string]::IsNullOrWhiteSpace($makeDefault) -or $makeDefault -match '^(?i)y(es)?$') {
        $Configuration.DefaultAppId = $newApp.Id
    }
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-Host (T 'AddedApplication' @($newApp.Name)) -ForegroundColor Green
    Pause-SettingsScreen
    return $Configuration
}

function Select-CustomApplicationIndex {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ActionName
    )

    $customApps = @($Configuration.Apps)
    if ($customApps.Count -eq 0) {
        Write-Host (T 'NoCustomApps') -ForegroundColor Red
        Pause-SettingsScreen
        return -1
    }
    Write-Host ''
    for ($index = 0; $index -lt $customApps.Count; $index++) {
        Write-Host ("  [{0}] {1}" -f ($index + 1), $customApps[$index].Name) -ForegroundColor Cyan
    }
    $selection = Read-Host (T 'ApplicationNumber' @($ActionName))
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return -1
    }
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $customApps.Count) {
        Write-Host (T 'InvalidApplicationNumber') -ForegroundColor Red
        Pause-SettingsScreen
        return -1
    }
    return ($number - 1)
}

function Edit-GatewayCustomApplication {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    $index = Select-CustomApplicationIndex -Configuration $Configuration -ActionName (T 'EditAction')
    if ($index -lt 0) { return $Configuration }
    $app = @($Configuration.Apps)[$index]

    Write-Host ''
    $name = Read-Host (T 'DisplayNamePrompt' @($app.Name))
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $app.Name = $name.Trim()
    }
    $pathInput = Read-Host ("{0} [{1}]" -f (T 'ExecutableLabel'), $app.ExecutablePath)
    if (-not [string]::IsNullOrWhiteSpace($pathInput)) {
        $app.ExecutablePath = ConvertTo-CustomExecutablePath -InputPath $pathInput
    }
    $arguments = Read-Host (T 'ArgumentsEdit')
    if ($arguments -eq '-') {
        $app.Arguments = ''
    } elseif (-not [string]::IsNullOrWhiteSpace($arguments)) {
        $app.Arguments = $arguments
    }
    $workingDirectory = Read-Host (T 'WorkingDirectoryEdit')
    if ($workingDirectory -eq '-') {
        $app.WorkingDirectory = ''
    } elseif (-not [string]::IsNullOrWhiteSpace($workingDirectory)) {
        if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
            throw "Working directory does not exist: $workingDirectory"
        }
        $app.WorkingDirectory = (Resolve-Path -LiteralPath $workingDirectory).Path
    }

    $Configuration.Apps[$index] = $app
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-Host (T 'UpdatedApplication' @($app.Name)) -ForegroundColor Green
    Pause-SettingsScreen
    return $Configuration
}

function Remove-GatewayCustomApplication {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    $index = Select-CustomApplicationIndex -Configuration $Configuration -ActionName (T 'RemoveAction')
    if ($index -lt 0) { return $Configuration }
    $customApps = @($Configuration.Apps)
    $app = $customApps[$index]
    $confirmation = Read-Host (T 'RemoveConfirmation' @($app.Name))
    if ($confirmation -notmatch '^(?i)y(es)?$') {
        return $Configuration
    }

    $Configuration.Apps = @($customApps | Where-Object Id -ne $app.Id)
    if ($Configuration.DefaultAppId -eq $app.Id) {
        $Configuration.DefaultAppId = 'codex'
    }
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-Host (T 'RemovedApplication' @($app.Name)) -ForegroundColor Green
    Pause-SettingsScreen
    return $Configuration
}

function Set-GatewayInterfaceLanguage {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$LocalesDirectory
    )

    Write-Host ''
    Write-Host (T 'ChooseLanguage') -ForegroundColor Cyan
    Write-Host ('  {0}' -f (T 'ChineseLanguage')) -ForegroundColor Cyan
    Write-Host ('  {0}' -f (T 'EnglishLanguage')) -ForegroundColor Cyan
    $selection = Read-Host (T 'LanguageSelection')
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Configuration
    }
    $language = switch ($selection.Trim()) {
        '1' { 'zh-CN' }
        '2' { 'en-US' }
        default { $null }
    }
    if (-not $language) {
        Write-Host (T 'UnknownSelection') -ForegroundColor Red
        Pause-SettingsScreen
        return $Configuration
    }

    $Configuration.Language = $language
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    $locale = Import-GatewayLanguage -Language $language -LocalesDirectory $LocalesDirectory
    Write-Host (T 'LanguageChanged' @($locale.DisplayName)) -ForegroundColor Green
    Pause-SettingsScreen
    return $Configuration
}

function Set-GatewayStartupDelay {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    $policy = Get-GatewayStartupDelayPolicy
    Write-Host ''
    Write-Host (T 'StartupDelayTitle') -ForegroundColor Cyan
    $selection = Read-Host (T 'StartupDelayPrompt' @(
        $Configuration.StartupDelaySeconds,
        $policy.MinimumSeconds,
        $policy.MaximumSeconds
    ))
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Configuration
    }

    try {
        $seconds = ConvertTo-GatewayStartupDelaySeconds -Value $selection
    } catch {
        Write-Host (T 'StartupDelayInvalid' @($policy.MinimumSeconds, $policy.MaximumSeconds)) -ForegroundColor Red
        Pause-SettingsScreen
        return $Configuration
    }

    $Configuration.StartupDelaySeconds = $seconds
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-Host (T 'StartupDelayChanged' @($seconds)) -ForegroundColor Green
    Pause-SettingsScreen
    return $Configuration
}

function Show-GatewaySettings {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$LocalesDirectory
    )

    while ($true) {
        Clear-Host
        $profiles = @(Get-GatewayAppProfiles -Configuration $Configuration)
        Write-Host ''
        Write-Host ('  {0}' -f (T 'SettingsTitle')) -ForegroundColor Cyan
        Write-Host ('  {0}' -f (T 'ConfigurationPath' @($ConfigurationPath))) -ForegroundColor Cyan
        Write-Host ''
        Write-Host ('  {0}' -f (T 'ApplicationsInstruction')) -ForegroundColor Cyan
        for ($index = 0; $index -lt $profiles.Count; $index++) {
            $defaultMarker = if ($profiles[$index].Id -eq $Configuration.DefaultAppId) { T 'DefaultMarker' } else { '' }
            Write-Host ("    [{0}] {1}{2}" -f ($index + 1), $profiles[$index].Name, $defaultMarker) -ForegroundColor Cyan
        }
        Write-Host ''
        Write-Host ('    {0}' -f (T 'AddMenu')) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'EditMenu')) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'DeleteMenu')) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'LanguageMenu')) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'StartupDelayMenu' @($Configuration.StartupDelaySeconds))) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'LaunchMenu')) -ForegroundColor Cyan
        Write-Host ('    {0}' -f (T 'ExitMenu')) -ForegroundColor Cyan
        Write-Host ''

        $choice = Read-Host (T 'Selection')
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return [pscustomobject]@{ Action = 'Launch'; Configuration = $Configuration }
        }
        if ($choice -match '^\d+$') {
            $number = [int]$choice
            if ($number -ge 1 -and $number -le $profiles.Count) {
                $Configuration.DefaultAppId = $profiles[$number - 1].Id
                Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
                continue
            }
        }

        try {
            switch ($choice.ToUpperInvariant()) {
                'A' { $Configuration = Add-GatewayCustomApplication -Configuration $Configuration -ConfigurationPath $ConfigurationPath }
                'E' { $Configuration = Edit-GatewayCustomApplication -Configuration $Configuration -ConfigurationPath $ConfigurationPath }
                'D' { $Configuration = Remove-GatewayCustomApplication -Configuration $Configuration -ConfigurationPath $ConfigurationPath }
                'L' { $Configuration = Set-GatewayInterfaceLanguage -Configuration $Configuration -ConfigurationPath $ConfigurationPath -LocalesDirectory $LocalesDirectory }
                'T' { $Configuration = Set-GatewayStartupDelay -Configuration $Configuration -ConfigurationPath $ConfigurationPath }
                'Q' { return [pscustomobject]@{ Action = 'Exit'; Configuration = $Configuration } }
                default {
                    Write-Host (T 'UnknownSelection') -ForegroundColor Red
                    Pause-SettingsScreen
                }
            }
        } catch {
            Write-Host (T 'SettingsError' @($_.Exception.Message)) -ForegroundColor Red
            Pause-SettingsScreen
        }
    }
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

function Resolve-SelectedGatewayApplication {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)][string]$AppPreference
    )

    if ($Profile.Type -eq 'CustomExecutable') {
        return Resolve-CustomExecutableProfile -Profile $Profile
    }

    $selection = Get-InstalledCodexPackage -Preference $AppPreference
    $executable = Resolve-CodexExecutable -Package $selection.Package -Variant $selection.Variant
    [pscustomobject]@{
        Id = 'codex'
        DisplayName = "ChatGPT / Codex $($selection.Variant)"
        Type = 'CodexAppX'
        Variant = $selection.Variant
        Version = [string]$selection.Package.Version
        PackageName = [string]$selection.Package.Name
        PackageFullName = [string]$selection.Package.PackageFullName
        InstallLocation = [string]$selection.Package.InstallLocation
        ExecutablePath = $executable.Path
        ExecutableSource = $executable.Source
        Arguments = ''
        WorkingDirectory = Split-Path -Parent $executable.Path
        ManifestError = $executable.ManifestError
    }
}

function Show-ResolvedApplication {
    param([Parameter(Mandatory)]$Application)

    Write-Success (T 'Selected' @($Application.DisplayName))
    Write-Host ("       {0}: {1}" -f (T 'TypeLabel'), $Application.Type) -ForegroundColor Cyan
    Write-Host ("       {0}: {1}" -f (T 'VariantLabel'), $Application.Variant) -ForegroundColor Cyan
    Write-Host ("       {0}: {1}" -f (T 'VersionLabel'), $Application.Version) -ForegroundColor Cyan
    if ($Application.PackageName -ne '-') {
        Write-Host ("       {0}: {1}" -f (T 'PackageNameLabel'), $Application.PackageName) -ForegroundColor Cyan
    }
    Write-Host ("       {0}: {1}" -f (T 'ExecutableLabel'), $Application.ExecutablePath) -ForegroundColor Cyan
    Write-Host ("       {0}: {1}" -f (T 'ResolvedFromLabel'), $Application.ExecutableSource) -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($Application.Arguments)) {
        Write-Host ("       Arguments: {0}" -f (T 'ArgumentsConfigured')) -ForegroundColor Cyan
    }
    Write-Host ''
}

function Get-RunningSelectedApplication {
    param([Parameter(Mandatory)]$Application)
    if ($Application.Type -eq 'CodexAppX') {
        return @(Get-RunningCodexProcess)
    }
    return @(Get-RunningCustomExecutableProcess -ExpectedExecutable $Application.ExecutablePath)
}

function Wait-SelectedApplicationStart {
    param(
        [Parameter(Mandatory)]$Application,
        [ValidateRange(1, 60)][int]$TimeoutSeconds
    )
    if ($Application.Type -eq 'CodexAppX') {
        return Wait-CodexProcessStart -ExistingProcessId @() -ExpectedExecutable $Application.ExecutablePath -TimeoutSeconds $TimeoutSeconds
    }
    return Wait-CustomExecutableProcessStart -ExistingProcessId @() -ExpectedExecutable $Application.ExecutablePath -TimeoutSeconds $TimeoutSeconds
}

function Invoke-CodexGateway {
    try {
        . (Join-Path $PSScriptRoot 'GatewayConfig.ps1')
        . (Join-Path $PSScriptRoot 'ProxySupport.ps1')
        . (Join-Path $PSScriptRoot 'AppSupport.ps1')
        . (Join-Path $PSScriptRoot 'AppProfileSupport.ps1')
        . (Join-Path $PSScriptRoot 'LocalizationSupport.ps1')
        $localesDirectory = Join-Path $PSScriptRoot 'locales'
        [void](Import-GatewayLanguage -Language (Get-DefaultGatewayLanguage) -LocalesDirectory $localesDirectory)

        if (-not $GatewayConfig) { throw 'GatewayConfig.ps1 did not define $GatewayConfig.' }
        if ([string]$GatewayConfig.GatewayVersion -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must contain a semantic version: '$($GatewayConfig.GatewayVersion)'" }
        if ($GatewayConfig.AppPreference -notin @('PreferBeta', 'PreferStable', 'BetaOnly', 'StableOnly')) { throw "Invalid AppPreference '$($GatewayConfig.AppPreference)'." }
        if ([string]::IsNullOrWhiteSpace([string]$GatewayConfig.DefaultProxyHost)) { throw 'DefaultProxyHost must not be empty.' }
        if ([int]$GatewayConfig.DefaultProxyPort -lt 1 -or [int]$GatewayConfig.DefaultProxyPort -gt 65535) { throw 'DefaultProxyPort must be between 1 and 65535.' }
        if ([int]$GatewayConfig.ProxyProbeTimeoutMs -lt 100 -or [int]$GatewayConfig.ProxyProbeTimeoutMs -gt 30000) { throw 'ProxyProbeTimeoutMs must be between 100 and 30000.' }
        if ([int]$GatewayConfig.LaunchTimeoutSeconds -lt 1 -or [int]$GatewayConfig.LaunchTimeoutSeconds -gt 60) { throw 'LaunchTimeoutSeconds must be between 1 and 60.' }
        if ([string]::IsNullOrWhiteSpace([string]$GatewayConfig.UserAppsPath)) { throw 'UserAppsPath must not be empty.' }
        $effectiveUserAppsPath = if ([string]::IsNullOrWhiteSpace($UserAppsPath)) { [string]$GatewayConfig.UserAppsPath } else { [IO.Path]::GetFullPath($UserAppsPath) }
        $configuredHealthUri = [uri]$GatewayConfig.HealthCheckUrl
        if (-not $configuredHealthUri.IsAbsoluteUri -or $configuredHealthUri.Scheme -ne 'https') { throw 'HealthCheckUrl must be an absolute HTTPS URL.' }
    } catch {
        Write-Failure -Reason (T 'GatewayConfigFailed') -Detail @($_.Exception.Message)
        return $ExitCode.Configuration
    }

    try {
        $userConfiguration = Read-GatewayUserConfiguration -Path $effectiveUserAppsPath
        [void](Import-GatewayLanguage -Language $userConfiguration.Language -LocalesDirectory $localesDirectory)
        $defaultProfile = Get-GatewayDefaultAppProfile -Configuration $userConfiguration
    } catch {
        Write-Failure -Reason (T 'AppConfigFailed') -Detail @(
            "Configuration: $effectiveUserAppsPath",
            $_.Exception.Message,
            'Restore the .bak file or remove the invalid JSON to return to the Codex default.'
        )
        return $ExitCode.UserConfiguration
    }

    if ($Mode -eq 'Settings') {
        $settingsResult = Show-GatewaySettings -Configuration $userConfiguration -ConfigurationPath $effectiveUserAppsPath -LocalesDirectory $localesDirectory
        if ($settingsResult.Action -eq 'Exit') { return $ExitCode.Success }
        $userConfiguration = $settingsResult.Configuration
        $defaultProfile = Get-GatewayDefaultAppProfile -Configuration $userConfiguration
    } elseif ($Mode -eq 'Launch') {
        $startupAction = Wait-ForStartupAction -DefaultApplicationName $defaultProfile.Name -DelaySeconds $userConfiguration.StartupDelaySeconds
        if ($startupAction -eq 'Settings') {
            $settingsResult = Show-GatewaySettings -Configuration $userConfiguration -ConfigurationPath $effectiveUserAppsPath -LocalesDirectory $localesDirectory
            if ($settingsResult.Action -eq 'Exit') { return $ExitCode.Success }
            $userConfiguration = $settingsResult.Configuration
            $defaultProfile = Get-GatewayDefaultAppProfile -Configuration $userConfiguration
        }
    }

    try {
        $logsDirectory = Join-Path $PSScriptRoot 'logs'
        if (-not (Test-Path -LiteralPath $logsDirectory -PathType Container)) { [void](New-Item -ItemType Directory -Path $logsDirectory -Force) }
        $script:LogPath = Join-Path $logsDirectory ('gateway-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
        Write-GatewayLog -Level Info -Message ("Gateway started. Version={0}; Mode={1}; DefaultApp={2}; AppType={3}; AppPreference={4}" -f $GatewayConfig.GatewayVersion, $Mode, $defaultProfile.Name, $defaultProfile.Type, $GatewayConfig.AppPreference)
    } catch {
        Write-Failure -Reason (T 'LogFailed') -Detail @("Log directory: $PSScriptRoot\logs", $_.Exception.Message)
        return $ExitCode.Logging
    }

    try {
        $proxy = & (Join-Path $PSScriptRoot 'Resolve-v2rayNProxy.ps1') -DefaultHost $GatewayConfig.DefaultProxyHost -DefaultPort $GatewayConfig.DefaultProxyPort -OutputFormat Object
        if (-not $proxy) { throw 'The proxy resolver returned no endpoint.' }
        Set-SessionProxyEnvironment -Proxy $proxy
        Write-GatewayLog -Level Info -Message ("Proxy endpoint={0}:{1}; Kind={2}; Source={3}" -f $proxy.Host, $proxy.Port, $proxy.Kind, $proxy.Source)
        foreach ($warning in @($proxy.Warnings)) { Write-GatewayLog -Level Warning -Message $warning }
    } catch {
        Write-Failure -Reason (T 'ProxyResolveFailed') -Detail @("Fallback: $($GatewayConfig.DefaultProxyHost):$($GatewayConfig.DefaultProxyPort)", $_.Exception.Message)
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.ProxyEndpoint
    }

    Write-Header -Proxy $proxy -GatewayVersion $GatewayConfig.GatewayVersion -ApplicationName $defaultProfile.Name

    Write-Step -Number '1/3' -Message (T 'VerifySocks')
    if (-not (Test-Socks5Handshake -ProxyHost $proxy.Host -Port $proxy.Port -TimeoutMilliseconds $GatewayConfig.ProxyProbeTimeoutMs)) {
        $message = "SOCKS5 handshake failed at $($proxy.Host):$($proxy.Port)."
        Write-Failure -Reason $message -Detail @((T 'StartV2ray'), "$(T 'DetectedFrom'): $($proxy.Source)")
        Write-GatewayLog -Level Error -Message $message
        return $ExitCode.ProxyEndpoint
    }
    Write-Success (T 'SocksVerified' @($proxy.Host, $proxy.Port))
    Write-GatewayLog -Level Info -Message 'SOCKS5 handshake succeeded.'
    Write-Host ''

    Write-Step -Number '2/3' -Message (T 'ResolveApplication' @($defaultProfile.Name))
    try {
        $application = Resolve-SelectedGatewayApplication -Profile $defaultProfile -AppPreference $GatewayConfig.AppPreference
        Write-GatewayLog -Level Info -Message ("Application resolved. Id={0}; Name={1}; Type={2}; Version={3}; Package={4}; Executable={5}; Source={6}" -f $application.Id, $application.DisplayName, $application.Type, $application.Version, $application.PackageName, $application.ExecutablePath, $application.ExecutableSource)
        if ($application.ManifestError) { Write-GatewayLog -Level Warning -Message ("Manifest fallback note: {0}" -f $application.ManifestError) }
    } catch {
        $code = if ($defaultProfile.Type -eq 'CodexAppX' -and $_.Exception.Message -match 'AppX package|eligible.*package') { $ExitCode.AppPackage } else { $ExitCode.Executable }
        Write-Failure -Reason (T 'ApplicationResolveFailed') -Detail @((T 'ApplicationLabel' @($defaultProfile.Name)), $_.Exception.Message)
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $code
    }
    Show-ResolvedApplication -Application $application

    if ($Mode -eq 'Check') {
        Write-Step -Number '3/3' -Message (T 'TestHttps')
        try {
            $targetPort = if ($configuredHealthUri.IsDefaultPort) { 443 } else { $configuredHealthUri.Port }
            $targetPath = if ($configuredHealthUri.PathAndQuery) { $configuredHealthUri.PathAndQuery } else { '/' }
            $statusCode = Test-HttpsThroughSocks5 -ProxyHost $proxy.Host -Port $proxy.Port -TargetHost $configuredHealthUri.Host -TargetPort $targetPort -TargetPath $targetPath
            Write-Success (T 'HttpsReached' @($configuredHealthUri.Host, $statusCode))
            Write-GatewayLog -Level Info -Message ("HTTPS health check succeeded. Host={0}; Status={1}" -f $configuredHealthUri.Host, $statusCode)
        } catch {
            Write-Failure -Reason (T 'HttpsFailed') -Detail @("$(T 'Endpoint'): $($proxy.Host):$($proxy.Port)", "URL: $($GatewayConfig.HealthCheckUrl)", $_.Exception.Message)
            Write-GatewayLog -Level Error -Message ("HTTPS health check failed. $($_.Exception.Message)")
            return $ExitCode.HttpsCheck
        }
        Write-Host ''
        Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Green
        Write-Host ('  {0}' -f (T 'CheckComplete')) -ForegroundColor Green
        Write-Host ('  {0}' -f (T 'CheckPassed')) -ForegroundColor Green
        Write-Host ('  {0}' -f (T 'NothingLaunched')) -ForegroundColor Green
        Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Green
        Write-Host ''
        Write-GatewayLog -Level Info -Message 'Check completed successfully; application was not launched.'
        return $ExitCode.Success
    }

    Write-Step -Number '3/3' -Message (T 'StartPrivate' @($application.DisplayName))
    try {
        $running = @(Get-RunningSelectedApplication -Application $application)
    } catch {
        Write-Failure -Reason (T 'ProcessCheckFailed') -Detail @($_.Exception.Message)
        Write-GatewayLog -Level Error -Message $_.Exception.Message
        return $ExitCode.AlreadyRunning
    }

    if ($running.Count -gt 0) {
        $details = @((T 'CloseExisting'))
        foreach ($group in @($running | Group-Object ExecutablePath, Identification)) {
            $sample = $group.Group[0]
            $displayPath = if ($sample.ExecutablePath) { $sample.ExecutablePath } else { T 'PathUnavailable' }
            $processIds = @($group.Group.ProcessId | Sort-Object) -join ', '
            $processNames = @($group.Group.Name | Sort-Object -Unique) -join ', '
            $details += "PIDs $processIds`: $processNames; Path: $displayPath; Identified by: $($sample.Identification)"
        }
        Write-Failure -Reason (T 'AlreadyRunning' @($application.DisplayName)) -Detail $details
        Write-GatewayLog -Level Error -Message ("Launch blocked by running process IDs: {0}" -f (($running.ProcessId) -join ', '))
        return $ExitCode.AlreadyRunning
    }

    try {
        $launchArguments = Expand-GatewayLaunchArguments -Arguments $application.Arguments -Proxy $proxy
        $startParameters = @{
            FilePath = $application.ExecutablePath
            WorkingDirectory = $application.WorkingDirectory
            PassThru = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($launchArguments)) { $startParameters.ArgumentList = $launchArguments }
        $started = Start-Process @startParameters
        Write-GatewayLog -Level Info -Message ("Start-Process returned PID={0}; ArgumentsConfigured={1}" -f $started.Id, (-not [string]::IsNullOrWhiteSpace($launchArguments)))
    } catch {
        Write-Failure -Reason (T 'StartFailed') -Detail @("$(T 'ExecutableLabel'): $($application.ExecutablePath)", $_.Exception.Message)
        Write-GatewayLog -Level Error -Message ("Start-Process failed. $($_.Exception.Message)")
        return $ExitCode.LaunchFailed
    }

    try {
        $observed = Wait-SelectedApplicationStart -Application $application -TimeoutSeconds $GatewayConfig.LaunchTimeoutSeconds
    } catch {
        Write-Failure -Reason (T 'VerificationFailed') -Detail @("$(T 'ExecutableLabel'): $($application.ExecutablePath)", $_.Exception.Message)
        Write-GatewayLog -Level Error -Message ("Process verification error. $($_.Exception.Message)")
        return $ExitCode.LaunchNotObserved
    }
    if (-not $observed) {
        $message = T 'ProcessNotObserved' @($GatewayConfig.LaunchTimeoutSeconds)
        Write-Failure -Reason $message -Detail @("$(T 'ExecutableLabel'): $($application.ExecutablePath)", "Start-Process PID: $($started.Id)")
        Write-GatewayLog -Level Error -Message $message
        return $ExitCode.LaunchNotObserved
    }

    Write-Success (T 'ProcessVerified' @($application.DisplayName, $observed.ProcessId))
    Write-Host ''
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Green
    Write-Host ('  {0}' -f (T 'Ready')) -ForegroundColor Green
    Write-Host ('  {0}' -f (T 'ReadyProxy')) -ForegroundColor Green
    Write-Host ('  {0}' -f (T 'ReadyWindows')) -ForegroundColor Green
    Write-Host '  ------------------------------------------------------------------------' -ForegroundColor Green
    Write-Host ''
    Write-GatewayLog -Level Info -Message ("Launch succeeded. App={0}; Type={1}; ObservedPID={2}" -f $application.DisplayName, $application.Type, $observed.ProcessId)
    return $ExitCode.Success
}

try {
    $result = Invoke-CodexGateway
    exit $result
} catch {
    if ($script:LogPath) {
        try { Write-GatewayLog -Level Error -Message ("Unexpected error. $($_.Exception.Message)") } catch {}
    }
    Write-Failure -Reason (T 'UnexpectedError') -Detail @($_.Exception.Message)
    exit $ExitCode.Unexpected
}
