[CmdletBinding()]
param(
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-recording-center-boundary-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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

& $adb start-server | Out-Null
if (-not $Serial) {
    $devices = @(& $adb devices | ForEach-Object { if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] } })
    $network = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($devices.Count -eq 1) { $Serial = $devices[0] }
    elseif ($network.Count -eq 1) { $Serial = $network[0] }
    else { throw 'Specify -Serial because a unique Android device was not found.' }
}

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $result = & $adb -s $Serial @AdbArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($AdbArguments -join ' ')`n$($result -join "`n")"
    }
    $result
}

function Save-UiDump {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remote = "/sdcard/purelive-$PID-$Name.xml"
    $local = Join-Path $evidence "$Name.xml"
    try {
        Invoke-Adb -AdbArguments @('shell', 'timeout', '10', 'uiautomator', 'dump', '--compressed', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, $local) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
    [xml](Get-Content -LiteralPath $local -Raw -Encoding UTF8)
}

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remote = "/sdcard/purelive-$PID-$Name.png"
    try {
        Invoke-Adb -AdbArguments @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
}

function Invoke-RepeatedSwipe {
    param(
        [Parameter(Mandatory = $true)][int] $X1,
        [Parameter(Mandatory = $true)][int] $Y1,
        [Parameter(Mandatory = $true)][int] $X2,
        [Parameter(Mandatory = $true)][int] $Y2,
        [Parameter(Mandatory = $true)][int] $Count,
        [int] $DurationMs = 160
    )
    for ($i = 0; $i -lt $Count; $i++) {
        Invoke-Adb -AdbArguments @('shell', 'input', 'swipe', $X1, $Y1, $X2, $Y2, $DurationMs) | Out-Null
        Start-Sleep -Milliseconds 60
    }
}

function Get-VisibleSignature {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $parts = @($Document.SelectNodes('//node') | ForEach-Object {
        $text = ([string]$_.text).Trim()
        $description = ([string]$_.'content-desc').Trim()
        if ($text) { "text=$text|bounds=$([string]$_.bounds)" }
        if ($description) { "desc=$description|bounds=$([string]$_.bounds)" }
    })
    $payload = $parts -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload)))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    checks = [ordered]@{}
}
$failure = $null
try {
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
    & (Join-Path $repo 'tool\android_ui.ps1') -TapSemantic '录制中心' -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Opening the recording center failed.' }
    Start-Sleep -Seconds 2

    $initial = Save-UiDump 'initial'
    $labels = @('全部', '录制中', '等待开播', '排队中', '重连中', '处理中', '已完成', '失败', '已停止')
    $missing = @($labels | Where-Object { -not $initial.OuterXml.Contains($_) })
    $result.checks.allStatusSelectorsVisible = $missing.Count -eq 0
    $result.checks.missingStatusSelectors = $missing
    $result.checks.hasScrollableTaskList = $null -ne ($initial.SelectNodes('//node') | Where-Object {
        [string]$_.scrollable -eq 'true' -and [string]$_.bounds -match '^\[0,(?:[5-9]\d\d|\d{4})\]'
    } | Select-Object -First 1)
    if ($missing.Count -gt 0) { throw "Recording status selectors are missing: $($missing -join ', ')" }
    Save-Screenshot 'initial'

    # The selector is a fixed grid and TabBarView deliberately rejects swipe
    # navigation. Repeated gestures over both the selector and task surface must
    # therefore keep all status controls visible and retain the All page.
    Invoke-RepeatedSwipe -X1 1100 -Y1 430 -X2 100 -Y2 430 -Count 12
    Invoke-RepeatedSwipe -X1 100 -Y1 430 -X2 1100 -Y2 430 -Count 12
    Invoke-RepeatedSwipe -X1 1100 -Y1 1200 -X2 100 -Y2 1200 -Count 8
    Invoke-RepeatedSwipe -X1 100 -Y1 1200 -X2 1100 -Y2 1200 -Count 8
    Start-Sleep -Milliseconds 500
    $horizontal = Save-UiDump 'after-horizontal-stress'
    $result.checks.horizontalGesturesKeepSelectorFixed = @($labels | Where-Object { -not $horizontal.OuterXml.Contains($_) }).Count -eq 0
    $result.checks.horizontalGesturesKeepRecordingCenter = $horizontal.OuterXml.Contains('录制中心')
    Save-Screenshot 'after-horizontal-stress'

    # Reach each vertical hard edge, then compare against additional same-way
    # swipes. Completed/stopped cards are stable, so identical visible semantic
    # signatures prove the list did not drift beyond either boundary.
    Invoke-RepeatedSwipe -X1 600 -Y1 2200 -X2 600 -Y2 760 -Count 24
    Start-Sleep -Milliseconds 700
    $bottomA = Save-UiDump 'bottom-boundary-a'
    Invoke-RepeatedSwipe -X1 600 -Y1 2200 -X2 600 -Y2 760 -Count 8
    Start-Sleep -Milliseconds 700
    $bottomB = Save-UiDump 'bottom-boundary-b'
    $bottomSignatureA = Get-VisibleSignature $bottomA
    $bottomSignatureB = Get-VisibleSignature $bottomB
    $result.checks.bottomBoundaryStable = $bottomSignatureA -eq $bottomSignatureB
    $result.checks.bottomSignature = $bottomSignatureB
    Save-Screenshot 'bottom-boundary'

    Invoke-RepeatedSwipe -X1 600 -Y1 760 -X2 600 -Y2 2200 -Count 24
    Start-Sleep -Milliseconds 700
    $topA = Save-UiDump 'top-boundary-a'
    Invoke-RepeatedSwipe -X1 600 -Y1 760 -X2 600 -Y2 2200 -Count 8
    Start-Sleep -Milliseconds 700
    $topB = Save-UiDump 'top-boundary-b'
    $topSignatureA = Get-VisibleSignature $topA
    $topSignatureB = Get-VisibleSignature $topB
    $result.checks.topBoundaryStable = $topSignatureA -eq $topSignatureB
    $result.checks.topSignature = $topSignatureB
    Save-Screenshot 'top-boundary'

    $failedChecks = @(@(
            'horizontalGesturesKeepSelectorFixed',
            'horizontalGesturesKeepRecordingCenter',
            'bottomBoundaryStable',
            'topBoundaryStable'
        ) | Where-Object { -not [bool]$result.checks[$_] })
    if ($failedChecks.Count -gt 0) { throw "Recording-center boundary checks failed: $($failedChecks -join ', ')" }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
