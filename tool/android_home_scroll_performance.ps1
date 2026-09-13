[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $Activity = '.MainActivity',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron',
    [string] $ExpectedApkSha256 = '',
    [ValidateRange(1, 100)][int] $VerticalCycles = 20,
    [ValidateRange(1, 100)][int] $HorizontalCycles = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_activity_state.ps1')
. (Join-Path $PSScriptRoot 'android_surfaceflinger_timestats.ps1')

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo ("local-artifacts\diagnostics\android-home-scroll-performance-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
} elseif ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    [IO.Path]::GetFullPath($EvidenceDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $repo $EvidenceDirectory))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

$adbCandidates = @((Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'), 'adb.exe')
$adb = $adbCandidates | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ }
    else { [bool] (Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

function Invoke-TargetAdb {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    $output = @(& $adb -s $Serial @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $output
}

function Save-Text {
    param([Parameter(Mandatory = $true)][string] $Name, [AllowNull()][object] $Value)
    $Value | Out-File -LiteralPath (Join-Path $evidence $Name) -Encoding utf8 -Width 8192
}

function Get-ActivityDump {
    (Invoke-TargetAdb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
}

function Assert-TargetForeground {
    $activityDump = Get-ActivityDump
    if ($activityDump -notmatch ('(?m)^\s*topResumedActivity=.*\s' + [regex]::Escape($Package) + '/')) {
        Save-Text 'unexpected-foreground.txt' $activityDump
        throw 'Pure Live lost exact top-resumed ownership before an input event.'
    }
}

function Get-UiHierarchy {
    param([Parameter(Mandatory = $true)][string] $Name)
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $raw = (Invoke-TargetAdb @('exec-out', 'uiautomator', 'dump', '--compressed', '/dev/tty')) -join "`n"
        $match = [regex]::Match($raw, '(?s)<\?xml\b.*?</hierarchy>')
        if ($match.Success) {
            $path = Join-Path $evidence "$Name.xml"
            [IO.File]::WriteAllText($path, $match.Value, [Text.UTF8Encoding]::new($false))
            return [xml] $match.Value
        }
        Save-Text "$Name.uia-attempt-$attempt.txt" $raw
        if ($attempt -lt 4) { Start-Sleep -Milliseconds (350 + 250 * $attempt) }
    }
    throw "UI hierarchy '$Name' did not return XML after four attempts."
}

function Get-NodeCenter {
    param([Parameter(Mandatory = $true)] $Node)
    $match = [regex]::Match([string] $Node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Unexpected UI bounds: $($Node.bounds)" }
    [pscustomobject]@{
        x = [int] (([int] $match.Groups[1].Value + [int] $match.Groups[3].Value) / 2)
        y = [int] (([int] $match.Groups[2].Value + [int] $match.Groups[4].Value) / 2)
    }
}

function Enter-PopularPage {
    $document = Get-UiHierarchy 'home-before-popular'
    $popular = @($document.SelectNodes('//node')) | Where-Object {
        $_.clickable -eq 'true' -and ([string] $_.'content-desc') -match '^热门(?:\r?\n|$)'
    } | Select-Object -First 1
    if (-not $popular) { throw 'The visible home navigation has no unique Popular action.' }
    Assert-TargetForeground
    $point = Get-NodeCenter $popular
    Invoke-TargetAdb @('shell', 'input', 'tap', [string] $point.x, [string] $point.y) | Out-Null

    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 500
        $document = Get-UiHierarchy 'popular-settling'
        $nodes = @($document.SelectNodes('//node'))
        $platformStrip = @($nodes | Where-Object {
            $_.class -eq 'android.widget.HorizontalScrollView' -and $_.scrollable -eq 'true'
        }).Count -gt 0
        $roomGrid = @($nodes | Where-Object {
            $_.scrollable -eq 'true' -and ([string] $_.bounds) -match '^\[0,3\d\d\]\[\d+,2\d\d\d\]$'
        }).Count -gt 0
        if ($platformStrip -and $roomGrid) { return }
    } while ($timer.Elapsed.TotalSeconds -lt 15)
    throw 'Popular page did not expose both platform and room scroll surfaces.'
}

function Get-MainThreadSchedStat {
    param([Parameter(Mandatory = $true)][string] $ProcessId)
    ((Invoke-TargetAdb @('shell', 'cat', "/proc/$ProcessId/task/$ProcessId/schedstat")) -join ' ').Trim()
}

function Start-TimeStats {
    Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-disable') | Out-Null
    Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-clear') | Out-Null
    Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-enable') | Out-Null
}

function Stop-TimeStats {
    param([Parameter(Mandatory = $true)][string] $Name)
    $dump = Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-dump')
    Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-disable') | Out-Null
    Save-Text "surfaceflinger-$Name.txt" $dump
    ConvertFrom-AndroidSurfaceFlingerTimeStats -Lines $dump -Package $Package
}

function Invoke-GuardedSwipe {
    param(
        [Parameter(Mandatory = $true)][int] $X1,
        [Parameter(Mandatory = $true)][int] $Y1,
        [Parameter(Mandatory = $true)][int] $X2,
        [Parameter(Mandatory = $true)][int] $Y2,
        [Parameter(Mandatory = $true)][int] $DurationMs
    )
    Assert-TargetForeground
    Invoke-TargetAdb @(
        'shell', 'input', 'swipe', [string] $X1, [string] $Y1, [string] $X2, [string] $Y2, [string] $DurationMs
    ) | Out-Null
}

function Invoke-Scenario {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][int] $Cycles,
        [Parameter(Mandatory = $true)][scriptblock] $Forward,
        [Parameter(Mandatory = $true)][scriptblock] $Reverse,
        [Parameter(Mandatory = $true)][string] $ProcessId
    )
    Start-TimeStats
    $schedBefore = Get-MainThreadSchedStat $ProcessId
    $timer = [Diagnostics.Stopwatch]::StartNew()
    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
        & $Forward
        Start-Sleep -Milliseconds 120
        & $Reverse
        Start-Sleep -Milliseconds 120
    }
    $timer.Stop()
    $schedAfter = Get-MainThreadSchedStat $ProcessId
    $surface = Stop-TimeStats $Name
    $sched = ConvertFrom-AndroidMainThreadSchedStat -Before $schedBefore -After $schedAfter
    [pscustomobject][ordered]@{
        cycles = $Cycles
        forwardGestures = $Cycles
        reverseGestures = $Cycles
        elapsedMs = $timer.ElapsedMilliseconds
        mainThreadScheduling = $sched
        surfaceFlinger = $surface
    }
}

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remote = "/sdcard/purelive-perf-$PID-$Name.png"
    try {
        Invoke-TargetAdb @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-TargetAdb @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        try { Invoke-TargetAdb @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
}

$result = [ordered]@{
    schemaVersion = 1
    sourceCommit = (git -C $repo rev-parse HEAD).Trim()
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    vertical = $null
    horizontal = $null
    checks = [ordered]@{}
}
$failure = $null
try {
    $deviceRows = @(& $adb devices -l)
    if (@($deviceRows | Where-Object { $_ -match ('^' + [regex]::Escape($Serial) + '\s+device(?:\s|$)') }).Count -ne 1) {
        throw "Requested serial '$Serial' is not connected in device state."
    }
    $result.identity = [ordered]@{
        model = ((Invoke-TargetAdb @('shell', 'getprop', 'ro.product.model')) -join '').Trim()
        device = ((Invoke-TargetAdb @('shell', 'getprop', 'ro.product.device')) -join '').Trim()
        android = ((Invoke-TargetAdb @('shell', 'getprop', 'ro.build.version.release')) -join '').Trim()
        root = ((Invoke-TargetAdb @('shell', 'su -c id')) -join "`n").Trim()
    }
    if ($result.identity.model -cne $ExpectedModel -or $result.identity.device -cne $ExpectedDevice) {
        throw 'Device model or product code does not match the requested target.'
    }
    if ($result.identity.root -notmatch 'uid=0\(root\)') { throw 'Root shell verification failed.' }

    $packageInfo = Invoke-TargetAdb @('shell', 'dumpsys', 'package', $Package)
    Save-Text 'package.txt' $packageInfo
    $packageText = $packageInfo -join "`n"
    if ($packageText -match '(?m)^\s*versionName=([^\s]+)') { $result.versionName = $Matches[1] }
    if ($packageText -match '(?m)^\s*versionCode=(\d+)') { $result.versionCode = [long] $Matches[1] }
    $packagePath = ((Invoke-TargetAdb @('shell', 'pm', 'path', $Package)) -join "`n").Trim()
    if ($packagePath -notmatch '^package:(.+base\.apk)$') { throw "Unexpected package path: $packagePath" }
    $remoteApk = $Matches[1]
    $deviceHashText = ((Invoke-TargetAdb @('shell', "su -c 'sha256sum $remoteApk'")) -join "`n").Trim()
    if ($deviceHashText -notmatch '^([A-Fa-f0-9]{64})\s') { throw 'Device APK SHA-256 output was malformed.' }
    $result.deviceApkSha256 = $Matches[1].ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedApkSha256) -and
        $result.deviceApkSha256 -cne $ExpectedApkSha256.Trim().ToUpperInvariant()) {
        throw 'Installed APK SHA-256 differs from the requested candidate.'
    }

    Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Save-Text 'start.txt' (Invoke-TargetAdb @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity"))
    Start-Sleep -Seconds 8
    Assert-TargetForeground
    Enter-PopularPage
    Start-Sleep -Seconds 6
    Assert-TargetForeground
    Save-Screenshot 'popular-before'

    $pidText = ((Invoke-TargetAdb @('shell', 'pidof', $Package)) -join ' ').Trim()
    $appPid = ($pidText -split '\s+')[0]
    if ($appPid -notmatch '^\d+$') { throw 'Pure Live process id was not available.' }
    $result.pid = [long] $appPid
    Save-Text 'display.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'display'))
    Save-Text 'thermal-before.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'thermalservice'))
    Save-Text 'meminfo-before.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'meminfo', $Package))

    $result.vertical = Invoke-Scenario -Name 'vertical' -Cycles $VerticalCycles -ProcessId $appPid `
        -Forward { Invoke-GuardedSwipe -X1 600 -Y1 1959 -X2 600 -Y2 741 -DurationMs 300 } `
        -Reverse { Invoke-GuardedSwipe -X1 600 -Y1 741 -X2 600 -Y2 1959 -DurationMs 300 }
    Get-UiHierarchy 'popular-after-vertical' | Out-Null

    $result.horizontal = Invoke-Scenario -Name 'horizontal' -Cycles $HorizontalCycles -ProcessId $appPid `
        -Forward { Invoke-GuardedSwipe -X1 1030 -Y1 1200 -X2 170 -Y2 1200 -DurationMs 260 } `
        -Reverse { Invoke-GuardedSwipe -X1 170 -Y1 1200 -X2 1030 -Y2 1200 -DurationMs 260 }
    $finalHierarchy = Get-UiHierarchy 'popular-after-horizontal'
    Save-Screenshot 'popular-after'

    $finalNodes = @($finalHierarchy.SelectNodes('//node'))
    $result.checks.popularUiAlive = @($finalNodes | Where-Object {
        $_.class -eq 'android.widget.HorizontalScrollView' -and $_.scrollable -eq 'true'
    }).Count -gt 0
    $result.checks.verticalMeasurementValid =
        $result.vertical.surfaceFlinger.totalFrames -ge 100 -and
        $result.vertical.surfaceFlinger.histogramIntervals -ge 100
    $result.checks.horizontalMeasurementValid =
        $result.horizontal.surfaceFlinger.totalFrames -ge 100 -and
        $result.horizontal.surfaceFlinger.histogramIntervals -ge 100
    $result.checks.verticalGesturesComplete =
        $result.vertical.forwardGestures -eq $VerticalCycles -and $result.vertical.reverseGestures -eq $VerticalCycles
    $result.checks.horizontalGesturesComplete =
        $result.horizontal.forwardGestures -eq $HorizontalCycles -and $result.horizontal.reverseGestures -eq $HorizontalCycles

    Save-Text 'meminfo-after.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'meminfo', $Package))
    Save-Text 'thermal-after.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'thermalservice'))
    $logcat = Invoke-TargetAdb @('logcat', '-d', '-v', 'threadtime', "--pid=$appPid", '-t', '3000')
    Save-Text 'logcat-tail.txt' $logcat
    $logText = $logcat -join "`n"
    $result.checks.noFatalOrAnr = $logText -notmatch 'FATAL EXCEPTION|ANR in com\.mystyle\.purelive'
    $result.passed = -not (@($result.checks.GetEnumerator() | Where-Object { -not [bool] $_.Value }).Count)
    if (-not $result.passed) {
        $failed = @($result.checks.GetEnumerator() | Where-Object { -not [bool] $_.Value } | ForEach-Object Key)
        throw "Android home performance assertions failed: $($failed -join ', ')."
    }
} catch {
    $failure = $_
    $result.passed = $false
    $result.error = $_.Exception.Message
} finally {
    try { Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-disable') | Out-Null } catch {}
    try { Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    try { Invoke-TargetAdb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try {
        $processOutput = @(& $adb -s $Serial shell pidof $Package 2>&1)
        $processExitCode = $LASTEXITCODE
        $result.cleanupAppStopped = Test-AndroidPidAbsent -ExitCode $processExitCode -Output ($processOutput -join "`n")
        $activityDump = Get-ActivityDump
        $result.cleanupHomeForeground = $activityDump -match '(?m)^\s*topResumedActivity=.*\scom\.miui\.home/'
    } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 16 | Set-Content (Join-Path $evidence 'summary.json') -Encoding utf8
}
if ($failure) { throw $failure }
Write-Output (Join-Path $evidence 'summary.json')
