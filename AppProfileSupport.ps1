function Get-GatewayStartupDelayPolicy {
    [pscustomobject]@{
        DefaultSeconds = 2
        MinimumSeconds = 0
        MaximumSeconds = 60
    }
}

function ConvertTo-GatewayStartupDelaySeconds {
    param(
        [AllowNull()][object]$Value,
        [switch]$UseDefaultWhenEmpty
    )

    $policy = Get-GatewayStartupDelayPolicy
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        if ($UseDefaultWhenEmpty) {
            return [int]$policy.DefaultSeconds
        }
        throw 'Startup wait time must not be empty.'
    }

    $seconds = 0
    if (-not [int]::TryParse($text, [ref]$seconds) -or
        $seconds -lt $policy.MinimumSeconds -or
        $seconds -gt $policy.MaximumSeconds) {
        throw "Startup wait time must be a whole number from $($policy.MinimumSeconds) to $($policy.MaximumSeconds) seconds."
    }
    return $seconds
}

function ConvertTo-GatewayProxyPortOverride {
    param(
        [AllowNull()][object]$Value,
        [switch]$AllowAuto
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Trim() -ieq 'auto') {
        if ($AllowAuto) {
            return $null
        }
        throw 'Proxy port must not be empty.'
    }

    $port = 0
    if (-not [int]::TryParse($text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw 'Proxy port must be a whole number from 1 to 65535, or auto.'
    }
    return $port
}

function New-GatewayUserConfiguration {
    $language = if ([Globalization.CultureInfo]::CurrentUICulture.Name -match '^(?i)zh') { 'zh-CN' } else { 'en-US' }
    $delayPolicy = Get-GatewayStartupDelayPolicy
    [pscustomobject]@{
        SchemaVersion = 1
        Language = $language
        StartupDelaySeconds = [int]$delayPolicy.DefaultSeconds
        ProxyPortOverride = $null
        DefaultAppId = 'codex'
        Apps = @()
    }
}

function Read-GatewayUserConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-GatewayUserConfiguration
    }

    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        $stored = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Could not read application configuration '$Path': $($_.Exception.Message)"
    }

    if ([int]$stored.SchemaVersion -ne 1) {
        throw "Unsupported application configuration schema '$($stored.SchemaVersion)' in $Path."
    }

    $apps = [Collections.Generic.List[object]]::new()
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$ids.Add('codex')
    foreach ($storedApp in @($stored.Apps)) {
        $id = [string]$storedApp.Id
        $name = [string]$storedApp.Name
        $executablePath = [string]$storedApp.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^custom-[a-f0-9]{8,32}$') {
            throw "Application configuration contains an invalid Id: '$id'."
        }
        if (-not $ids.Add($id)) {
            throw "Application configuration contains a duplicate Id: '$id'."
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Application '$id' has an empty Name."
        }
        if ([string]::IsNullOrWhiteSpace($executablePath)) {
            throw "Application '$name' has an empty ExecutablePath."
        }

        $apps.Add([pscustomobject]@{
            Id = $id
            Name = $name
            ExecutablePath = $executablePath
            Arguments = [string]$storedApp.Arguments
            WorkingDirectory = [string]$storedApp.WorkingDirectory
        })
    }

    $language = [string]$stored.Language
    if ([string]::IsNullOrWhiteSpace($language)) {
        $language = if ([Globalization.CultureInfo]::CurrentUICulture.Name -match '^(?i)zh') { 'zh-CN' } else { 'en-US' }
    }
    if ($language -notin @('zh-CN', 'en-US')) {
        throw "Unsupported interface language '$language'."
    }

    $startupDelayValue = $null
    if ($stored.PSObject.Properties.Name -contains 'StartupDelaySeconds') {
        $startupDelayValue = $stored.StartupDelaySeconds
    }
    try {
        $startupDelaySeconds = ConvertTo-GatewayStartupDelaySeconds -Value $startupDelayValue -UseDefaultWhenEmpty
    } catch {
        throw "Invalid StartupDelaySeconds in ${Path}: $($_.Exception.Message)"
    }

    $proxyPortValue = $null
    if ($stored.PSObject.Properties.Name -contains 'ProxyPortOverride') {
        $proxyPortValue = $stored.ProxyPortOverride
    }
    try {
        $proxyPortOverride = ConvertTo-GatewayProxyPortOverride -Value $proxyPortValue -AllowAuto
    } catch {
        throw "Invalid ProxyPortOverride in ${Path}: $($_.Exception.Message)"
    }

    $defaultAppId = [string]$stored.DefaultAppId
    if ([string]::IsNullOrWhiteSpace($defaultAppId)) {
        $defaultAppId = 'codex'
    }
    if (-not $ids.Contains($defaultAppId)) {
        throw "DefaultAppId '$defaultAppId' does not identify a configured application."
    }

    [pscustomobject]@{
        SchemaVersion = 1
        Language = $language
        StartupDelaySeconds = $startupDelaySeconds
        ProxyPortOverride = $proxyPortOverride
        DefaultAppId = $defaultAppId
        Apps = @($apps)
    }
}

