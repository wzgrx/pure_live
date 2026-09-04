[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApkPath,
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apk = (Resolve-Path $ApkPath).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-local-interaction-enabled-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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

$adbServerRecoveries = 0
function Start-AdbServer {
    $serverResult = & $adb start-server 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb start-server failed ($LASTEXITCODE):`n$($serverResult -join "`n")"
    }
}

Start-AdbServer
$deviceRows = & $adb devices -l
if (-not $Serial) {
    $devices = @($deviceRows | ForEach-Object { if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] } })
    $network = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($devices.Count -eq 1) { $Serial = $devices[0] }
    elseif ($network.Count -eq 1) { $Serial = $network[0] }
    else { throw "Specify -Serial; devices=$($devices.Count), network=$($network.Count)." }
}

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $result = & $adb -s $Serial @AdbArguments 2>&1
    $exitCode = $LASTEXITCODE
    $output = $result -join "`n"
    if ($exitCode -ne 0 -and $output -match '(?i)cannot connect to daemon|daemon still not running') {
        Start-AdbServer
        $script:adbServerRecoveries++
        Start-Sleep -Milliseconds 350
        $result = & $adb -s $Serial @AdbArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($AdbArguments -join ' ')`n$($result -join "`n")"
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

function Get-CenterFromNode {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Unexpected UI node bounds: $bounds"
    }
    [pscustomobject]@{
        X = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
        Y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    }
}

function Get-BoundsFromNode {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Unexpected UI node bounds: $bounds"
    }
    [pscustomobject]@{
        Left = [int]$Matches[1]
        Top = [int]$Matches[2]
        Right = [int]$Matches[3]
        Bottom = [int]$Matches[4]
    }
}

function Find-UiNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [switch] $Editable,
        [switch] $Clickable
    )
    foreach ($candidate in $Candidates) {
        $node = $Document.SelectNodes('//node') | Where-Object {
            $text = [string]$_.text
            $desc = [string]$_.'content-desc'
            $matchesText = $text.Contains($candidate) -or $desc.Contains($candidate)
            $matchesEditable = -not $Editable -or [string]$_.class -match 'EditText'
            $matchesClickable = -not $Clickable -or [string]$_.clickable -eq 'true'
            $matchesText -and $matchesEditable -and $matchesClickable
        } | Select-Object -First 1
        if ($node) { return $node }
    }
    $null
}

function Tap-UiNode {
    param([Parameter(Mandatory = $true)] $Node)
    $center = Get-CenterFromNode $Node
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $center.X, $center.Y) | Out-Null
}

function Get-KeyboardVisible {
    param([Parameter(Mandatory = $true)][string] $EvidenceName)
    $state = Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'input_method')
    $text = $state -join "`n"
    $text | Out-File -LiteralPath (Join-Path $evidence "$EvidenceName-input-method.txt") -Encoding utf8
    $text -match '(?m)\bmInputShown=true\b|\bmIsInputViewShown=true\b|\bmImeWindowVis=0x1\b'
}

function Dismiss-DebugCompatibilityDialog {
    param([Parameter(Mandatory = $true)][string] $EvidenceName)
    $document = Save-UiDump $EvidenceName
    $button = Find-UiNode -Document $document -Candidates @('确定') -Clickable
    if (-not $button) { return }
    Tap-UiNode $button
    Start-Sleep -Milliseconds 800
}

function Get-LocalInteractionSwitchState {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $switch = $Document.SelectNodes('//node') | Where-Object {
        (([string]$_.'content-desc').Contains('启用本地互动体验') -or ([string]$_.text).Contains('启用本地互动体验')) -and
        [string]$_.checkable -eq 'true'
    } | Select-Object -First 1
    if (-not $switch) { throw 'The local interaction switch was not exposed by UIAutomator.' }
    [string]$switch.checked -eq 'true'
}

function Open-LocalInteractionSettings {
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
    Dismiss-DebugCompatibilityDialog 'debug-compatibility-settings'
    & (Join-Path $repo 'tool\android_ui.ps1') -Sequence open_local_interaction_settings -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Opening local interaction settings failed.' }
    Start-Sleep -Seconds 1
}

