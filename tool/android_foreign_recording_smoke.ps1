[CmdletBinding()]
param(
    [string]$Serial = $env:PURELIVE_ADB_SERIAL,
    [ValidateSet('twitch', 'soop', 'picarto')]
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
$sessionDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) ('local-artifacts/diagnostics/foreign-proxy-session-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sessionDirectory)
$sessionPath = Join-Path $sessionDirectory 'session.json'

try {
    # Recording now requires the verified target app to remain foreground.
    & $configure -Serial $Serial -Mode LocalClash -Port $ProxyPort -KeepAppOpen -SessionPath $sessionPath -EvidenceDirectory $sessionDirectory
    if ($LASTEXITCODE -ne 0) { throw "Proxy setup exited with code $LASTEXITCODE." }

    $smokeParameters = @{
        Serial = $Serial
        Platform = $Platform
        RecordSeconds = $RecordSeconds
        PlatformLoadTimeoutSeconds = $PlatformLoadTimeoutSeconds
        ProxySessionPath = $sessionPath
    }
    if ($RequireLiveDanmaku) { $smokeParameters.RequireLiveDanmaku = $true }
    if ($ExerciseStreamSelection) { $smokeParameters.ExerciseStreamSelection = $true }
    & $smoke @smokeParameters
    if ($LASTEXITCODE -ne 0) { throw "$Platform recording smoke exited with code $LASTEXITCODE." }
} catch {
    $failure = $_
} finally {
    try {
        if (Test-Path -LiteralPath $sessionPath -PathType Leaf) {
            & $restore -Serial $Serial -SessionPath $sessionPath -EvidenceDirectory (Join-Path $sessionDirectory 'cleanup')
            if ($LASTEXITCODE -ne 0) { throw "Proxy cleanup exited with code $LASTEXITCODE." }
        }
    } catch {
        Write-Warning "Proxy cleanup requires attention; session: $sessionPath"
        if ($null -eq $failure) { $failure = $_ }
        else { Write-Error "Proxy cleanup also failed: $($_.Exception.Message)" -ErrorAction Continue }
    }
}

if ($null -ne $failure) { throw $failure }
