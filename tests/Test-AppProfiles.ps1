$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'AppProfileSupport.ps1')

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('Codex Gateway Profiles (' + [guid]::NewGuid().ToString('N') + ')')
$configPath = Join-Path $tempRoot 'config\apps.json'
$executablePath = Join-Path $tempRoot 'Apps\Example App (Test).exe'
New-Item -ItemType Directory -Path (Split-Path -Parent $executablePath) -Force | Out-Null
New-Item -ItemType File -Path $executablePath | Out-Null

try {
    $configuration = New-GatewayUserConfiguration
    Assert-Equal 'codex' $configuration.DefaultAppId 'New configuration has the wrong default.'
    if ($configuration.Language -notin @('zh-CN', 'en-US')) { throw 'New configuration has an unsupported language.' }
    Assert-Equal 2 $configuration.StartupDelaySeconds 'New configuration has the wrong startup delay.'
    Assert-Equal $null $configuration.ProxyPortOverride 'New configuration should use automatic proxy detection.'
    Assert-Equal 0 @($configuration.Apps).Count 'New configuration contains custom apps.'

    $customApp = [pscustomobject]@{
        Id = 'custom-1234abcd'
        Name = '示例应用 (Example App)'
        ExecutablePath = $executablePath
        Arguments = '--example "value with spaces"'
        WorkingDirectory = ''
    }
    $configuration.Apps = @($customApp)
    $configuration.DefaultAppId = $customApp.Id
    $configuration.StartupDelaySeconds = 7
    $configuration.ProxyPortOverride = 10809
    Save-GatewayUserConfiguration -Configuration $configuration -Path $configPath

    $loaded = Read-GatewayUserConfiguration -Path $configPath
    Assert-Equal $configuration.Language $loaded.Language 'Language changed after JSON round-trip.'
    Assert-Equal 7 $loaded.StartupDelaySeconds 'Startup delay changed after JSON round-trip.'
    Assert-Equal 10809 $loaded.ProxyPortOverride 'Proxy port override changed after JSON round-trip.'
    Assert-Equal $customApp.Id $loaded.DefaultAppId 'Default custom app was not preserved.'
    Assert-Equal 1 @($loaded.Apps).Count 'Custom app count changed after JSON round-trip.'
    Assert-Equal $customApp.Name $loaded.Apps[0].Name 'Unicode application name changed after JSON round-trip.'
    Assert-Equal $executablePath $loaded.Apps[0].ExecutablePath 'Executable path changed after JSON round-trip.'
    Assert-Equal $customApp.Arguments $loaded.Apps[0].Arguments 'Arguments changed after JSON round-trip.'

    $defaultProfile = Get-GatewayDefaultAppProfile -Configuration $loaded
    Assert-Equal 'CustomExecutable' $defaultProfile.Type 'Custom profile type is wrong.'
    $resolved = Resolve-CustomExecutableProfile -Profile $defaultProfile
    Assert-Equal $executablePath $resolved.ExecutablePath 'Custom executable did not resolve literally.'
    Assert-Equal (Split-Path -Parent $executablePath) $resolved.WorkingDirectory 'Default working directory is wrong.'

    $expandedArguments = Expand-GatewayLaunchArguments -Arguments '--host={proxy_host} --port={proxy_port} --proxy={socks_proxy} --http={http_proxy}' -Proxy ([pscustomobject]@{
        Host = '127.0.0.1'
        UriHost = '127.0.0.1'
        Port = 10808
    })
    Assert-Equal '--host=127.0.0.1 --port=10808 --proxy=socks5://127.0.0.1:10808 --http=http://127.0.0.1:10808' $expandedArguments 'Proxy argument placeholders were not expanded.'

    Save-GatewayUserConfiguration -Configuration $loaded -Path $configPath
    Assert-Equal $true (Test-Path -LiteralPath "$configPath.bak") 'Configuration backup was not created.'

    $legacyConfigPath = Join-Path $tempRoot 'legacy.json'
    [IO.File]::WriteAllText($legacyConfigPath, '{"SchemaVersion":1,"Language":"en-US","DefaultAppId":"codex","Apps":[]}', [Text.UTF8Encoding]::new($false))
    $legacyConfiguration = Read-GatewayUserConfiguration -Path $legacyConfigPath
    Assert-Equal 2 $legacyConfiguration.StartupDelaySeconds 'Legacy configuration did not receive the default startup delay.'
    Assert-Equal $null $legacyConfiguration.ProxyPortOverride 'Legacy configuration did not use automatic proxy detection.'

    $invalidDelayPath = Join-Path $tempRoot 'invalid-delay.json'
    [IO.File]::WriteAllText($invalidDelayPath, '{"SchemaVersion":1,"Language":"en-US","StartupDelaySeconds":61,"DefaultAppId":"codex","Apps":[]}', [Text.UTF8Encoding]::new($false))
    try {
        Read-GatewayUserConfiguration -Path $invalidDelayPath | Out-Null
        throw 'Invalid StartupDelaySeconds was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'StartupDelaySeconds') { throw }
    }

    $invalidPortPath = Join-Path $tempRoot 'invalid-port.json'
    [IO.File]::WriteAllText($invalidPortPath, '{"SchemaVersion":1,"Language":"en-US","StartupDelaySeconds":2,"ProxyPortOverride":0,"DefaultAppId":"codex","Apps":[]}', [Text.UTF8Encoding]::new($false))
    try {
        Read-GatewayUserConfiguration -Path $invalidPortPath | Out-Null
        throw 'Invalid ProxyPortOverride was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'ProxyPortOverride') { throw }
    }

    function Get-CimInstance {
        [CmdletBinding()]
        param([string]$ClassName)
        @(
            [pscustomobject]@{ ProcessId = 201; Name = 'Example App (Test).exe'; ExecutablePath = $executablePath; CommandLine = $null },
            [pscustomobject]@{ ProcessId = 202; Name = 'Example App (Test).exe'; ExecutablePath = $null; CommandLine = $null },
            [pscustomobject]@{ ProcessId = 203; Name = 'unrelated.exe'; ExecutablePath = 'C:\Tools\unrelated.exe'; CommandLine = $null }
        )
    }
    $running = @(Get-RunningCustomExecutableProcess -ExpectedExecutable $executablePath)
    Assert-Equal 2 $running.Count 'Custom process matcher returned the wrong count.'
    Assert-Equal 'exact executable path' $running[0].Identification 'Exact path match was not identified.'
    Assert-Equal 'process name; executable path unavailable' $running[1].Identification 'Restricted-path match was not identified.'
    Remove-Item Function:\Get-CimInstance

    $invalidConfigPath = Join-Path $tempRoot 'invalid.json'
    [IO.File]::WriteAllText($invalidConfigPath, '{"SchemaVersion":1,"DefaultAppId":"missing","Apps":[]}', [Text.UTF8Encoding]::new($false))
    try {
        Read-GatewayUserConfiguration -Path $invalidConfigPath | Out-Null
        throw 'Invalid DefaultAppId was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'does not identify a configured application') { throw }
    }

    Write-Host 'All custom application profile tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path Function:\Get-CimInstance) {
        Remove-Item Function:\Get-CimInstance
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