function Set-LocalInteractionState {
    param([Parameter(Mandatory = $true)][bool] $Enabled, [Parameter(Mandatory = $true)][string] $EvidenceName)
    $document = Save-UiDump "$EvidenceName-before"
    $current = Get-LocalInteractionSwitchState $document
    if ($current -ne $Enabled) {
        & (Join-Path $repo 'tool\android_ui.ps1') -TapSemantic '启用本地互动体验' -Serial $Serial -CaptureOnFailure
        if ($LASTEXITCODE -ne 0) { throw 'Toggling local interaction failed.' }
        Start-Sleep -Milliseconds 700
    }
    $after = Save-UiDump "$EvidenceName-after"
    if ((Get-LocalInteractionSwitchState $after) -ne $Enabled) {
        throw "Local interaction did not settle to enabled=$Enabled."
    }
}

function Open-QuietRoom {
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
    Dismiss-DebugCompatibilityDialog 'debug-compatibility-room'
    & (Join-Path $repo 'tool\android_ui.ps1') -TapSemantic '热门' -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Opening the popular page failed.' }
    # CC intentionally has no remote danmaku transport in this project. It is
    # therefore the deterministic device fixture for proving that one locally
    # submitted row remains observable instead of being displaced by a busy
    # platform socket while UIAutomator is taking a snapshot.
    Invoke-Adb -AdbArguments @('shell', 'input', 'swipe', '980', '228', '500', '228', '420') | Out-Null
    Start-Sleep -Milliseconds 350
    [void](Save-UiDump 'popular-platforms-after-scroll')
    & (Join-Path $repo 'tool\android_ui.ps1') -TapSemantic '网易CC' -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Selecting the CC platform failed.' }
    Start-Sleep -Seconds 8
    & (Join-Path $repo 'tool\android_ui.ps1') -Tap home.first_left_room -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Entering the first CC room failed.' }
    Start-Sleep -Seconds 12
    $room = Save-UiDump 'room-enabled'
    if (-not ($room.OuterXml.Contains('弹幕列表') -and $room.OuterXml.Contains('弹幕设置'))) {
        throw 'The selected card did not reach a live-room UI.'
    }
    $room
}

function Send-LocalMessage {
    param(
        [Parameter(Mandatory = $true)][string] $Marker,
        [Parameter(Mandatory = $true)][string] $EvidencePrefix,
        [switch] $AlreadyFocused
    )
    $before = Save-UiDump "$EvidencePrefix-before"
    # Flutter merges the empty TextField into the two adjacent IconButton
    # semantics on Android, so the hint itself is not exposed. Derive the
    # editable center from the stable style/send actions instead of using a
    # device-specific cached coordinate.
    $styleAction = Find-UiNode -Document $before -Candidates @('本地弹幕样式', 'Local danmaku style') -Clickable
    $sendAction = Find-UiNode -Document $before -Candidates @('发送本地弹幕', 'Send local danmaku') -Clickable
    if (-not $styleAction -or -not $sendAction) {
        throw "The local composer actions were not visible for $EvidencePrefix."
    }
    if (-not $AlreadyFocused) {
        $styleBounds = Get-BoundsFromNode $styleAction
        $sendBounds = Get-BoundsFromNode $sendAction
        $fieldX = [math]::Floor(($styleBounds.Right + $sendBounds.Left) / 2)
        $fieldY = [math]::Floor(($sendBounds.Top + $sendBounds.Bottom) / 2)
        Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $fieldX, $fieldY) | Out-Null
        Start-Sleep -Milliseconds 350
    }
    Invoke-Adb -AdbArguments @('shell', 'input', 'text', $Marker) | Out-Null
    Start-Sleep -Milliseconds 250
    $input = Save-UiDump "$EvidencePrefix-input"
    $sendAction = Find-UiNode -Document $input -Candidates @('发送本地弹幕', 'Send local danmaku') -Clickable
    if (-not $sendAction) { throw "The send action disappeared after entering text for $EvidencePrefix." }
    $keyboardBeforeSend = Get-KeyboardVisible "$EvidencePrefix-before-send"
    if ($keyboardBeforeSend) {
        # In landscape Android keeps the player at full size and draws the IME
        # above its bottom controls. UIAutomator still exposes the obscured
        # Flutter suffix button, but a coordinate tap reaches the keyboard
        # instead. Submit through the TextField IME action so onSubmitted uses
        # the same product path without relying on an occluded coordinate.
        Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_ENTER') | Out-Null
    } else {
        Tap-UiNode $sendAction
    }
    Start-Sleep -Milliseconds 300
    # Record IME state, but keep the route untouched. Pressing BACK based on a
    # slightly stale InputMethodService snapshot can pop the live-room route on
    # vendor Android builds where the keyboard finishes closing concurrently.
    $keyboardWasVisible = $keyboardBeforeSend -or (Get-KeyboardVisible "$EvidencePrefix-after-send")
    $queued = Save-UiDump "$EvidencePrefix-queued"
    $queuedObserved = $queued.OuterXml.Contains('2 秒后同步显示') -or -not $queued.OuterXml.Contains($Marker)
    Start-Sleep -Milliseconds 1900
    $delivered = Save-UiDump "$EvidencePrefix-delivered"
    Save-Screenshot "$EvidencePrefix-delivered"
    [pscustomobject]@{
        QueuedObserved = $queuedObserved
        Delivered = $delivered.OuterXml.Contains($Marker)
        KeyboardWasVisible = $keyboardWasVisible
        ActionsVisible = $null -ne $styleAction -and $null -ne $sendAction
        BeforeDocument = $before
        Document = $delivered
    }
}

