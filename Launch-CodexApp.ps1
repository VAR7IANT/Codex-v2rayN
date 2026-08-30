[CmdletBinding()]
param(
    [ValidateSet('Launch', 'Check', 'Settings')]
    [string]$Mode = 'Launch',
    [string]$UserAppsPath,
    [switch]$PauseOnError
)

$ErrorActionPreference = 'Stop'
$script:UiFrame = [Collections.Generic.List[object]]::new()
$script:UiLastConsoleWidth = 0
$script:UiIsRendering = $false

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

function Get-UiConsoleWidth {
    try {
        $width = [Console]::WindowWidth
        if ($width -ge 20) { return $width }
    } catch {}
    return 80
}

function Test-UiInteractive {
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and [Console]::WindowWidth -ge 20
    } catch {
        return $false
    }
}

function Get-UiPanelWidth {
    $consoleWidth = Get-UiConsoleWidth
    return [Math]::Max(20, [Math]::Min(76, $consoleWidth - 4))
}

function Get-UiMargin {
    $marginWidth = [Math]::Max(0, [Math]::Floor(((Get-UiConsoleWidth) - (Get-UiPanelWidth)) / 2))
    return (' ' * $marginWidth)
}

function Get-UiDisplayWidth {
    param([AllowEmptyString()][string]$Text)

    $width = 0
    foreach ($character in $Text.ToCharArray()) {
        $code = [int]$character
        $isWide = ($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE10 -and $code -le 0xFE6F) -or
            ($code -ge 0xFF01 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        $width += if ($isWide) { 2 } else { 1 }
    }
    return $width
}

function Split-UiText {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateRange(4, 500)][int]$MaxWidth
    )

    $result = [Collections.Generic.List[string]]::new()
    foreach ($sourceLine in @($Text -split '\r?\n')) {
        $remaining = [string]$sourceLine
        if ($remaining.Length -eq 0) {
            $result.Add('')
            continue
        }

        while ((Get-UiDisplayWidth $remaining) -gt $MaxWidth) {
            $usedWidth = 0
            $fitCount = 0
            $lastWhitespace = -1
            for ($index = 0; $index -lt $remaining.Length; $index++) {
                $character = [string]$remaining[$index]
                $characterWidth = Get-UiDisplayWidth $character
                if (($usedWidth + $characterWidth) -gt $MaxWidth) { break }
                $usedWidth += $characterWidth
                $fitCount = $index + 1
                if ([char]::IsWhiteSpace($remaining[$index])) { $lastWhitespace = $index }
            }

            if ($fitCount -lt 1) { $fitCount = 1 }
            $breakCount = if ($lastWhitespace -gt 0) { $lastWhitespace } else { $fitCount }
            $line = $remaining.Substring(0, $breakCount).TrimEnd()
            if ($line.Length -eq 0) { $line = $remaining.Substring(0, $fitCount) }
            $result.Add($line)

            $consumed = if ($lastWhitespace -gt 0) { $lastWhitespace + 1 } else { $fitCount }
            while ($consumed -lt $remaining.Length -and [char]::IsWhiteSpace($remaining[$consumed])) { $consumed++ }
            $remaining = $remaining.Substring($consumed)
        }
        $result.Add($remaining)
    }
    return $result.ToArray()
}

