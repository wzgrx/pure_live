[CmdletBinding()]
param(
    [string] $ApkPath,
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $Activity = '.MainActivity',
    [ValidateSet('Portrait', 'Standard')]
    [string] $Mode = 'Portrait'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    $modeSlug = $Mode.ToLowerInvariant()
    Join-Path $repo ("local-artifacts\diagnostics\android-$modeSlug-presentation-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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
    $arguments = @()
    if ($Serial) { $arguments += @('-s', $Serial) }
    $arguments += $AdbArguments
    $output = & $adb @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($AdbArguments -join ' ')`n$($output -join "`n")"
    }
    $output
}

$deviceRows = & $adb devices -l
if (-not $Serial) {
    $devices = @($deviceRows | ForEach-Object { if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] } })
    $networkDevices = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($networkDevices.Count -eq 1) { $Serial = $networkDevices[0] }
    elseif ($devices.Count -eq 1) { $Serial = $devices[0] }
    else { throw "Specify -Serial; devices=$($devices.Count), network=$($networkDevices.Count)." }
}

function Ensure-Awake {
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

function Get-DisplayMetrics {
    $display = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'window', 'displays')) -join "`n"
    if ($display -match 'cur=(\d+)x(\d+)') {
        $width = [int]$Matches[1]
        $height = [int]$Matches[2]
    } else {
        $size = (Invoke-Adb -AdbArguments @('shell', 'wm', 'size')) -join "`n"
        if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected display size: $size" }
        $width = [int]$Matches[1]
        $height = [int]$Matches[2]
    }
    [pscustomobject]@{
        width = $width
        height = $height
        orientation = $(if ($width -gt $height) { 'landscape' } else { 'portrait' })
    }
}

function Save-UiDump {
    param([Parameter(Mandatory = $true)][string] $Name)
    Ensure-Awake
    $remote = "/sdcard/purelive-$PID-$Name.xml"
    $local = Join-Path $evidence "$Name.xml"
    try {
        $captured = $false
        for ($attempt = 1; $attempt -le 2 -and -not $captured; $attempt++) {
            try {
                Invoke-Adb -AdbArguments @('shell', 'timeout', '12', 'uiautomator', 'dump', '--compressed', $remote) | Out-Null
                Invoke-Adb -AdbArguments @('pull', $remote, $local) | Out-Null
                $captured = $true
            } catch {
                if ($attempt -eq 2) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
    [xml](Get-Content -LiteralPath $local -Raw -Encoding UTF8)
}

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    Ensure-Awake
    $remote = "/sdcard/purelive-$PID-$Name.png"
    try {
        Invoke-Adb -AdbArguments @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
}

function Get-UiText {
    param([Parameter(Mandatory = $true)][xml] $Document)
    (($Document.SelectNodes('//node') | ForEach-Object {
        @([string]$_.text, [string]$_.'content-desc') | Where-Object { $_ }
    }) -join "`n")
}

function Find-UiNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string] $Needle
    )
    @($Document.SelectNodes('//node') | Where-Object {
        $label = "{0}`n{1}" -f ([string]$_.text), ([string]$_.'content-desc')
        $label.Contains($Needle)
    }) | Sort-Object {
        if ([string]$_.clickable -eq 'true') { 0 } else { 1 }
    } | Select-Object -First 1
}

function Tap-Node {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "Unexpected UI bounds: $bounds" }
    $x = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
    $y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
}

function Tap-Text {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $EvidenceName,
        [int] $WaitMilliseconds = 900
    )
    $document = Save-UiDump $EvidenceName
    $node = Find-UiNode -Document $document -Needle $Text
    if (-not $node) { throw "UI text not found: $Text" }
    Tap-Node $node
    Start-Sleep -Milliseconds $WaitMilliseconds
}

function Wait-ForText {
    param(
        [Parameter(Mandatory = $true)][string] $Needle,
        [Parameter(Mandatory = $true)][string] $EvidencePrefix,
        [int] $TimeoutSeconds = 12
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiDump "$EvidencePrefix-$attempt"
        $text = Get-UiText $document
        if ($text.Contains($Needle)) {
            return [pscustomobject]@{ document = $document; text = $text; attempt = $attempt }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for UI text: $Needle"
}

function Wait-ForOrientation {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('portrait', 'landscape')][string] $Orientation,
        [int] $TimeoutSeconds = 8
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $metrics = Get-DisplayMetrics
        if ($metrics.orientation -eq $Orientation) { return $metrics }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $Orientation orientation; current=$($metrics.orientation)."
}

function Tap-Relative {
    param([double] $X, [double] $Y)
    $metrics = Get-DisplayMetrics
    $tapX = [math]::Round($metrics.width * $X)
    $tapY = [math]::Round($metrics.height * $Y)
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $tapX, $tapY) | Out-Null
}

