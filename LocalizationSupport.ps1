function Get-DefaultGatewayLanguage {
    if ([Globalization.CultureInfo]::CurrentUICulture.Name -match '^(?i)zh') {
        return 'zh-CN'
    }
    return 'en-US'
}
function Import-GatewayLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('zh-CN', 'en-US')][string]$Language,
        [Parameter(Mandatory)][string]$LocalesDirectory
    )

    $localePath = Join-Path $LocalesDirectory "$Language.json"
    if (-not (Test-Path -LiteralPath $localePath -PathType Leaf)) {
        throw "Language resource does not exist: $localePath"
    }
    try {
        $json = [IO.File]::ReadAllText($localePath, [Text.Encoding]::UTF8)
        $locale = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Could not load language resource '$localePath': $($_.Exception.Message)"
    }
    if ([string]$locale.Language -ne $Language) {
        throw "Language resource '$localePath' declares '$($locale.Language)' instead of '$Language'."
    }
    $script:GatewayLanguage = $Language
    $script:GatewayText = $locale.Text
    return $locale
}

function Get-GatewayText {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(Position = 1)][object[]]$Values = @()
    )

    if (-not $script:GatewayText) {
        return $Key
    }
    $property = $script:GatewayText.PSObject.Properties[$Key]
    if (-not $property) {
        return "[$Key]"
    }
    $template = [string]$property.Value
    if ($Values.Count -gt 0) {
        return ($template -f $Values)
    }
    return $template
}