function Write-UiLineCore {
    param(
        [AllowEmptyString()][string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [ValidateSet('Left', 'Center')][string]$Align = 'Left',
        [ValidateRange(0, 8)][int]$Indent = 0
    )

    $panelWidth = Get-UiPanelWidth
    $contentWidth = if ($Align -eq 'Center') { $panelWidth } else { [Math]::Max(4, $panelWidth - $Indent) }
    foreach ($line in @(Split-UiText -Text $Text -MaxWidth $contentWidth)) {
        $prefix = Get-UiMargin
        if ($Align -eq 'Center') {
            $padding = [Math]::Max(0, [Math]::Floor(($panelWidth - (Get-UiDisplayWidth $line)) / 2))
            $prefix += (' ' * $padding)
        } else {
            $prefix += (' ' * $Indent)
        }
        Write-Host ($prefix + $line) -ForegroundColor $Color
    }
}

function Write-UiRuleCore {
    param(
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan,
        [char]$Character = [char]0x2500
    )
    Write-Host ((Get-UiMargin) + ([string]$Character * (Get-UiPanelWidth))) -ForegroundColor $Color
}

function Redraw-UiFrame {
    if (-not (Test-UiInteractive) -or $script:UiIsRendering) { return }

    $script:UiIsRendering = $true
    try {
        Clear-Host
        foreach ($record in $script:UiFrame) {
            switch ($record.Kind) {
                'Line' {
                    Write-UiLineCore -Text $record.Text -Color $record.Color -Align $record.Align -Indent $record.Indent
                }
                'Rule' {
                    Write-UiRuleCore -Color $record.Color -Character $record.Character
                }
                'Blank' {
                    Write-Host ''
                }
            }
        }
        $script:UiLastConsoleWidth = Get-UiConsoleWidth
    } finally {
        $script:UiIsRendering = $false
    }
}

function Sync-UiLayout {
    if (-not (Test-UiInteractive) -or $script:UiIsRendering) { return $false }

    $currentWidth = Get-UiConsoleWidth
    if ($script:UiLastConsoleWidth -eq 0) {
        $script:UiLastConsoleWidth = $currentWidth
        return $false
    }
    if ($currentWidth -eq $script:UiLastConsoleWidth) { return $false }

    Redraw-UiFrame
    return $true
}

function Start-UiFrame {
    $script:UiFrame.Clear()
    $script:UiLastConsoleWidth = Get-UiConsoleWidth
    Clear-Host
}

function Write-UiLine {
    param(
        [AllowEmptyString()][string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [ValidateSet('Left', 'Center')][string]$Align = 'Left',
        [ValidateRange(0, 8)][int]$Indent = 0
    )

    [void](Sync-UiLayout)
    $script:UiFrame.Add([pscustomobject]@{
        Kind = 'Line'; Text = $Text; Color = $Color; Align = $Align; Indent = $Indent
    })
    Write-UiLineCore -Text $Text -Color $Color -Align $Align -Indent $Indent
}

function Write-UiRule {
    param(
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan,
        [char]$Character = [char]0x2500
    )

    [void](Sync-UiLayout)
    $script:UiFrame.Add([pscustomobject]@{
        Kind = 'Rule'; Color = $Color; Character = $Character
    })
    Write-UiRuleCore -Color $Color -Character $Character
}

function Write-UiBlank {
    [void](Sync-UiLayout)
    $script:UiFrame.Add([pscustomobject]@{ Kind = 'Blank' })
    Write-Host ''
}

function Write-UiBrand {
    Write-UiBlank
    Write-UiRule -Color DarkCyan -Character ([char]0x2550)
    Write-UiLine -Text 'CODEX GATEWAY' -Color Cyan -Align Center
    Write-UiLine -Text (T 'Subtitle') -Color DarkCyan -Align Center
    Write-UiRule -Color DarkCyan
}

function Read-UiInput {
    param([Parameter(Mandatory)][string]$Prompt)
    Write-UiLine -Text $Prompt -Color Gray -Indent 2

    if (-not (Test-UiInteractive)) {
        return Read-Host ((Get-UiMargin) + '  >')
    }

    $inputText = ''
    Write-UiLineCore -Text '> ' -Color White -Indent 2
    while ($true) {
        if (Sync-UiLayout) {
            Write-UiLineCore -Text ("> $inputText") -Color White -Indent 2
        }
        if (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            continue
        }

        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Enter) {
            $script:UiFrame.Add([pscustomobject]@{
                Kind = 'Line'; Text = "> $inputText"; Color = [ConsoleColor]::White; Align = 'Left'; Indent = 2
            })
            return $inputText
        }
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($inputText.Length -gt 0) { $inputText = $inputText.Substring(0, $inputText.Length - 1) }
        } elseif ($key.Key -eq [ConsoleKey]::Escape) {
            $inputText = ''
        } elseif ($key.KeyChar -ne [char]0) {
            $inputText += [string]$key.KeyChar
        } else {
            continue
        }

        Redraw-UiFrame
        Write-UiLineCore -Text ("> $inputText") -Color White -Indent 2
    }
}

