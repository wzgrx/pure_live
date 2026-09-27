[CmdletBinding()]
param(
    [string]$Serial = $env:PURELIVE_ADB_SERIAL,
    [ValidateSet('Disabled', 'LocalClash', 'Restore')]
    [string]$Mode = 'Disabled',
    [ValidateRange(1, 65535)][int]$Port = 7897,
    [string]$EvidenceDirectory,
    [string]$SessionPath,
    [switch]$KeepAppOpen
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_recording_navigation.ps1')
. (Join-Path $PSScriptRoot 'android_proxy_session.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'ADB executable was not found.' }
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $repo ('local-artifacts/diagnostics/android-proxy-' + [Guid]::NewGuid().ToString('N'))
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
if ($SessionPath) { $SessionPath = [IO.Path]::GetFullPath($SessionPath) }
if ($Mode -eq 'Restore' -and -not $SessionPath) { throw 'Restore requires the exact proxy SessionPath.' }
# Validate a supplied cleanup journal before any device commands.
$session = if ($Mode -eq 'Restore') { Read-ProxySession $SessionPath $Serial } else { $null }
Initialize-ProxyContext -Serial $Serial -AdbExecutable $adb -EvidenceDirectory $EvidenceDirectory
if ($Mode -eq 'LocalClash') {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $connection.Wait(3000) -or -not $client.Connected) { throw 'Local Clash listener did not respond.' }
    } finally { $client.Dispose() }
    if (-not $SessionPath) { $SessionPath = Join-Path $EvidenceDirectory 'session.json' }
    Start-ProxySession -Port $Port -Path $SessionPath | Out-Null
} elseif ($Mode -eq 'Restore') {
    Restore-ProxySession $session $SessionPath -AllowHomeLaunch
} else {
    # Explicit default-off operation has no reverse ownership and removes none.
    Assert-ProxyForeground
    Open-ProxySettings
    Set-ProxySwitch '启用播放代理' $false
    Set-ProxySwitch '启用应用层代理' $false
}
if (-not $KeepAppOpen) {
    Invoke-ProxyAdb @('shell','am','force-stop','com.mystyle.purelive') | Out-Null
}
$summary = Join-Path $EvidenceDirectory 'summary.json'
[ordered]@{
    serial=$Serial;mode=$Mode;sessionPath=$SessionPath
    proxyPort=if($null -ne $session){$session.port}else{$Port}
    status='succeeded';completedAt=[DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output $summary
