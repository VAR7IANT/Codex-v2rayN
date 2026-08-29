$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'AppSupport.ps1')

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('Codex Gateway App Tests (' + [guid]::NewGuid().ToString('N') + ')')
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Assert-Equal 'Beta' (Get-CodexPackageOrder -Preference PreferBeta)[0] 'PreferBeta order is wrong.'
    Assert-Equal 'Stable' (Get-CodexPackageOrder -Preference PreferStable)[0] 'PreferStable order is wrong.'
    Assert-Equal 1 @(Get-CodexPackageOrder -Preference BetaOnly).Count 'BetaOnly returned more than one variant.'
    Assert-Equal 1 @(Get-CodexPackageOrder -Preference StableOnly).Count 'StableOnly returned more than one variant.'

    $script:MockPackages = @(
        [pscustomobject]@{ Name = 'OpenAI.CodexBeta'; Version = [version]'2.0.0.0' },
        [pscustomobject]@{ Name = 'OpenAI.Codex'; Version = [version]'3.0.0.0' }
    )
    function Get-AppxPackage {
        [CmdletBinding()]
        param([string]$Name)
        $script:MockPackages | Where-Object Name -eq $Name
    }

    $preferredBeta = Get-InstalledCodexPackage -Preference PreferBeta
    Assert-Equal 'Beta' $preferredBeta.Variant 'PreferBeta did not select an installed Beta package.'
    $script:MockPackages = @($script:MockPackages | Where-Object Name -eq 'OpenAI.Codex')
    $fallbackStable = Get-InstalledCodexPackage -Preference PreferBeta
    Assert-Equal 'Stable' $fallbackStable.Variant 'PreferBeta did not fall back when Beta was absent.'
    Remove-Item Function:\Get-AppxPackage

    $manifestPath = 'app\Unexpected Name (Beta).exe'
    $manifestExecutable = Join-Path $tempRoot $manifestPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $manifestExecutable) -Force | Out-Null
    New-Item -ItemType File -Path $manifestExecutable | Out-Null
    $fakePackage = [pscustomobject]@{
        Name = 'OpenAI.CodexBeta'
        PackageFullName = 'OpenAI.CodexBeta_Test_x64__test'
        InstallLocation = $tempRoot
    }

    function Get-AppxPackageManifest {
        param($Package)
        [pscustomobject]@{
            Package = [pscustomobject]@{
                Applications = [pscustomobject]@{
                    Application = [pscustomobject]@{ Executable = $manifestPath }
                }
            }
        }
    }

    $resolved = Resolve-CodexExecutable -Package $fakePackage -Variant Beta
    Assert-Equal $manifestExecutable $resolved.Path 'Manifest executable was not selected.'
    Assert-Equal 'AppX manifest' $resolved.Source 'Manifest source was not reported.'

    Remove-Item Function:\Get-AppxPackageManifest
    $fallbackExecutable = Join-Path $tempRoot 'app\ChatGPT (Beta).exe'
    New-Item -ItemType File -Path $fallbackExecutable | Out-Null
    function Get-AppxPackageManifest { throw 'simulated manifest failure' }

    $fallback = Resolve-CodexExecutable -Package $fakePackage -Variant Beta
    Assert-Equal $fallbackExecutable $fallback.Path 'Known-path fallback was not selected.'
    Assert-Equal 'known-path fallback' $fallback.Source 'Fallback source was not reported.'
    if ($fallback.ManifestError -notmatch 'simulated manifest failure') {
        throw 'Manifest failure detail was not retained.'
    }

    Remove-Item Function:\Get-AppxPackageManifest
    function Get-CimInstance {
        [CmdletBinding()]
        param([string]$ClassName)
        @(
            [pscustomobject]@{
                ProcessId = 100
                Name = 'Unexpected Name (Beta).exe'
                ExecutablePath = 'C:\Program Files\WindowsApps\OpenAI.CodexBeta_2.0.0.0_x64__test\app\Unexpected Name (Beta).exe'
                CommandLine = $null
            },
            [pscustomobject]@{
                ProcessId = 101
                Name = 'ChatGPT (Beta).exe'
                ExecutablePath = $null
                CommandLine = $null
            },
            [pscustomobject]@{
                ProcessId = 102
                Name = 'ChatGPT.exe'
                ExecutablePath = 'C:\Program Files\WindowsApps\OpenAI.Codex_3.0.0.0_x64__test\app\ChatGPT.exe'
                CommandLine = $null
            },
            [pscustomobject]@{
                ProcessId = 103
                Name = 'unrelated.exe'
                ExecutablePath = 'C:\Tools\unrelated.exe'
                CommandLine = $null
            }
        )
    }

    $running = @(Get-RunningCodexProcess)
    Assert-Equal 3 $running.Count 'CIM process matching returned the wrong count.'
    Assert-Equal 'WindowsApps executable path' $running[0].Identification 'WindowsApps path match was not reported.'
    Assert-Equal 'process name; executable path unavailable' $running[1].Identification 'Restricted-path fallback was not reported.'
    Remove-Item Function:\Get-CimInstance

    Write-Host 'All AppX selection and executable resolution tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path Function:\Get-AppxPackageManifest) {
        Remove-Item Function:\Get-AppxPackageManifest
    }
    if (Test-Path Function:\Get-AppxPackage) {
        Remove-Item Function:\Get-AppxPackage
    }
    if (Test-Path Function:\Get-CimInstance) {
        Remove-Item Function:\Get-CimInstance
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