function Wait-UiClose {
    $message = 'Press any key to close this window.'
    if ($script:GatewayText) {
        $property = $script:GatewayText.PSObject.Properties['PressAnyKeyToClose']
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $message = [string]$property.Value
        }
    }

    Write-UiBlank
    Write-UiLine -Text $message -Color Cyan -Align Center
    try {
        if (-not [Console]::IsInputRedirected) {
            while ($true) {
                [void](Sync-UiLayout)
                if ([Console]::KeyAvailable) {
                    [void][Console]::ReadKey($true)
                    return
                }
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {}
    [void](Read-Host)
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

    Start-UiFrame
    Write-UiBrand
    Write-UiBlank
    Write-UiLine -Text (('{0}  {1}  {2}' -f $socksUrl, $Proxy.Kind.ToUpperInvariant(), (T 'CurrentLaunchOnly'))) -Color White -Align Center
    Write-UiBlank
    Write-UiLine -Text ('{0}: {1}' -f (T 'GatewayVersion'), $GatewayVersion) -Color DarkGray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'DefaultApp'), $ApplicationName) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'Endpoint'), $socksUrl) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'InboundType'), $Proxy.Kind) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'DetectedFrom'), $Proxy.Source) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'Environment'), $environmentLabel) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'SessionScope'), (T 'CurrentLaunchOnly')) -Color Gray -Indent 2
    Write-UiLine -Text ('{0}: {1}' -f (T 'WindowsProxy'), (T 'Unchanged')) -Color Gray -Indent 2
    Write-UiBlank
    Write-UiRule -Color DarkCyan
    Write-UiBlank
}

function Write-Step {
    param([string]$Number, [string]$Message)
    Write-UiLine -Text ("[{0}]  {1}..." -f $Number, $Message) -Color Cyan
}

function Write-Success {
    param([string]$Message)
    Write-UiLine -Text ("[OK]  {0}" -f $Message) -Color Green -Indent 7
}

function Write-Failure {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string[]]$Detail = @()
    )

    Write-UiLine -Text (T 'Failed') -Color Red -Indent 7
    Write-UiBlank
    Write-UiRule -Color Red
    Write-UiLine -Text (T 'GatewayStopped') -Color Red -Align Center
    Write-UiRule -Color Red
    Write-UiBlank
    Write-UiLine -Text $Reason -Color Red -Indent 2
    foreach ($line in $Detail) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-UiLine -Text $line -Color Gray -Indent 2
        }
    }
    Write-UiBlank
}

function Wait-ForStartupAction {
    param(
        [Parameter(Mandatory)][string]$DefaultApplicationName,
        [ValidateRange(0, 60)][int]$DelaySeconds = 2
    )

    Start-UiFrame
    Write-UiBrand
    Write-UiBlank
    Write-UiLine -Text (T 'DefaultApplication' @($DefaultApplicationName)) -Color White -Align Center
    Write-UiBlank
    Write-UiLine -Text (T 'StartupKeys') -Color Cyan -Align Center
    Write-UiLine -Text (T 'AutoLaunch' @($DelaySeconds)) -Color Yellow -Align Center
    Write-UiBlank
    Write-UiRule -Color DarkCyan

    if ($DelaySeconds -eq 0) {
        return 'Launch'
    }

    try {
        if ([Console]::IsInputRedirected) {
            return 'Launch'
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($DelaySeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            [void](Sync-UiLayout)
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
    [void](Read-UiInput (T 'PressEnter'))
}

function Add-GatewayCustomApplication {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    Write-UiBlank
    Write-UiLine -Text (T 'AddTitle') -Color White -Indent 2
    Write-UiLine -Text (T 'AddHint') -Color DarkGray -Indent 2
    $pathInput = Read-UiInput (T 'ExecutableBlankCancels')
    if ([string]::IsNullOrWhiteSpace($pathInput)) {
        return $Configuration
    }
    $executablePath = ConvertTo-CustomExecutablePath -InputPath $pathInput
    $suggestedName = [IO.Path]::GetFileNameWithoutExtension($executablePath)
    $name = Read-UiInput (T 'DisplayNamePrompt' @($suggestedName))
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $suggestedName
    }
    $arguments = Read-UiInput (T 'ArgumentsOptional')
    $workingDirectory = Read-UiInput (T 'WorkingDirectoryDefault' @((Split-Path -Parent $executablePath)))

    $newApp = [pscustomobject]@{
        Id = 'custom-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        Name = $name.Trim()
        ExecutablePath = $executablePath
        Arguments = [string]$arguments
        WorkingDirectory = [string]$workingDirectory
    }
    $Configuration.Apps = @($Configuration.Apps) + @($newApp)

    $makeDefault = Read-UiInput (T 'SetDefaultPrompt')
    if ([string]::IsNullOrWhiteSpace($makeDefault) -or $makeDefault -match '^(?i)y(es)?$') {
        $Configuration.DefaultAppId = $newApp.Id
    }
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-UiLine -Text (T 'AddedApplication' @($newApp.Name)) -Color Green -Indent 2
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
        Write-UiLine -Text (T 'NoCustomApps') -Color Red -Indent 2
        Pause-SettingsScreen
        return -1
    }
    Write-UiBlank
    for ($index = 0; $index -lt $customApps.Count; $index++) {
        Write-UiLine -Text ("[{0}] {1}" -f ($index + 1), $customApps[$index].Name) -Color Cyan -Indent 2
    }
    $selection = Read-UiInput (T 'ApplicationNumber' @($ActionName))
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return -1
    }
    $number = 0
    if (-not [int]::TryParse($selection, [ref]$number) -or $number -lt 1 -or $number -gt $customApps.Count) {
        Write-UiLine -Text (T 'InvalidApplicationNumber') -Color Red -Indent 2
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

    Write-UiBlank
    $name = Read-UiInput (T 'DisplayNamePrompt' @($app.Name))
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        $app.Name = $name.Trim()
    }
    $pathInput = Read-UiInput ("{0} [{1}]" -f (T 'ExecutableLabel'), $app.ExecutablePath)
    if (-not [string]::IsNullOrWhiteSpace($pathInput)) {
        $app.ExecutablePath = ConvertTo-CustomExecutablePath -InputPath $pathInput
    }
    $arguments = Read-UiInput (T 'ArgumentsEdit')
    if ($arguments -eq '-') {
        $app.Arguments = ''
    } elseif (-not [string]::IsNullOrWhiteSpace($arguments)) {
        $app.Arguments = $arguments
    }
    $workingDirectory = Read-UiInput (T 'WorkingDirectoryEdit')
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
    Write-UiLine -Text (T 'UpdatedApplication' @($app.Name)) -Color Green -Indent 2
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
    $confirmation = Read-UiInput (T 'RemoveConfirmation' @($app.Name))
    if ($confirmation -notmatch '^(?i)y(es)?$') {
        return $Configuration
    }

    $Configuration.Apps = @($customApps | Where-Object Id -ne $app.Id)
    if ($Configuration.DefaultAppId -eq $app.Id) {
        $Configuration.DefaultAppId = 'codex'
    }
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-UiLine -Text (T 'RemovedApplication' @($app.Name)) -Color Green -Indent 2
    Pause-SettingsScreen
    return $Configuration
}

