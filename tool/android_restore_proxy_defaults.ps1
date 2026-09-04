[CmdletBinding()]
param(
    [string]$Serial,
    [string]$EvidenceDirectory,
    [switch]$KeepAppOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Backward-compatible cleanup entry point. The shared implementation also
# supports enabling the temporary adb-reversed Clash fixture for foreign-site
# runtime checks; normal device state remains direct/off after each test.
$configure = Join-Path $PSScriptRoot 'android_configure_proxy.ps1'
& $configure -Serial $Serial -Mode Disabled -EvidenceDirectory $EvidenceDirectory -KeepAppOpen:$KeepAppOpen
exit $LASTEXITCODE
