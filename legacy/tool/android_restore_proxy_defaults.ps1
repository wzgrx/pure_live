[CmdletBinding()]
param(
    [string]$Serial = $env:PURELIVE_ADB_SERIAL,
    [string]$SessionPath,
    [string]$EvidenceDirectory,
    [switch]$KeepAppOpen
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$configure = Join-Path $PSScriptRoot 'android_configure_proxy.ps1'
$mode = if ($SessionPath) { 'Restore' } else { 'Disabled' }
# Without a session, only disable switches in the already foreground target.
# A journal supplies its own exact port; never fall back to removing tcp:7897.
& $configure -Serial $Serial -Mode $mode -SessionPath $SessionPath -EvidenceDirectory $EvidenceDirectory -KeepAppOpen:$KeepAppOpen
