# Codex Gateway configuration
#
# Change AppPreference only when you want a different package-selection policy.
# Valid values: PreferBeta, PreferStable, BetaOnly, StableOnly
$GatewayConfig = [ordered]@{
    GatewayVersion         = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
    AppPreference          = 'PreferBeta'
    DefaultProxyHost       = '127.0.0.1'
    DefaultProxyPort       = 10808
    HealthCheckUrl         = 'https://api.openai.com/v1/models'
    ProxyProbeTimeoutMs    = 1500
    LaunchTimeoutSeconds   = 15
    UserAppsPath           = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexGateway\apps.json'
}
