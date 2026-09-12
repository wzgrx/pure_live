[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-pip-danmaku-settings-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

$adb = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
) | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ }
    else { [bool](Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $result = & $adb -s $Serial @AdbArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($AdbArguments -join ' ')`n$($result -join "`n")"
    }
    @($result)
}

function Get-Identity {
    $lines = Invoke-Adb -AdbArguments @('shell', 'getprop ro.product.model; getprop ro.product.device; su -c id')
    $text = $lines -join "`n"
    if ($text -notmatch "(?m)^$([regex]::Escape($ExpectedModel))\s*$" -or
        $text -notmatch "(?m)^$([regex]::Escape($ExpectedDevice))\s*$" -or
        $text -notmatch 'uid=0\(root\)') {
        throw "Unexpected target identity:`n$text"
    }
    [ordered]@{ model = $ExpectedModel; device = $ExpectedDevice; root = $true }
}

function Save-UiState {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remoteXml = "/sdcard/purelive-pip-settings-$PID-$Name.xml"
    $remotePng = "/sdcard/purelive-pip-settings-$PID-$Name.png"
    $localXml = Join-Path $evidence "$Name.xml"
    $localPng = Join-Path $evidence "$Name.png"
    try {
        Invoke-Adb -AdbArguments @('shell', 'timeout', '10', 'uiautomator', 'dump', '--compressed', $remoteXml) | Out-Null
        Invoke-Adb -AdbArguments @('shell', 'screencap', '-p', $remotePng) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remoteXml, $localXml) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remotePng, $localPng) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remoteXml, $remotePng) | Out-Null } catch {}
    }
    [xml][IO.File]::ReadAllText($localXml, [Text.Encoding]::UTF8)
}

function Get-BoundsCenter {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Unexpected UI bounds: $bounds"
    }
    [pscustomobject]@{
        Left = [int]$Matches[1]
        X = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
        Y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
        Top = [int]$Matches[2]
        Right = [int]$Matches[3]
        Bottom = [int]$Matches[4]
    }
}

function Get-SwitchNodes {
    param([Parameter(Mandatory = $true)][xml] $Document)
    @($Document.SelectNodes('//node') | Where-Object {
        [string]$_.class -eq 'android.widget.Switch' -and [string]$_.checkable -eq 'true'
    } | Sort-Object { (Get-BoundsCenter $_).Top })
}

function Test-ContainsAny {
    param([Parameter(Mandatory = $true)][string] $Text, [Parameter(Mandatory = $true)][string[]] $Candidates)
    foreach ($candidate in $Candidates) {
        if ($Text.Contains($candidate)) { return $true }
    }
    $false
}

function Assert-PipSettingsState {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][bool] $ExpectedEnabled,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $xmlText = $Document.OuterXml
    if (-not (Test-ContainsAny $xmlText @('样式预览', 'Style Preview'))) {
        throw "${Phase}: the fixed preview heading is missing."
    }
    $switches = @(Get-SwitchNodes $Document)
    if ($switches.Count -eq 0) { throw "${Phase}: the PiP danmaku switch is missing." }
    $actualEnabled = [string]$switches[0].checked -eq 'true'
    if ($actualEnabled -ne $ExpectedEnabled) {
        throw "${Phase}: expected enable=$ExpectedEnabled, got $actualEnabled."
    }
    $disabledVisible = Test-ContainsAny $xmlText @('小窗弹幕已关闭', 'PiP danmaku is disabled')
    if ($ExpectedEnabled) {
        if ($disabledVisible) { throw "${Phase}: the disabled preview overlay remained visible while enabled." }
        if ($switches.Count -lt 4) { throw "${Phase}: enabled controls did not expand." }
    } else {
        if (-not $disabledVisible) { throw "${Phase}: the disabled preview overlay is missing." }
        if ($switches.Count -ne 1) { throw "${Phase}: disabled controls did not collapse to the master switch." }
    }
    [ordered]@{
        enabled = $actualEnabled
        switchCount = $switches.Count
        disabledOverlayVisible = $disabledVisible
        firstSwitchBounds = [string]$switches[0].bounds
    }
}

function Open-PipSettings {
    param([Parameter(Mandatory = $true)][string] $Phase)
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    $routeOutput = @(& (Join-Path $PSScriptRoot 'android_ui.ps1') `
        -Sequence open_pip_danmaku_settings -Serial $Serial -CaptureOnFailure *>&1)
    if (-not $?) { throw ($routeOutput -join "`n") }
    $routeOutput | Set-Content -LiteralPath (Join-Path $evidence "$Phase-route.txt") -Encoding UTF8
    $joined = $routeOutput -join "`n"
    if ($joined -notmatch "tap semantic '" -or $joined -notmatch "assert semantic '") {
        throw "${Phase}: semantic route evidence is incomplete."
    }
}

function Tap-MasterSwitch {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $switch = @(Get-SwitchNodes $Document) | Select-Object -First 1
    if (-not $switch) { throw 'The PiP danmaku master switch is missing.' }
    $center = Get-BoundsCenter $switch
    # Flutter may merge a disabled Switch into the full row semantics bounds.
    # The trailing control itself remains about 180 px wide on the K90; tap its
    # stable right-side center rather than the merged row center.
    $tapX = $center.Right - [math]::Min(90, [math]::Floor(($center.Right - $center.Left) / 2))
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $tapX, $center.Y) | Out-Null
    Start-Sleep -Milliseconds 900
}

