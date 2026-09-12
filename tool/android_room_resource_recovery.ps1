[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $Activity = '.MainActivity',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron',
    [string] $ExpectedApkSha256 = '',
    [ValidateRange(1, 100)][int] $Cycles = 50,
    [ValidateRange(1, 50)][int] $SampleEvery = 5,
    [ValidateRange(46, 180)][int] $IdleReleaseSeconds = 52,
    [ValidateRange(5, 30)][int] $RoomTimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_activity_state.ps1')
. (Join-Path $PSScriptRoot 'android_process_resource_metrics.ps1')

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo ("local-artifacts\diagnostics\android-room-resource-recovery-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
} elseif ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    [IO.Path]::GetFullPath($EvidenceDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $repo $EvidenceDirectory))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$uiMap = Get-Content (Join-Path $PSScriptRoot 'device_ui_map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$uiProfile = $uiMap.profiles.k90pro_portrait_1200x2608
$roomPoint = $uiProfile.points.'home.first_left_room'
$controlsPoint = $uiProfile.points.'live.show_controls'
$audioPoint = $uiProfile.points.'live.audio_toggle'
$audioTransitionSettleMilliseconds = 5250

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

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remote = "/sdcard/purelive-resource-$PID-$Name.png"
    try {
        Invoke-TargetAdb @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-TargetAdb @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        try { Invoke-TargetAdb @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
}

function Get-ActivityDump {
    (Invoke-TargetAdb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
}

function Assert-TargetForeground {
    $dump = Get-ActivityDump
    if ($dump -notmatch ('(?m)^\s*topResumedActivity=.*\s' + [regex]::Escape($Package) + '/')) {
        Save-Text 'unexpected-foreground.txt' $dump
        throw 'Pure Live lost exact top-resumed ownership before an input event.'
    }
}

function Get-UiHierarchy {
    param([string] $Name = '')
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Assert-TargetForeground
        $raw = (Invoke-TargetAdb @('exec-out', 'uiautomator', 'dump', '--compressed', '/dev/tty')) -join "`n"
        $match = [regex]::Match($raw, '(?s)<\?xml\b.*?</hierarchy>')
        if ($match.Success) {
            if (-not [string]::IsNullOrWhiteSpace($Name)) {
                [IO.File]::WriteAllText((Join-Path $evidence "$Name.xml"), $match.Value, [Text.UTF8Encoding]::new($false))
            }
            return [xml] $match.Value
        }
        if (-not [string]::IsNullOrWhiteSpace($Name)) { Save-Text "$Name.uia-attempt-$attempt.txt" $raw }
        if ($attempt -lt 4) { Start-Sleep -Milliseconds (250 + 200 * $attempt) }
    }
    throw "UI hierarchy '$Name' did not return XML after four attempts."
}

function Get-NodeCenter {
    param([Parameter(Mandatory = $true)] $Node)
    $match = [regex]::Match([string] $Node.bounds, '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
    if (-not $match.Success) { throw "Unexpected UI bounds: $($Node.bounds)" }
    [pscustomobject]@{
        X = [int] (([int] $match.Groups[1].Value + [int] $match.Groups[3].Value) / 2)
        Y = [int] (([int] $match.Groups[2].Value + [int] $match.Groups[4].Value) / 2)
    }
}

function Find-SemanticNode {
    param([Parameter(Mandatory = $true)] [xml] $Document, [Parameter(Mandatory = $true)][string[]] $Labels)
    foreach ($label in $Labels) {
        $node = @($Document.SelectNodes('//node')) | Where-Object {
            $_.clickable -eq 'true' -and (
                [string] $_.'content-desc' -eq $label -or
                [string] $_.text -eq $label -or
                [string] $_.'content-desc' -match ('^' + [regex]::Escape($label) + '(?:\r?\n|$)') -or
                [string] $_.text -match ('^' + [regex]::Escape($label) + '(?:\r?\n|$)')
            )
        } | Select-Object -First 1
        if ($node) { return $node }
    }
    $null
}

function Invoke-SemanticTap {
    param([Parameter(Mandatory = $true)][string[]] $Labels, [string] $EvidenceName = '')
    $document = Get-UiHierarchy $EvidenceName
    $node = Find-SemanticNode -Document $document -Labels $Labels
    if (-not $node) { throw "Visible semantic action was not found: $($Labels -join ' / ')" }
    $point = Get-NodeCenter $node
    Assert-TargetForeground
    Invoke-TargetAdb @('shell', 'input', 'tap', [string] $point.X, [string] $point.Y) | Out-Null
}

function Test-RoomUi {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $raw = $Document.OuterXml
    $raw.Contains('弹幕列表') -and $raw.Contains('弹幕设置')
}

function Test-HomeUi {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $raw = $Document.OuterXml
    -not (Test-RoomUi $Document) -and $raw.Contains('热门') -and $raw.Contains('分区') -and $raw.Contains('录制中心')
}

function Test-AudioOnlyPresentation {
    param([Parameter(Mandatory = $true)][xml] $Document)
    @($Document.SelectNodes('//node') | Where-Object {
        [string] $_.'content-desc' -eq '纯音频模式' -or [string] $_.text -eq '纯音频模式'
    }).Count -gt 0
}

function Wait-UiState {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('room', 'home')][string] $State,
        [int] $TimeoutSeconds = 15,
        [string] $EvidenceName = ''
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 450
        $document = Get-UiHierarchy
        $matched = if ($State -eq 'room') { Test-RoomUi $document } else { Test-HomeUi $document }
        if ($matched) {
            if (-not [string]::IsNullOrWhiteSpace($EvidenceName)) {
                [IO.File]::WriteAllText(
                    (Join-Path $evidence "$EvidenceName.xml"),
                    $document.OuterXml,
                    [Text.UTF8Encoding]::new($false)
                )
            }
            return [pscustomobject]@{ Document = $document; ElapsedMs = $timer.ElapsedMilliseconds }
        }
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "UI state '$State' did not settle within $TimeoutSeconds seconds."
}

function Show-PlayerControls {
    Assert-TargetForeground
    Invoke-TargetAdb @(
        'shell', 'input', 'tap', [string] $controlsPoint.x, [string] $controlsPoint.y
    ) | Out-Null
    Start-Sleep -Milliseconds 250
}

function Invoke-ModeTransition {
    param([Parameter(Mandatory = $true)][bool] $AudioOnly)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    # UIAutomator needs long enough that the transient control bar can hide
    # before its XML arrives. Resolve the target from the already-validated K90
    # profile, then verify the persistent presentation state instead of using a
    # late semantic tap on a button that has left the tree.
    Show-PlayerControls
    Assert-TargetForeground
    Invoke-TargetAdb @(
        'shell', 'input', 'tap', [string] $audioPoint.x, [string] $audioPoint.y
    ) | Out-Null
    do {
        Start-Sleep -Milliseconds 350
        $document = Get-UiHierarchy
        # The video-mode action is labelled "切换到纯音频模式". A substring
        # search therefore reports audio mode even after video has returned;
        # only the persistent centre badge owns the exact label below.
        $hasAudioPresentation = Test-AudioOnlyPresentation $document
        if ($hasAudioPresentation -eq $AudioOnly -and (Test-RoomUi $document)) {
            return $timer.ElapsedMilliseconds
        }
    } while ($timer.Elapsed.TotalSeconds -lt 10)
    throw "Mode transition did not reach audioOnly=$AudioOnly within 10 seconds."
}

function Invoke-ModeRoundTrip {
    $audioMs = Invoke-ModeTransition -AudioOnly $true
    # The audio badge is intentionally published before the native track
    # command completes. Wait through PlayerManager's five-second deadline so
    # the reverse tap is never delivered to the temporarily disabled button.
    Start-Sleep -Milliseconds $audioTransitionSettleMilliseconds
    $settledAudio = Get-UiHierarchy
    if (-not (Test-AudioOnlyPresentation $settledAudio)) {
        throw 'Audio-only presentation rolled back during the native settle window.'
    }
    $videoMs = Invoke-ModeTransition -AudioOnly $false
    [pscustomobject]@{
        audioMs = $audioMs
        audioSettleMs = $audioTransitionSettleMilliseconds
        videoMs = $videoMs
    }
}

function Enter-PopularBilibili {
    Invoke-SemanticTap @('热门')
    Start-Sleep -Milliseconds 700
    Invoke-SemanticTap @('哔哩哔哩')
    Start-Sleep -Seconds 4
    $document = Get-UiHierarchy 'popular-bilibili'
    if (-not (Test-HomeUi $document) -or -not $document.OuterXml.Contains('哔哩哔哩')) {
        throw 'Popular Bilibili room grid did not settle.'
    }
}

function Enter-FirstRoom {
    Assert-TargetForeground
    Invoke-TargetAdb @(
        'shell', 'input', 'tap', [string] $roomPoint.x, [string] $roomPoint.y
    ) | Out-Null
    Wait-UiState -State room -TimeoutSeconds $RoomTimeoutSeconds
}

function Exit-Room {
    Assert-TargetForeground
    Invoke-TargetAdb @('shell', 'input', 'keyevent', '4') | Out-Null
    Wait-UiState -State home -TimeoutSeconds 12
}

function Get-AppPid {
    $text = ((Invoke-TargetAdb @('shell', 'pidof', $Package)) -join ' ').Trim()
    $candidate = ($text -split '\s+')[0]
    if ($candidate -notmatch '^\d+$') { throw 'Pure Live process id was not available.' }
    $candidate
}

function Get-ResourceSnapshot {
    param(
        [Parameter(Mandatory = $true)][int] $Cycle,
        [Parameter(Mandatory = $true)][string] $Phase,
        [Parameter(Mandatory = $true)][string] $Name
    )
    $currentPid = Get-AppPid
    if ($null -ne $script:initialAppPid -and $currentPid -ne $script:initialAppPid) {
        throw "Pure Live process restarted during the resource cycle: $script:initialAppPid -> $currentPid"
    }
    $proc = Invoke-TargetAdb @('shell', 'cat', "/proc/$currentPid/status")
    $meminfo = Invoke-TargetAdb @('shell', 'dumpsys', 'meminfo', $Package)
    $fds = Invoke-TargetAdb @('shell', "su -c 'ls -l /proc/$currentPid/fd'")
    # Android's toybox `ps -T ... NAME` repeats the process name for every row
    # on some vendor builds. Read each task's comm file so native codec/player
    # workers remain observable instead of collapsing into the package name.
    $threadCommand = 'su -c ''for t in /proc/' + $currentPid +
        '/task/*; do n=${t##*/}; printf "%s " "$n"; cat "$t/comm"; done'''
    $threads = Invoke-TargetAdb @('shell', $threadCommand)
    $layers = Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--list')
    Save-Text "$Name-proc-status.txt" $proc
    Save-Text "$Name-meminfo.txt" $meminfo
    Save-Text "$Name-fds.txt" $fds
    Save-Text "$Name-threads.txt" $threads
    Save-Text "$Name-layers.txt" $layers
    $snapshot = ConvertFrom-AndroidProcessResourceText `
        -ProcStatusLines $proc -MeminfoLines $meminfo -FdLines $fds -ThreadLines $threads `
        -SurfaceLayerLines $layers -Package $Package -Cycle $Cycle -Phase $Phase
    $snapshot | Add-Member -NotePropertyName pid -NotePropertyValue ([long] $currentPid)
    $snapshot
}

$result = [ordered]@{
    schemaVersion = 1
    sourceCommit = (git -C $repo rev-parse HEAD).Trim()
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    requestedCycles = $Cycles
    sampleEvery = $SampleEvery
    idleReleaseSeconds = $IdleReleaseSeconds
    cycles = @()
    samples = @()
    series = [ordered]@{}
    checks = [ordered]@{}
}
$script:initialAppPid = $null
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

    $displaySize = ((Invoke-TargetAdb @('shell', 'wm', 'size')) -join "`n").Trim()
    $expectedDisplaySize = "$($uiProfile.width)x$($uiProfile.height)"
    if ($displaySize -notmatch [regex]::Escape($expectedDisplaySize)) {
        throw "The K90 portrait UI profile does not match: $displaySize"
    }
    $packageInfo = Invoke-TargetAdb @('shell', 'dumpsys', 'package', $Package)
    Save-Text 'package.txt' $packageInfo
    $packageText = $packageInfo -join "`n"
    if ($packageText -match '(?m)^\s*versionName=([^\s]+)') { $result.versionName = $Matches[1] }
    if ($packageText -match '(?m)^\s*versionCode=(\d+)') { $result.versionCode = [long] $Matches[1] }
    $packagePath = ((Invoke-TargetAdb @('shell', 'pm', 'path', $Package)) -join "`n").Trim()
    if ($packagePath -notmatch '^package:(.+base\.apk)$') { throw "Unexpected package path: $packagePath" }
    $remoteApk = $Matches[1]
    $deviceHash = ((Invoke-TargetAdb @('shell', "su -c 'sha256sum $remoteApk'")) -join "`n").Trim()
    if ($deviceHash -notmatch '^([A-Fa-f0-9]{64})\s') { throw 'Device APK SHA-256 output was malformed.' }
    $result.deviceApkSha256 = $Matches[1].ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedApkSha256) -and
        $result.deviceApkSha256 -cne $ExpectedApkSha256.Trim().ToUpperInvariant()) {
        throw 'Installed APK SHA-256 differs from the requested candidate.'
    }

    Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Save-Text 'start.txt' (Invoke-TargetAdb @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity"))
    Start-Sleep -Seconds 7
    Assert-TargetForeground
    Enter-PopularBilibili
    Save-Screenshot 'popular-before-warmup'
    $script:initialAppPid = Get-AppPid
    $result.pid = [long] $script:initialAppPid
    $result.coldHome = Get-ResourceSnapshot -Cycle -1 -Phase 'cold-home' -Name 'cold-home'

    $warmRoom = Enter-FirstRoom
    $warmModes = Invoke-ModeRoundTrip
    $warmHome = Exit-Room
    $result.warmup = [ordered]@{
        roomEnterMs = $warmRoom.ElapsedMs
        audioMs = $warmModes.audioMs
        audioSettleMs = $warmModes.audioSettleMs
        videoMs = $warmModes.videoMs
        homeReturnMs = $warmHome.ElapsedMs
    }
    Start-Sleep -Seconds $IdleReleaseSeconds
    $warmBaselineUi = Wait-UiState -State home -TimeoutSeconds 5 -EvidenceName 'warm-home-baseline'
    $result.warmHomeBaseline = Get-ResourceSnapshot -Cycle 0 -Phase 'warm-home-baseline' -Name 'warm-home-baseline'
    Save-Screenshot 'warm-home-baseline'

    $cycleResults = [Collections.Generic.List[object]]::new()
    $samples = [Collections.Generic.List[object]]::new()
    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
        $cycleTimer = [Diagnostics.Stopwatch]::StartNew()
        $roomState = Enter-FirstRoom
        $modeState = Invoke-ModeRoundTrip
        $homeState = Exit-Room
        $cycleTimer.Stop()
        $cycleResults.Add([pscustomobject][ordered]@{
            cycle = $cycle
            roomEnterMs = $roomState.ElapsedMs
            audioMs = $modeState.audioMs
            audioSettleMs = $modeState.audioSettleMs
            videoMs = $modeState.videoMs
            homeReturnMs = $homeState.ElapsedMs
            totalMs = $cycleTimer.ElapsedMilliseconds
        })
        if (($cycle % $SampleEvery) -eq 0 -or $cycle -eq $Cycles) {
            $sample = Get-ResourceSnapshot -Cycle $cycle -Phase 'cycle-home' -Name ("cycle-{0:D2}-home" -f $cycle)
            $samples.Add($sample)
            Write-Host (
                'cycle {0}/{1}: PSS={2}KB RSS={3}KB threads={4} fds={5} sockets={6} layers={7}' -f
                $cycle, $Cycles, $sample.totalPssKb, $sample.totalRssKb, $sample.threadCount,
                $sample.fdCount, $sample.socketFds, $sample.packageBlastLayers
            )
        } else {
            Write-Host "cycle $cycle/$Cycles complete"
        }
    }
    $result.cycles = @($cycleResults)
    $result.samples = @($samples)

    Save-Text 'thermal-before-idle-release.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'thermalservice'))
    Start-Sleep -Seconds $IdleReleaseSeconds
    $finalUi = Wait-UiState -State home -TimeoutSeconds 5 -EvidenceName 'final-home-after-idle-release'
    $result.finalHome = Get-ResourceSnapshot -Cycle $Cycles -Phase 'final-home-after-idle-release' -Name 'final-home-after-idle-release'
    Save-Screenshot 'final-home-after-idle-release'
    Save-Text 'thermal-after-idle-release.txt' (Invoke-TargetAdb @('shell', 'dumpsys', 'thermalservice'))

    foreach ($metric in @(
        'totalPssKb', 'totalRssKb', 'nativeHeapKb', 'graphicsKb', 'threadCount', 'nativePlayerThreads',
        'codecThreads', 'fdCount', 'socketFds', 'dmaBufferFds', 'gpuDeviceFds', 'packageBlastLayers'
    )) {
        $result.series[$metric] = Measure-AndroidResourceSeries -Samples @($samples) -Property $metric
    }

    $logcat = Invoke-TargetAdb @('logcat', '-d', '-v', 'threadtime', "--pid=$script:initialAppPid", '-t', '5000')
    Save-Text 'logcat-tail.txt' $logcat
    $logText = $logcat -join "`n"
    $baseline = $result.warmHomeBaseline
    $final = $result.finalHome
    $result.checks.cyclesComplete = $cycleResults.Count -eq $Cycles
    $result.checks.modeRoundTripsComplete = @($cycleResults | Where-Object {
        $_.audioMs -le 0 -or $_.videoMs -le 0
    }).Count -eq 0
    $result.checks.processStable = (Get-AppPid) -eq $script:initialAppPid
    $result.checks.finalHomeUiAlive = Test-HomeUi $finalUi.Document
    $result.checks.finalFdBounded = $final.fdCount -le ($baseline.fdCount + 24)
    $result.checks.finalThreadsBounded = $final.threadCount -le ($baseline.threadCount + 16)
    $result.checks.finalSocketsBounded = $final.socketFds -le ($baseline.socketFds + 4)
    $result.checks.finalActivitiesBounded = $final.activities -le ($baseline.activities + 1)
    $result.checks.finalViewRootsBounded = $final.viewRoots -le ($baseline.viewRoots + 1)
    $result.checks.finalLayersBounded = $final.packageBlastLayers -le ($baseline.packageBlastLayers + 2)
    $result.checks.finalPssBounded = $final.totalPssKb -le ($baseline.totalPssKb + 131072)
    $result.checks.finalNativeHeapBounded = $final.nativeHeapKb -le ($baseline.nativeHeapKb + 65536)
    $result.checks.noFatalOrAnr = $logText -notmatch 'FATAL EXCEPTION|ANR in com\.mystyle\.purelive'
    $result.passed = -not (@($result.checks.GetEnumerator() | Where-Object { -not [bool] $_.Value }).Count)
    if (-not $result.passed) {
        $failed = @($result.checks.GetEnumerator() | Where-Object { -not [bool] $_.Value } | ForEach-Object Key)
        throw "Android room resource assertions failed: $($failed -join ', ')."
    }
} catch {
    $failure = $_
    $result.passed = $false
    $result.error = $_.Exception.Message
    try { Save-Screenshot 'failure' } catch {}
    try { Get-UiHierarchy 'failure' | Out-Null } catch {}
} finally {
    try { Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    try { Invoke-TargetAdb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    Start-Sleep -Seconds 2
    try {
        $processOutput = @(& $adb -s $Serial shell pidof $Package 2>&1)
        $processExitCode = $LASTEXITCODE
        $result.cleanupAppStopped = Test-AndroidPidAbsent -ExitCode $processExitCode -Output ($processOutput -join "`n")
        $activityDump = Get-ActivityDump
        $result.cleanupHomeForeground = $activityDump -match '(?m)^\s*topResumedActivity=.*\scom\.miui\.home/'
    } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $evidence 'summary.json') -Encoding utf8
}

if ($failure) { throw $failure }
Write-Output (Join-Path $evidence 'summary.json')