function Save-GatewayUserConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "Application configuration path must include a directory: $Path"
    }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }

    $startupDelaySeconds = ConvertTo-GatewayStartupDelaySeconds -Value $Configuration.StartupDelaySeconds -UseDefaultWhenEmpty
    $proxyPortOverride = ConvertTo-GatewayProxyPortOverride -Value $Configuration.ProxyPortOverride -AllowAuto
    $serializable = [ordered]@{
        SchemaVersion = 1
        Language = [string]$Configuration.Language
        StartupDelaySeconds = $startupDelaySeconds
        ProxyPortOverride = $proxyPortOverride
        DefaultAppId = [string]$Configuration.DefaultAppId
        Apps = @($Configuration.Apps | ForEach-Object {
            [ordered]@{
                Id = [string]$_.Id
                Name = [string]$_.Name
                ExecutablePath = [string]$_.ExecutablePath
                Arguments = [string]$_.Arguments
                WorkingDirectory = [string]$_.WorkingDirectory
            }
        })
    }

    $json = $serializable | ConvertTo-Json -Depth 5
    $temporaryPath = Join-Path $directory ('.apps-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = "$Path.bak"
    try {
        [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        }
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-GatewayAppProfiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)

    @([pscustomobject]@{
        Id = 'codex'
        Name = 'ChatGPT / Codex'
        Type = 'CodexAppX'
        ExecutablePath = $null
        Arguments = ''
        WorkingDirectory = ''
    }) + @($Configuration.Apps | ForEach-Object {
        [pscustomobject]@{
            Id = [string]$_.Id
            Name = [string]$_.Name
            Type = 'CustomExecutable'
            ExecutablePath = [string]$_.ExecutablePath
            Arguments = [string]$_.Arguments
            WorkingDirectory = [string]$_.WorkingDirectory
        }
    })
}

function Get-GatewayDefaultAppProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)

    $profile = Get-GatewayAppProfiles -Configuration $Configuration |
        Where-Object Id -eq $Configuration.DefaultAppId |
        Select-Object -First 1
    if (-not $profile) {
        throw "Default application '$($Configuration.DefaultAppId)' is not configured."
    }
    return $profile
}

function Resolve-CustomExecutableProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)

    $path = [Environment]::ExpandEnvironmentVariables([string]$Profile.ExecutablePath)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Configured executable does not exist: $path"
    }
    $resolvedPath = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
    if ([IO.Path]::GetExtension($resolvedPath) -ine '.exe') {
        throw "Configured application must be a Windows .exe file: $resolvedPath"
    }

    $workingDirectory = [Environment]::ExpandEnvironmentVariables([string]$Profile.WorkingDirectory)
    if ([string]::IsNullOrWhiteSpace($workingDirectory)) {
        $workingDirectory = Split-Path -Parent $resolvedPath
    }
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        throw "Configured working directory does not exist: $workingDirectory"
    }
    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $workingDirectory -ErrorAction Stop).Path

    [pscustomobject]@{
        Id = [string]$Profile.Id
        DisplayName = [string]$Profile.Name
        Type = 'CustomExecutable'
        Variant = 'Custom'
        Version = 'user configured'
        PackageName = '-'
        PackageFullName = '-'
        InstallLocation = Split-Path -Parent $resolvedPath
        ExecutablePath = $resolvedPath
        ExecutableSource = 'user application configuration'
        Arguments = [string]$Profile.Arguments
        WorkingDirectory = $resolvedWorkingDirectory
        ManifestError = $null
    }
}

function ConvertTo-CustomExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InputPath)

    $candidate = $InputPath.Trim().Trim('"').Trim("'")
    $candidate = [Environment]::ExpandEnvironmentVariables($candidate)
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Executable does not exist: $candidate"
    }
    $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    if ([IO.Path]::GetExtension($resolved) -ine '.exe') {
        throw "Only Windows .exe applications are supported: $resolved"
    }
    return $resolved
}

function Expand-GatewayLaunchArguments {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Arguments,
        [Parameter(Mandatory)]$Proxy
    )

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        return ''
    }
    $socksProxy = 'socks5://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port
    $httpProxy = 'http://{0}:{1}' -f $Proxy.UriHost, $Proxy.Port
    return $Arguments.Replace('{proxy_host}', [string]$Proxy.Host).
        Replace('{proxy_port}', [string]$Proxy.Port).
        Replace('{socks_proxy}', $socksProxy).
        Replace('{http_proxy}', $httpProxy)
}

function Get-RunningCustomExecutableProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExpectedExecutable)

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        throw "Could not inspect running processes with Win32_Process: $($_.Exception.Message)"
    }

    $expectedName = [IO.Path]::GetFileName($ExpectedExecutable)
    foreach ($process in $processes) {
        $path = [string]$process.ExecutablePath
        $exactPath = -not [string]::IsNullOrWhiteSpace($path) -and
            [string]::Equals($path, $ExpectedExecutable, [StringComparison]::OrdinalIgnoreCase)
        $restrictedPathNameMatch = [string]::IsNullOrWhiteSpace($path) -and
            [string]::Equals([string]$process.Name, $expectedName, [StringComparison]::OrdinalIgnoreCase)
        if ($exactPath -or $restrictedPathNameMatch) {
            [pscustomobject]@{
                ProcessId = [int]$process.ProcessId
                Name = [string]$process.Name
                ExecutablePath = $path
                Identification = if ($exactPath) { 'exact executable path' } else { 'process name; executable path unavailable' }
            }
        }
    }
}

function Wait-CustomExecutableProcessStart {
    [CmdletBinding()]
    param(
        [int[]]$ExistingProcessId = @(),
        [Parameter(Mandatory)][string]$ExpectedExecutable,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        foreach ($process in @(Get-RunningCustomExecutableProcess -ExpectedExecutable $ExpectedExecutable)) {
            if ($ExistingProcessId -notcontains $process.ProcessId) {
                return $process
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}