function Get-DeviceFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)
    $line = (Invoke-Adb -AdbArguments @('shell', "su -c `"sha256sum '$Path'`"")) -join "`n"
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Unexpected sha256sum output: $line" }
    $Matches[1].ToUpperInvariant()
}

$dataFile = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$remoteBackup = "/data/local/tmp/purelive-pip-settings-$PID-original.hive"
$remoteRestore = "/data/local/tmp/purelive-pip-settings-$PID-restore.hive"
$localBackup = Join-Path $evidence 'app_settings.original.hive'
$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    identity = $null
    originalEnabled = $null
    oppositeEnabled = $null
    states = [ordered]@{}
    settingsFile = [ordered]@{}
    checks = [ordered]@{}
}
$failure = $null
$settingsBackedUp = $false

try {
    $result.identity = Get-Identity
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    $statLine = (Invoke-Adb -AdbArguments @('shell', "su -c `"stat -c '%u:%g:%a' '$dataFile'`"")) -join ''
    if ($statLine -notmatch '^(\d+):(\d+):(\d+)$') { throw "Unexpected settings file metadata: $statLine" }
    $ownerUid = $Matches[1]
    $ownerGid = $Matches[2]
    $mode = $Matches[3]
    $result.settingsFile.metadata = $statLine
    $result.settingsFile.originalSha256 = Get-DeviceFileHash $dataFile
    Invoke-Adb -AdbArguments @(
        'shell',
        "su -c `"cp '$dataFile' '$remoteBackup' && chown shell:shell '$remoteBackup' && chmod 600 '$remoteBackup'`""
    ) | Out-Null
    Invoke-Adb -AdbArguments @('pull', $remoteBackup, $localBackup) | Out-Null
    $localOriginalHash = (Get-FileHash -LiteralPath $localBackup -Algorithm SHA256).Hash
    if ($localOriginalHash -ne $result.settingsFile.originalSha256) { throw 'The local settings backup hash differs from the device file.' }
    $settingsBackedUp = $true

    Open-PipSettings 'baseline'
    $baselineXml = Save-UiState 'baseline'
    $baselineSwitch = @(Get-SwitchNodes $baselineXml) | Select-Object -First 1
    if (-not $baselineSwitch) { throw 'baseline: the PiP danmaku master switch is missing.' }
    $originalEnabled = [string]$baselineSwitch.checked -eq 'true'
    $oppositeEnabled = -not $originalEnabled
    $result.originalEnabled = $originalEnabled
    $result.oppositeEnabled = $oppositeEnabled
    $result.states.baseline = Assert-PipSettingsState $baselineXml $originalEnabled 'baseline'

    Tap-MasterSwitch $baselineXml
    $oppositeXml = Save-UiState 'opposite-immediate'
    $result.states.oppositeImmediate = Assert-PipSettingsState $oppositeXml $oppositeEnabled 'opposite-immediate'

    Open-PipSettings 'opposite-relaunch'
    $oppositeRelaunchXml = Save-UiState 'opposite-relaunch'
    $result.states.oppositeRelaunch = Assert-PipSettingsState $oppositeRelaunchXml $oppositeEnabled 'opposite-relaunch'

    Tap-MasterSwitch $oppositeRelaunchXml
    $restoredXml = Save-UiState 'restored-immediate'
    $result.states.restoredImmediate = Assert-PipSettingsState $restoredXml $originalEnabled 'restored-immediate'

    Open-PipSettings 'restored-relaunch'
    $restoredRelaunchXml = Save-UiState 'restored-relaunch'
    $result.states.restoredRelaunch = Assert-PipSettingsState $restoredRelaunchXml $originalEnabled 'restored-relaunch'
    $result.checks.previewTracksMasterSwitch = $true
    $result.checks.oppositeStatePersistedAcrossRelaunch = $true
    $result.checks.originalStatePersistedAcrossRelaunch = $true
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    if ($settingsBackedUp) {
        try {
            Invoke-Adb -AdbArguments @('push', $localBackup, $remoteRestore) | Out-Null
            Invoke-Adb -AdbArguments @(
                'shell',
                "su -c `"cat '$remoteRestore' > '$dataFile' && chown ${ownerUid}:${ownerGid} '$dataFile' && chmod '$mode' '$dataFile' && restorecon '$dataFile'`""
            ) | Out-Null
            $result.settingsFile.restoredSha256 = Get-DeviceFileHash $dataFile
            $result.checks.settingsFileRestoredExactly = $result.settingsFile.restoredSha256 -eq $result.settingsFile.originalSha256
            if (-not $result.checks.settingsFileRestoredExactly -and -not $failure) {
                $failure = [InvalidOperationException]::new('The original settings file hash was not restored.')
            }
        } catch {
            $result.restoreError = $_.Exception.Message
            if (-not $failure) { $failure = $_ }
        }
    }
    try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remoteBackup, $remoteRestore) | Out-Null } catch {}
    try { Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $pidOutput = @(& $adb -s $Serial shell pidof $Package 2>&1)
    $pidExitCode = $LASTEXITCODE
    $result.checks.appStopped = $pidExitCode -in @(0, 1) -and [string]::IsNullOrWhiteSpace(($pidOutput -join ''))
    if (-not $result.checks.appStopped -and -not $failure) {
        $failure = [InvalidOperationException]::new("Pure Live remained active after cleanup: $($pidOutput -join ' ')")
    }
    $result.checks.passed = $null -eq $failure
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
# `pidof` uses exit code 1 for the expected absent-process state. The result was
# already classified above; do not leak that native code to the outer device-turn
# wrapper after a fully passing cleanup.
$global:LASTEXITCODE = 0