function Swipe-Relative {
    param([double] $X1, [double] $Y1, [double] $X2, [double] $Y2, [int] $DurationMilliseconds)
    $metrics = Get-DisplayMetrics
    $values = @(
        [math]::Round($metrics.width * $X1),
        [math]::Round($metrics.height * $Y1),
        [math]::Round($metrics.width * $X2),
        [math]::Round($metrics.height * $Y2),
        $DurationMilliseconds
    )
    $swipeArguments = @('shell', 'input', 'swipe') + $values
    Invoke-Adb -AdbArguments $swipeArguments | Out-Null
}

function Dismiss-DebugCompatibilityDialog {
    $document = Save-UiDump 'debug-compatibility'
    $button = Find-UiNode -Document $document -Needle '确定'
    if ($button) {
        Tap-Node $button
        Start-Sleep -Milliseconds 700
    }
}

function Open-Test-Room {
    Tap-Text -Text '热门' -EvidenceName 'home-before-popular' -WaitMilliseconds 1200
    $platform = if ($Mode -eq 'Portrait') { '抖音' } else { '哔哩哔哩' }
    Tap-Text -Text $platform -EvidenceName "popular-before-$($platform.ToLowerInvariant())" -WaitMilliseconds 5000

    $candidates = @(
        @{ x = 0.27; y = 0.29 },
        @{ x = 0.73; y = 0.29 },
        @{ x = 0.27; y = 0.52 },
        @{ x = 0.73; y = 0.52 }
    )
    $attempt = 0
    foreach ($page in 0..2) {
        foreach ($candidate in $candidates) {
            $attempt++
            Tap-Relative -X $candidate.x -Y $candidate.y
            Start-Sleep -Seconds 10
            $document = Save-UiDump "candidate-$attempt"
            $text = Get-UiText $document
            $isRoom = $text.Contains('弹幕列表') -and $text.Contains('弹幕设置')
            $matchesMode = if ($Mode -eq 'Portrait') {
                $isRoom -and $text.Contains('下滑进入竖屏全屏') -and $text.Contains('横屏全屏')
            } else {
                $isRoom -and -not $text.Contains('下滑进入竖屏全屏')
            }
            if ($matchesMode) {
                Save-Screenshot "candidate-$attempt-$($Mode.ToLowerInvariant())-room"
                return [pscustomobject]@{ attempt = $attempt; page = $page; document = $document; text = $text }
            }
            Save-Screenshot "candidate-$attempt-rejected"
            if ($text.Contains('弹幕列表') -or $text.Contains('直播已结束') -or $text.Contains('网络请求失败')) {
                Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
                Start-Sleep -Seconds 2
            }
        }
        if ($page -lt 2) {
            Swipe-Relative -X1 0.5 -Y1 0.82 -X2 0.5 -Y2 0.34 -DurationMilliseconds 420
            Start-Sleep -Seconds 3
        }
    }
    throw "No $Mode room was found for $platform in the first three visible result pages."
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    mode = $Mode
    apk = if ($ApkPath) { [IO.Path]::GetFullPath($ApkPath) } else { $null }
    checks = [ordered]@{}
}
$failure = $null
try {
    if ($ApkPath) {
        $apk = (Resolve-Path $ApkPath).Path
        $result.checks.install = ((Invoke-Adb -AdbArguments @('install', '-r', '-t', $apk)) -join "`n").Trim()
    }
    Ensure-Awake
    Invoke-Adb -AdbArguments @('shell', 'logcat', '-c') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity") | Out-Null
    Start-Sleep -Seconds 7
    Dismiss-DebugCompatibilityDialog

    $room = Open-Test-Room
    $result.checks.roomCandidate = $room.attempt
    $normalMetrics = Wait-ForOrientation -Orientation portrait
    $result.checks.normalPortrait = $normalMetrics
    if ($Mode -eq 'Portrait') {
        $result.checks.normalHasPortraitGesture = $room.text.Contains('下滑进入竖屏全屏')
        $result.checks.normalHasLandscapeAction = $room.text.Contains('横屏全屏')
        Save-Screenshot 'portrait-normal'

        Swipe-Relative -X1 0.5 -Y1 0.63 -X2 0.5 -Y2 0.96 -DurationMilliseconds 650
        $portraitFull = Wait-ForText -Needle '已进入竖屏全屏' -EvidencePrefix 'portrait-fullscreen'
        $result.checks.portraitFullscreenHintVisible = $portraitFull.text.Contains('上滑恢复弹幕栏')
        $result.checks.portraitFullscreenMetrics = Wait-ForOrientation -Orientation portrait
        Save-Screenshot 'portrait-fullscreen'

        # Start above Android's bottom-edge navigation reservation. A gesture that
        # begins at the physical edge opens HyperOS recents before Flutter can see
        # it, which is different from using the in-app restore affordance.
        Swipe-Relative -X1 0.5 -Y1 0.935 -X2 0.5 -Y2 0.73 -DurationMilliseconds 420
        $restored = Wait-ForText -Needle '弹幕列表' -EvidencePrefix 'portrait-restored'
        $result.checks.portraitPanelRestored = $restored.text.Contains('下滑进入竖屏全屏')
        Save-Screenshot 'portrait-restored'

        Tap-Text -Text '横屏全屏' -EvidenceName 'before-landscape-fullscreen' -WaitMilliseconds 700
    } else {
        $result.checks.standardPortraitPathAbsent = -not $room.text.Contains('下滑进入竖屏全屏')
        Save-Screenshot 'standard-normal'
        Tap-Relative -X 0.5 -Y 0.25
        Start-Sleep -Milliseconds 500
        Tap-Text -Text '进入全屏' -EvidenceName 'standard-before-fullscreen' -WaitMilliseconds 700
    }
    $landscapeMetrics = Wait-ForOrientation -Orientation landscape
    $result.checks.landscapeFullscreen = $landscapeMetrics
    Start-Sleep -Seconds 2
    Save-UiDump 'landscape-fullscreen' | Out-Null
    Save-Screenshot 'landscape-fullscreen'

    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
    $result.checks.backReturnedPortrait = Wait-ForOrientation -Orientation portrait
    $afterBack = Wait-ForText -Needle '弹幕列表' -EvidencePrefix "$($Mode.ToLowerInvariant())-after-back"
    $result.checks.backReturnedToRoom = if ($Mode -eq 'Portrait') {
        $afterBack.text.Contains('下滑进入竖屏全屏')
    } else {
        -not $afterBack.text.Contains('下滑进入竖屏全屏')
    }
    Save-Screenshot "$($Mode.ToLowerInvariant())-after-back"

    & (Join-Path $repo 'tool\android_ui.ps1') -Sequence enter_pip -Serial $Serial -CaptureOnFailure |
        Out-File -LiteralPath (Join-Path $evidence 'enter-pip.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Entering system picture-in-picture failed.' }
    Start-Sleep -Seconds 4
    $pipState = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    $pipState | Out-File -LiteralPath (Join-Path $evidence 'pip-activity.txt') -Encoding utf8
    $result.checks.pipReported = $pipState -match 'pictureInPicture|mLastReportedPictureInPictureMode=true|supportsPictureInPicture'
    Save-Screenshot "$($Mode.ToLowerInvariant())-system-pip"

    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity") | Out-Null
    Start-Sleep -Seconds 5
    $afterPip = Wait-ForText -Needle '弹幕列表' -EvidencePrefix "$($Mode.ToLowerInvariant())-after-pip"
    $result.checks.afterPipRoomAlive = if ($Mode -eq 'Portrait') {
        $afterPip.text.Contains('下滑进入竖屏全屏')
    } else {
        -not $afterPip.text.Contains('下滑进入竖屏全屏')
    }
    $result.checks.afterPipPortrait = (Wait-ForOrientation -Orientation portrait).orientation -eq 'portrait'
    Save-Screenshot "$($Mode.ToLowerInvariant())-after-pip"

    $logcat = (Invoke-Adb -AdbArguments @('shell', 'logcat', '-d', '-v', 'threadtime')) -join "`n"
    $logcat | Out-File -LiteralPath (Join-Path $evidence 'logcat.txt') -Encoding utf8
    $fatalLines = @($logcat -split "`r?`n" | Where-Object {
        $_ -match 'FATAL EXCEPTION|AndroidRuntime: Process: com\.mystyle\.purelive|SIGABRT|Fatal signal'
    })
    $result.checks.noFatal = $fatalLines.Count -eq 0
    $modeAssertions = if ($Mode -eq 'Portrait') {
        @(
            $result.checks.normalHasPortraitGesture,
            $result.checks.normalHasLandscapeAction,
            $result.checks.portraitFullscreenHintVisible,
            $result.checks.portraitPanelRestored
        )
    } else {
        @($result.checks.standardPortraitPathAbsent)
    }
    $result.checks.passed = @(
        $modeAssertions
        $result.checks.backReturnedToRoom
        $result.checks.pipReported
        $result.checks.afterPipRoomAlive
        $result.checks.afterPipPortrait
        $result.checks.noFatal
    ) -notcontains $false
    if (-not $result.checks.passed) { throw "One or more $Mode presentation assertions failed." }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
    $result.checks.passed = $false
    try {
        $failureLogcat = (Invoke-Adb -AdbArguments @('shell', 'logcat', '-d', '-v', 'threadtime')) -join "`n"
        $failureLogcat | Out-File -LiteralPath (Join-Path $evidence 'logcat-failure.txt') -Encoding utf8
    } catch {}
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    try { Invoke-Adb -AdbArguments @('shell', 'settings', 'put', 'system', 'user_rotation', '0') | Out-Null } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $summaryPath = Join-Path $evidence 'summary.json'
    $result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $summaryPath -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