function Get-LargestViewport {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $Document.SelectNodes('//node') | ForEach-Object {
        if ([string]$_.bounds -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
            $width = [int]$Matches[3] - [int]$Matches[1]
            $height = [int]$Matches[4] - [int]$Matches[2]
            [pscustomobject]@{ Width = $width; Height = $height; Area = $width * $height }
        }
    } | Sort-Object Area -Descending | Select-Object -First 1
}

function Focus-FullscreenComposer {
    $windowText = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'window', 'displays')) -join "`n"
    $size = [regex]::Match($windowText, 'cur=(\d+)x(\d+)')
    if (-not $size.Success) { throw 'Unable to parse the current Android display surface.' }
    $width = [int]$size.Groups[1].Value
    $height = [int]$size.Groups[2].Value
    # FullscreenLocalDanmakuComposer is centered between the left and right
    # action groups and occupies the lower control bar. Focus it immediately
    # after revealing controls so its FocusNode pins the bar before an
    # accessibility snapshot is collected.
    $x = [math]::Floor($width * 0.45)
    $y = [math]::Floor($height * $(if ($width -gt $height) { 0.93 } else { 0.90 }))
    [ordered]@{ width = $width; height = $height; x = $x; y = $y } |
        ConvertTo-Json | Out-File -LiteralPath (Join-Path $evidence 'fullscreen-focus-point.json') -Encoding utf8
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
    Start-Sleep -Milliseconds 250
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    apk = $apk
    checks = [ordered]@{}
}
$originalEnabled = $null
$failure = $null
try {
    $install = Invoke-Adb -AdbArguments @('install', '-r', '-t', $apk)
    $result.checks.install = ($install -join "`n").Trim()
    $result.checks.pageSizeBytes = [int](((Invoke-Adb -AdbArguments @('shell', 'getconf', 'PAGE_SIZE')) -join '').Trim())

    Open-LocalInteractionSettings
    $initial = Save-UiDump 'local-settings-initial'
    $originalEnabled = Get-LocalInteractionSwitchState $initial
    $result.checks.originalEnabled = $originalEnabled
    Set-LocalInteractionState -Enabled $true -EvidenceName 'local-settings-enabled'

    $room = Open-QuietRoom
    $result.checks.fixturePlatform = 'cc'
    $portraitStyle = Find-UiNode -Document $room -Candidates @('本地弹幕样式', 'Local danmaku style') -Clickable
    $portraitSend = Find-UiNode -Document $room -Candidates @('发送本地弹幕', 'Send local danmaku') -Clickable
    $result.checks.portraitComposerVisible = $null -ne $portraitStyle -and $null -ne $portraitSend
    if (-not $result.checks.portraitComposerVisible) { throw 'Enabled portrait local composer was not visible.' }

    $portraitMarker = 'PLP' + (Get-Date -Format 'HHmmss')
    $portrait = Send-LocalMessage -Marker $portraitMarker -EvidencePrefix 'portrait-local'
    $result.checks.portraitMarker = $portraitMarker
    $result.checks.portraitQueued = $portrait.QueuedObserved
    $result.checks.portraitKeyboardWasVisible = $portrait.KeyboardWasVisible
    $result.checks.portraitDeliveredToList = $portrait.Delivered
    if (-not $portrait.Delivered) { throw 'The delayed portrait local message did not appear in the danmaku list.' }

    # Re-enter the room before the fullscreen scenario. This separately proves
    # that the global enable switch survives an app restart and avoids making
    # the next navigation depend on vendor-IME focus/keyboard animation state.
    $roomAfterRestart = Open-QuietRoom
    $restartStyle = Find-UiNode -Document $roomAfterRestart -Candidates @('本地弹幕样式', 'Local danmaku style') -Clickable
    $restartSend = Find-UiNode -Document $roomAfterRestart -Candidates @('发送本地弹幕', 'Send local danmaku') -Clickable
    $result.checks.enabledAfterAppRestart = $null -ne $restartStyle -and $null -ne $restartSend
    if (-not $result.checks.enabledAfterAppRestart) {
        throw 'Local interaction was not enabled after restarting the app.'
    }

    & (Join-Path $repo 'tool\android_ui.ps1') -Tap live.show_controls -Serial $Serial -CaptureOnFailure
    & (Join-Path $repo 'tool\android_ui.ps1') -TapSemantic '进入全屏' -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Entering landscape fullscreen failed.' }
    Start-Sleep -Seconds 2
    & (Join-Path $repo 'tool\android_ui.ps1') -Tap live.show_controls -Serial $Serial -CaptureOnFailure
    Focus-FullscreenComposer
    $fullscreenMarker = 'PLF' + (Get-Date -Format 'HHmmss')
    $fullscreenResult = Send-LocalMessage -Marker $fullscreenMarker -EvidencePrefix 'fullscreen-local' -AlreadyFocused
    $viewport = Get-LargestViewport $fullscreenResult.BeforeDocument
    $result.checks.fullscreenOrientation = if ($viewport -and $viewport.Width -gt $viewport.Height) {
        'landscape'
    } else {
        'portrait'
    }
    $result.checks.fullscreenEntered =
        $fullscreenResult.ActionsVisible -and -not $fullscreenResult.BeforeDocument.OuterXml.Contains('弹幕列表')
    $result.checks.fullscreenComposerVisible = $fullscreenResult.ActionsVisible
    if (-not $result.checks.fullscreenEntered) { throw 'The player did not settle in fullscreen.' }
    if (-not $result.checks.fullscreenComposerVisible) { throw 'Enabled fullscreen local composer was not visible.' }
    $result.checks.fullscreenMarker = $fullscreenMarker
    $result.checks.fullscreenQueued = $fullscreenResult.QueuedObserved
    $result.checks.fullscreenKeyboardWasVisible = $fullscreenResult.KeyboardWasVisible

    # A CustomPainter danmaku overlay has no Android accessibility text node.
    # Return to the shared room list and assert the same delayed message there;
    # the screenshot captured above remains the visual overlay evidence.
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
    Start-Sleep -Milliseconds 650
    $afterBack = Save-UiDump 'fullscreen-after-first-back'
    if (-not $afterBack.OuterXml.Contains('弹幕列表')) {
        Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
        Start-Sleep -Seconds 2
    }
    $returned = Save-UiDump 'portrait-after-fullscreen-send'
    Save-Screenshot 'portrait-after-fullscreen-send'
    $result.checks.fullscreenDeliveredToSharedList = $returned.OuterXml.Contains($fullscreenMarker)
    if (-not $result.checks.fullscreenDeliveredToSharedList) {
        throw 'The delayed fullscreen local message did not reach the shared danmaku list.'
    }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
} finally {
    if ($null -ne $originalEnabled) {
        try {
            Open-LocalInteractionSettings
            Set-LocalInteractionState -Enabled ([bool]$originalEnabled) -EvidenceName 'local-settings-restored'
            $result.checks.originalStateRestored = $true
        } catch {
            $result.checks.originalStateRestored = $false
            if (-not $failure) { $failure = $_; $result.error = $_.Exception.Message }
        }
    }
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $result.checks.adbServerRecoveries = $adbServerRecoveries
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
