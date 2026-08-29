function Get-CodexPackageOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PreferBeta', 'PreferStable', 'BetaOnly', 'StableOnly')]
        [string]$Preference
    )

    switch ($Preference) {
        'PreferBeta'   { return @('Beta', 'Stable') }
        'PreferStable' { return @('Stable', 'Beta') }
        'BetaOnly'     { return @('Beta') }
        'StableOnly'   { return @('Stable') }
    }
}

function Get-CodexPackageName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Beta', 'Stable')]
        [string]$Variant
    )

    if ($Variant -eq 'Beta') { return 'OpenAI.CodexBeta' }
    return 'OpenAI.Codex'
}

function Get-CodexFallbackExecutable {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Beta', 'Stable')]
        [string]$Variant
    )

    if ($Variant -eq 'Beta') { return 'app\ChatGPT (Beta).exe' }
    return 'app\ChatGPT.exe'
}

function Get-InstalledCodexPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PreferBeta', 'PreferStable', 'BetaOnly', 'StableOnly')]
        [string]$Preference
    )

    foreach ($variant in @(Get-CodexPackageOrder -Preference $Preference)) {
        $packageName = Get-CodexPackageName -Variant $variant
        try {
            $package = Get-AppxPackage -Name $packageName -ErrorAction Stop |
                Sort-Object Version -Descending |
                Select-Object -First 1
        } catch {
            throw "AppX package query failed for $packageName`: $($_.Exception.Message)"
        }

        if ($package) {
            return [pscustomobject]@{
                Variant = $variant
                Package = $package
            }
        }
    }

    $expected = @(Get-CodexPackageOrder -Preference $Preference | ForEach-Object {
        Get-CodexPackageName -Variant $_
    }) -join ', '
    throw "No eligible ChatGPT / Codex AppX package is installed. Selection policy: $Preference. Expected: $expected."
}

function Resolve-CodexExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)]
        [ValidateSet('Beta', 'Stable')]
        [string]$Variant
    )

    $installLocation = [string]$Package.InstallLocation
    if ([string]::IsNullOrWhiteSpace($installLocation)) {
        throw "Package $($Package.Name) did not report an InstallLocation."
    }

    $manifestError = $null
    $manifestExecutables = [Collections.Generic.List[string]]::new()
    try {
        $packageFullName = [string]$Package.PackageFullName
        if ([string]::IsNullOrWhiteSpace($packageFullName)) {
            throw "Package $($Package.Name) did not report a PackageFullName."
        }
        $manifest = Get-AppxPackageManifest -Package $packageFullName -ErrorAction Stop
        foreach ($application in @($manifest.Package.Applications.Application)) {
            $relativePath = [string]$application.Executable
            if (-not [string]::IsNullOrWhiteSpace($relativePath) -and
                -not $manifestExecutables.Contains($relativePath)) {
                $manifestExecutables.Add($relativePath)
            }
        }
    } catch {
        $manifestError = $_.Exception.Message
    }

    foreach ($relativePath in @($manifestExecutables)) {
        $candidate = Join-Path -Path $installLocation -ChildPath $relativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [pscustomobject]@{
                Path = $candidate
                Source = 'AppX manifest'
                ManifestError = $manifestError
            }
        }
    }

    if (-not $manifestError) {
        if ($manifestExecutables.Count -gt 0) {
            $manifestError = "Manifest executable candidates did not exist: $($manifestExecutables -join ', ')"
        } else {
            $manifestError = 'The AppX manifest contained no executable paths.'
        }
    }

    $fallbackRelativePath = Get-CodexFallbackExecutable -Variant $Variant
    $fallbackPath = Join-Path -Path $installLocation -ChildPath $fallbackRelativePath
    if (Test-Path -LiteralPath $fallbackPath -PathType Leaf) {
        return [pscustomobject]@{
            Path = $fallbackPath
            Source = 'known-path fallback'
            ManifestError = $manifestError
        }
    }

    $manifestSummary = if ($manifestExecutables.Count -gt 0) {
        $manifestExecutables -join ', '
    } elseif ($manifestError) {
        "manifest unavailable: $manifestError"
    } else {
        'manifest contained no executable paths'
    }

    throw "Executable not found for package $($Package.Name). Install location: $installLocation. Manifest candidates: $manifestSummary. Fallback checked: $fallbackPath"
}

function Get-CodexProcessNames {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('ChatGPT.exe', 'ChatGPT (Beta).exe')) {
        [void]$names.Add($name)
    }

    foreach ($variant in @('Beta', 'Stable')) {
        $packageName = Get-CodexPackageName -Variant $variant
        try {
            foreach ($package in @(Get-AppxPackage -Name $packageName -ErrorAction Stop)) {
                try {
                    $resolved = Resolve-CodexExecutable -Package $package -Variant $variant
                    [void]$names.Add([IO.Path]::GetFileName($resolved.Path))
                } catch {
                    # A broken secondary package must not prevent process detection.
                }
            }
        } catch {
            # CIM path matching remains authoritative when package enumeration is unavailable.
        }
    }

    return @($names)
}

function Get-RunningCodexProcess {
    [CmdletBinding()]
    param([AllowNull()][string[]]$KnownProcessName)

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        throw "Could not inspect running processes with Win32_Process: $($_.Exception.Message)"
    }

    $knownNames = if ($null -eq $KnownProcessName) {
        @(Get-CodexProcessNames)
    } else {
        @($KnownProcessName)
    }
    foreach ($process in $processes) {
        $path = [string]$process.ExecutablePath
        $commandLine = [string]$process.CommandLine
        $pathIdentifiesPackage = -not [string]::IsNullOrWhiteSpace($path) -and (
            $path -match '(?i)[\\/]WindowsApps[\\/]OpenAI\.CodexBeta_' -or
            $path -match '(?i)[\\/]WindowsApps[\\/]OpenAI\.Codex_'
        )
        $commandIdentifiesPackage = -not [string]::IsNullOrWhiteSpace($commandLine) -and (
            $commandLine -match '(?i)[\\/]WindowsApps[\\/]OpenAI\.CodexBeta_' -or
            $commandLine -match '(?i)[\\/]WindowsApps[\\/]OpenAI\.Codex_'
        )
        $pathUnavailableButNameMatches = [string]::IsNullOrWhiteSpace($path) -and
            $knownNames -contains ([string]$process.Name)

        if ($pathIdentifiesPackage -or $commandIdentifiesPackage -or $pathUnavailableButNameMatches) {
            [pscustomobject]@{
                ProcessId = [int]$process.ProcessId
                Name = [string]$process.Name
                ExecutablePath = $path
                Identification = if ($pathIdentifiesPackage) {
                    'WindowsApps executable path'
                } elseif ($commandIdentifiesPackage) {
                    'WindowsApps command line'
                } else {
                    'process name; executable path unavailable'
                }
            }
        }
    }
}

function Wait-CodexProcessStart {
    [CmdletBinding()]
    param(
        [int[]]$ExistingProcessId = @(),
        [Parameter(Mandatory)][string]$ExpectedExecutable,
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $knownNames = @(@(Get-CodexProcessNames) + @([IO.Path]::GetFileName($ExpectedExecutable)) | Sort-Object -Unique)
    do {
        foreach ($process in @(Get-RunningCodexProcess -KnownProcessName $knownNames)) {
            if ($ExistingProcessId -notcontains $process.ProcessId) {
                return $process
            }
            if ($process.ExecutablePath -and
                [string]::Equals($process.ExecutablePath, $ExpectedExecutable, [StringComparison]::OrdinalIgnoreCase)) {
                return $process
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return $null
}
