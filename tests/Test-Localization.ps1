$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'LocalizationSupport.ps1')
$localesDirectory = Join-Path $projectRoot 'locales'

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}
$english = Import-GatewayLanguage -Language 'en-US' -LocalesDirectory $localesDirectory
$englishKeys = @($english.Text.PSObject.Properties.Name | Sort-Object)
Assert-Equal 'Default application: Example' (Get-GatewayText -Key 'DefaultApplication' -Values @('Example')) 'English formatting failed.'
Assert-Equal 'en-US' $script:GatewayLanguage 'English language state was not set.'

$chinese = Import-GatewayLanguage -Language 'zh-CN' -LocalesDirectory $localesDirectory
$chineseKeys = @($chinese.Text.PSObject.Properties.Name | Sort-Object)
Assert-Equal $englishKeys.Count $chineseKeys.Count 'Locale key counts differ.'
Assert-Equal ($englishKeys -join '|') ($chineseKeys -join '|') 'Locale keys differ.'
Assert-Equal 'zh-CN' $script:GatewayLanguage 'Chinese language state was not set.'
if ((Get-GatewayText -Key 'StartupKeys') -notmatch '\[S\]') {
    throw 'Chinese startup shortcut text was not loaded.'
}
Assert-Equal '[MissingKey]' (Get-GatewayText -Key 'MissingKey') 'Missing-key fallback is wrong.'

$defaultLanguage = Get-DefaultGatewayLanguage
if ($defaultLanguage -notin @('zh-CN', 'en-US')) {
    throw "Unsupported default language: $defaultLanguage"
}

Write-Host 'All localization resource tests passed.' -ForegroundColor Green