function Set-GatewayInterfaceLanguage {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][string]$LocalesDirectory
    )

    Write-UiBlank
    Write-UiLine -Text (T 'ChooseLanguage') -Color White -Indent 2
    Write-UiLine -Text (T 'ChineseLanguage') -Color Cyan -Indent 2
    Write-UiLine -Text (T 'EnglishLanguage') -Color Cyan -Indent 2
    $selection = Read-UiInput (T 'LanguageSelection')
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Configuration
    }
    $language = switch ($selection.Trim()) {
        '1' { 'zh-CN' }
        '2' { 'en-US' }
        default { $null }
    }
    if (-not $language) {
        Write-UiLine -Text (T 'UnknownSelection') -Color Red -Indent 2
        Pause-SettingsScreen
        return $Configuration
    }

    $Configuration.Language = $language
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    $locale = Import-GatewayLanguage -Language $language -LocalesDirectory $LocalesDirectory
    Write-UiLine -Text (T 'LanguageChanged' @($locale.DisplayName)) -Color Green -Indent 2
    Pause-SettingsScreen
    return $Configuration
}

function Set-GatewayStartupDelay {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    $policy = Get-GatewayStartupDelayPolicy
    Write-UiBlank
    Write-UiLine -Text (T 'StartupDelayTitle') -Color White -Indent 2
    $selection = Read-UiInput (T 'StartupDelayPrompt' @(
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
        Write-UiLine -Text (T 'StartupDelayInvalid' @($policy.MinimumSeconds, $policy.MaximumSeconds)) -Color Red -Indent 2
        Pause-SettingsScreen
        return $Configuration
    }

    $Configuration.StartupDelaySeconds = $seconds
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    Write-UiLine -Text (T 'StartupDelayChanged' @($seconds)) -Color Green -Indent 2
    Pause-SettingsScreen
    return $Configuration
}

function Set-GatewayProxyPort {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )

    $currentValue = if ($null -eq $Configuration.ProxyPortOverride) { T 'ProxyPortAuto' } else { [string]$Configuration.ProxyPortOverride }
    Write-UiBlank
    Write-UiLine -Text (T 'ProxyPortTitle') -Color White -Indent 2
    Write-UiLine -Text (T 'ProxyPortAutoHint') -Color DarkGray -Indent 2
    $selection = Read-UiInput (T 'ProxyPortPrompt' @($currentValue))
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Configuration
    }

    try {
        $port = ConvertTo-GatewayProxyPortOverride -Value $selection -AllowAuto
    } catch {
        Write-UiLine -Text (T 'ProxyPortInvalid') -Color Red -Indent 2
        Pause-SettingsScreen
        return $Configuration
    }

    $Configuration.ProxyPortOverride = $port
    Save-GatewayUserConfiguration -Configuration $Configuration -Path $ConfigurationPath
    if ($null -eq $port) {
        Write-UiLine -Text (T 'ProxyPortAutoChanged') -Color Green -Indent 2
    } else {
        Write-UiLine -Text (T 'ProxyPortChanged' @($port)) -Color Green -Indent 2
    }
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
        Start-UiFrame
        $profiles = @(Get-GatewayAppProfiles -Configuration $Configuration)
        Write-UiBrand
        Write-UiBlank
        Write-UiLine -Text (T 'SettingsTitle') -Color White -Align Center
        Write-UiLine -Text (T 'ConfigurationPath' @($ConfigurationPath)) -Color DarkGray -Indent 2
        Write-UiBlank
        Write-UiLine -Text (T 'ApplicationsInstruction') -Color Gray -Indent 2
        for ($index = 0; $index -lt $profiles.Count; $index++) {
            $defaultMarker = if ($profiles[$index].Id -eq $Configuration.DefaultAppId) { T 'DefaultMarker' } else { '' }
            $profileColor = if ($profiles[$index].Id -eq $Configuration.DefaultAppId) { 'Green' } else { 'Cyan' }
            Write-UiLine -Text ("[{0}] {1}{2}" -f ($index + 1), $profiles[$index].Name, $defaultMarker) -Color $profileColor -Indent 4
        }
        Write-UiBlank
        Write-UiRule -Color DarkCyan
        Write-UiBlank
        Write-UiLine -Text (T 'AddMenu') -Color Cyan -Indent 4
        Write-UiLine -Text (T 'EditMenu') -Color Cyan -Indent 4
        Write-UiLine -Text (T 'DeleteMenu') -Color Cyan -Indent 4
        Write-UiLine -Text (T 'LanguageMenu') -Color Cyan -Indent 4
        Write-UiLine -Text (T 'StartupDelayMenu' @($Configuration.StartupDelaySeconds)) -Color Cyan -Indent 4
        $proxyPortDisplay = if ($null -eq $Configuration.ProxyPortOverride) { T 'ProxyPortAuto' } else { [string]$Configuration.ProxyPortOverride }
        Write-UiLine -Text (T 'ProxyPortMenu' @($proxyPortDisplay)) -Color Cyan -Indent 4
        Write-UiBlank
        Write-UiLine -Text (T 'LaunchMenu') -Color White -Indent 4
        Write-UiLine -Text (T 'ExitMenu') -Color DarkGray -Indent 4
        Write-UiBlank

        $choice = Read-UiInput (T 'Selection')
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
                'P' { $Configuration = Set-GatewayProxyPort -Configuration $Configuration -ConfigurationPath $ConfigurationPath }
                'Q' { return [pscustomobject]@{ Action = 'Exit'; Configuration = $Configuration } }
                default {
                    Write-UiLine -Text (T 'UnknownSelection') -Color Red -Indent 2
                    Pause-SettingsScreen
                }
            }
        } catch {
            Write-UiLine -Text (T 'SettingsError' @($_.Exception.Message)) -Color Red -Indent 2
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
    Write-UiLine -Text ("{0}: {1}" -f (T 'TypeLabel'), $Application.Type) -Color Gray -Indent 7
    Write-UiLine -Text ("{0}: {1}" -f (T 'VariantLabel'), $Application.Variant) -Color Gray -Indent 7
    Write-UiLine -Text ("{0}: {1}" -f (T 'VersionLabel'), $Application.Version) -Color Gray -Indent 7
    if ($Application.PackageName -ne '-') {
        Write-UiLine -Text ("{0}: {1}" -f (T 'PackageNameLabel'), $Application.PackageName) -Color Gray -Indent 7
    }
    Write-UiLine -Text ("{0}: {1}" -f (T 'ExecutableLabel'), $Application.ExecutablePath) -Color Gray -Indent 7
    Write-UiLine -Text ("{0}: {1}" -f (T 'ResolvedFromLabel'), $Application.ExecutableSource) -Color Gray -Indent 7
    if (-not [string]::IsNullOrWhiteSpace($Application.Arguments)) {
        Write-UiLine -Text ("Arguments: {0}" -f (T 'ArgumentsConfigured')) -Color Gray -Indent 7
    }
    Write-UiBlank
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
        $proxyPortMode = if ($null -eq $userConfiguration.ProxyPortOverride) { 'Auto' } else { "Manual:$($userConfiguration.ProxyPortOverride)" }
        Write-GatewayLog -Level Info -Message ("Gateway started. Version={0}; Mode={1}; DefaultApp={2}; AppType={3}; AppPreference={4}; ProxyPortMode={5}" -f $GatewayConfig.GatewayVersion, $Mode, $defaultProfile.Name, $defaultProfile.Type, $GatewayConfig.AppPreference, $proxyPortMode)
    } catch {
        Write-Failure -Reason (T 'LogFailed') -Detail @("Log directory: $PSScriptRoot\logs", $_.Exception.Message)
        return $ExitCode.Logging
    }

    try {
        $resolverParameters = @{
            DefaultHost = $GatewayConfig.DefaultProxyHost
            DefaultPort = $GatewayConfig.DefaultProxyPort
            OutputFormat = 'Object'
        }
        if ($null -ne $userConfiguration.ProxyPortOverride) {
            $resolverParameters.OverridePort = [int]$userConfiguration.ProxyPortOverride
        }
        $proxy = & (Join-Path $PSScriptRoot 'Resolve-v2rayNProxy.ps1') @resolverParameters
        if (-not $proxy) { throw 'The proxy resolver returned no endpoint.' }
        Set-SessionProxyEnvironment -Proxy $proxy
        Write-GatewayLog -Level Info -Message ("Proxy endpoint={0}:{1}; Kind={2}; Source={3}" -f $proxy.Host, $proxy.Port, $proxy.Kind, $proxy.Source)
        foreach ($warning in @($proxy.Warnings)) { Write-GatewayLog -Level Warning -Message $warning }
    } catch {
        $requestedPort = if ($null -eq $userConfiguration.ProxyPortOverride) { $GatewayConfig.DefaultProxyPort } else { $userConfiguration.ProxyPortOverride }
        $requestedMode = if ($null -eq $userConfiguration.ProxyPortOverride) { T 'ProxyPortAuto' } else { T 'ProxyPortManual' }
        Write-Failure -Reason (T 'ProxyResolveFailed') -Detail @("$requestedMode`: $($GatewayConfig.DefaultProxyHost):$requestedPort", $_.Exception.Message)
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
    Write-UiBlank

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
        Write-UiBlank
        Write-UiRule -Color Green -Character ([char]0x2550)
        Write-UiLine -Text (T 'CheckComplete') -Color Green -Align Center
        Write-UiLine -Text (T 'CheckPassed') -Color Green -Align Center
        Write-UiLine -Text (T 'NothingLaunched') -Color DarkGreen -Align Center
        Write-UiRule -Color Green -Character ([char]0x2550)
        Write-UiBlank
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
    Write-UiBlank
    Write-UiRule -Color Green -Character ([char]0x2550)
    Write-UiLine -Text (T 'Ready') -Color Green -Align Center
    Write-UiLine -Text (T 'ReadyProxy') -Color Green -Align Center
    Write-UiLine -Text (T 'ReadyWindows') -Color DarkGreen -Align Center
    Write-UiRule -Color Green -Character ([char]0x2550)
    Write-UiBlank
    Write-GatewayLog -Level Info -Message ("Launch succeeded. App={0}; Type={1}; ObservedPID={2}" -f $application.DisplayName, $application.Type, $observed.ProcessId)
    return $ExitCode.Success
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

try {
    $result = Invoke-CodexGateway
    if ($result -ne $ExitCode.Success -and $PauseOnError) { Wait-UiClose }
    exit $result
} catch {
    if ($script:LogPath) {
        try { Write-GatewayLog -Level Error -Message ("Unexpected error. $($_.Exception.Message)") } catch {}
    }
    Write-Failure -Reason (T 'UnexpectedError') -Detail @($_.Exception.Message)
    if ($PauseOnError) { Wait-UiClose }
    exit $ExitCode.Unexpected
}
