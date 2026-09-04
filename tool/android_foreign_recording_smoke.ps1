[CmdletBinding()]
param(
    [string]$Serial = $env:PURELIVE_ADB_SERIAL,
    [ValidateSet('twitch', 'soop')]
    [string]$Platform = 'twitch',
    [ValidateRange(20, 300)]
    [int]$RecordSeconds = 20,
    [ValidateRange(10, 90)]
    [int]$PlatformLoadTimeoutSeconds = 60,
    [ValidateRange(1, 65535)]
    [int]$ProxyPort = 7897,
    [switch]$RequireLiveDanmaku,
    [switch]$ExerciseStreamSelection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configure = Join-Path $PSScriptRoot 'android_configure_proxy.ps1'
$smoke = Join-Path $PSScriptRoot 'android_recording_smoke.ps1'
$restore = Join-Path $PSScriptRoot 'android_restore_proxy_defaults.ps1'
$failure = $null

try {
    & $configure -Serial $Serial -Mode LocalClash -Port $ProxyPort
    if ($LASTEXITCODE -ne 0) { throw "Proxy setup exited with code $LASTEXITCODE." }

    $smokeParameters = @{
        Serial = $Serial
        Platform = $Platform
        RecordSeconds = $RecordSeconds
        PlatformLoadTimeoutSeconds = $PlatformLoadTimeoutSeconds
    }
    if ($RequireLiveDanmaku) { $smokeParameters.RequireLiveDanmaku = $true }
    if ($ExerciseStreamSelection) { $smokeParameters.ExerciseStreamSelection = $true }
    & $smoke @smokeParameters
    if ($LASTEXITCODE -ne 0) { throw "$Platform recording smoke exited with code $LASTEXITCODE." }
} catch {
    $failure = $_
} finally {
    try {
        & $restore -Serial $Serial
        if ($LASTEXITCODE -ne 0) { throw "Proxy cleanup exited with code $LASTEXITCODE." }
    } catch {
        if ($null -eq $failure) { $failure = $_ }
        else { Write-Error "Proxy cleanup also failed: $($_.Exception.Message)" -ErrorAction Continue }
    }
}

if ($null -ne $failure) { throw $failure }
