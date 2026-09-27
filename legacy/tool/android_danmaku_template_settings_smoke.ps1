[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Serial,
    [Parameter(Mandatory = $true)]
    [string] $ApkPath,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-danmaku-template-settings-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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

. (Join-Path $PSScriptRoot 'android_recording_navigation.ps1')

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $output = @(& $adb -s $Serial @AdbArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($AdbArguments -join ' ')`n$($output -join "`n")"
    }
    $output
}

function Get-Identity {
    $text = (Invoke-Adb -AdbArguments @('shell', 'getprop ro.product.model; getprop ro.product.device; su -c id')) -join "`n"
    if ($text -notmatch "(?m)^$([regex]::Escape($ExpectedModel))\s*$" -or
        $text -notmatch "(?m)^$([regex]::Escape($ExpectedDevice))\s*$" -or
        $text -notmatch 'uid=0\(root\)') {
        throw "Unexpected target identity:`n$text"
    }
    [ordered]@{ model = $ExpectedModel; device = $ExpectedDevice; root = $true }
}

function Get-ForegroundPackage {
    $dump = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    Get-RecordingForegroundPackage -ActivityDump $dump
}

function Assert-PackageForeground {
    param([Parameter(Mandatory = $true)][string] $Phase)
    $foreground = Get-ForegroundPackage
    if ($foreground -cne $Package) {
        throw "${Phase}: expected $Package in the foreground, observed '$foreground'; no input was sent."
    }
}

function Save-UiState {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remoteXml = "/sdcard/purelive-danmaku-template-$PID-$Name.xml"
    $remotePng = "/sdcard/purelive-danmaku-template-$PID-$Name.png"
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
        Top = [int]$Matches[2]
        Right = [int]$Matches[3]
        Bottom = [int]$Matches[4]
        X = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
        Y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    }
}

function Get-NodeLabel {
    param([Parameter(Mandatory = $true)] $Node)
    ("{0}`n{1}" -f ([string]$Node.text), ([string]$Node.'content-desc')).Trim()
}

function Find-LabeledNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [string] $Class,
        [switch] $Clickable,
        [switch] $Checkable
    )
    $matches = @($Document.SelectNodes('//node') | Where-Object {
        $node = $_
        $label = Get-NodeLabel $node
        (-not $Class -or [string]$node.class -eq $Class) -and
            (-not $Clickable.IsPresent -or [string]$node.clickable -eq 'true') -and
            (-not $Checkable.IsPresent -or [string]$node.checkable -eq 'true') -and
            @($Candidates | Where-Object { $label.Contains($_) }).Count -gt 0
    })
    $matches | Sort-Object {
        $label = Get-NodeLabel $_
        if (@($Candidates | Where-Object { $label -eq $_ }).Count -gt 0) { 0 } else { 1 }
    }, { (Get-BoundsCenter $_).Top } | Select-Object -First 1
}

function Tap-Node {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [Parameter(Mandatory = $true)][string] $Phase,
        [switch] $Trailing
    )
    Assert-PackageForeground $Phase
    $bounds = Get-BoundsCenter $Node
    $x = if ($Trailing) {
        [math]::Max($bounds.Left + 1, $bounds.Right - [math]::Min(70, [math]::Floor(($bounds.Right - $bounds.Left) / 2)))
    } else {
        $bounds.X
    }
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $bounds.Y) | Out-Null
    Start-Sleep -Milliseconds 900
}

function Tap-LabeledNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $Phase,
        [switch] $Trailing
    )
    $node = Find-LabeledNode -Document $Document -Candidates $Candidates -Clickable
    if (-not $node) { throw "${Phase}: expected control was not found: $($Candidates -join ' / ')." }
    Tap-Node -Node $node -Phase $Phase -Trailing:$Trailing
}

function Get-SwitchState {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $node = Find-LabeledNode -Document $Document -Candidates $Candidates -Class 'android.widget.Switch' -Checkable
    if (-not $node) { throw "${Phase}: switch semantics are missing: $($Candidates -join ' / ')." }
    [pscustomobject]@{
        Node = $node
        Checked = [string]$node.checked -eq 'true'
        Label = Get-NodeLabel $node
    }
}

function Get-CounterValue {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $node = @($Document.SelectNodes('//node') | Where-Object {
        $label = Get-NodeLabel $_
        $label -match '(?:,|，)\s*\d+\s*$' -and
            @($Candidates | Where-Object { $label.StartsWith($_) }).Count -gt 0
    } | Sort-Object { (Get-BoundsCenter $_).Top }) | Select-Object -First 1
    if (-not $node) { throw "${Phase}: counter value semantics are missing: $($Candidates -join ' / ')." }
    $label = Get-NodeLabel $node
    if ($label -notmatch '(?:,|，)\s*(\d+)\s*$') { throw "${Phase}: counter label has no numeric value: $label" }
    [pscustomobject]@{ Node = $node; Value = [int]$Matches[1]; Label = $label }
}

function Invoke-SettingsScroll {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][ValidateSet('Down', 'Up')][string] $Direction,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    Assert-PackageForeground $Phase
    $root = $Document.SelectSingleNode('/hierarchy/node')
    if (-not $root) { throw "${Phase}: root UI node is missing." }
    $bounds = Get-BoundsCenter $root
    if (($bounds.Right - $bounds.Left) -ge ($bounds.Bottom - $bounds.Top)) {
        throw "${Phase}: expected the portrait main-settings surface; no scroll was sent."
    }
    $x = [math]::Floor(($bounds.Left + $bounds.Right) / 2)
    $highY = [math]::Floor($bounds.Top + (($bounds.Bottom - $bounds.Top) * 0.58))
    $lowY = [math]::Floor($bounds.Top + (($bounds.Bottom - $bounds.Top) * 0.91))
    $startY = if ($Direction -eq 'Down') { $lowY } else { $highY }
    $endY = if ($Direction -eq 'Down') { $highY } else { $lowY }
    Invoke-Adb -AdbArguments @('shell', 'input', 'swipe', $x, $startY, $x, $endY, 450) | Out-Null
    Start-Sleep -Milliseconds 900
}

function Find-AfterScroll {
    param(
        [Parameter(Mandatory = $true)][xml] $InitialDocument,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][ValidateSet('Down', 'Up')][string] $Direction,
        [Parameter(Mandatory = $true)][string] $EvidencePrefix,
        [string] $Class,
        [switch] $Clickable,
        [int] $MaxSwipes = 5
    )
    $document = $InitialDocument
    for ($attempt = 0; $attempt -le $MaxSwipes; $attempt++) {
        $node = Find-LabeledNode -Document $document -Candidates $Candidates -Class $Class -Clickable:$Clickable
        if ($node) { return [pscustomobject]@{ Document = $document; Node = $node; Swipes = $attempt } }
        if ($attempt -eq $MaxSwipes) { break }
        Invoke-SettingsScroll -Document $document -Direction $Direction -Phase "$EvidencePrefix-scroll-$attempt"
        $document = Save-UiState "$EvidencePrefix-$($attempt + 1)"
    }
    throw "${EvidencePrefix}: expected control was not found after $MaxSwipes $Direction scrolls: $($Candidates -join ' / ')."
}

function Assert-TemplateSurface {
    param([Parameter(Mandatory = $true)][xml] $Document, [Parameter(Mandatory = $true)][string] $Phase)
    $restore = Find-LabeledNode -Document $Document -Candidates @('恢复已保存模板', 'Restore saved template') -Clickable
    if (-not $restore) { throw "${Phase}: embedded restore-template action is missing." }
    $save = Find-LabeledNode -Document $Document -Candidates @('保存当前模板', 'Save current template') -Clickable
    if (-not $save) { throw "${Phase}: save-template action is missing." }
    $pureText = Get-SwitchState -Document $Document -Candidates @('纯文字模式', 'Pure text') -Phase $Phase
    [ordered]@{
        pureTextChecked = $pureText.Checked
        pureTextSemantics = $pureText.Label
        saveVisible = $true
        restoreVisible = $true
    }
}

function Assert-AdjustableSurface {
    param([Parameter(Mandatory = $true)][xml] $Document, [Parameter(Mandatory = $true)][string] $Phase)
    $area = Find-LabeledNode -Document $Document -Candidates @('画面顶部占用高度', 'Danmaku area') -Class 'android.widget.SeekBar'
    if (-not $area) { throw "${Phase}: visible area slider does not announce its setting name." }
    $top = Get-CounterValue -Document $Document -Candidates @('顶部留白（像素）', 'Top margin') -Phase $Phase
    $increaseTop = Find-LabeledNode -Document $Document -Candidates @('增加顶部留白（像素）', 'Increase Top margin') -Clickable
    $decreaseTop = Find-LabeledNode -Document $Document -Candidates @('减少顶部留白（像素）', 'Decrease Top margin') -Clickable
    if (-not $increaseTop -or -not $decreaseTop) { throw "${Phase}: named top-margin counter actions are incomplete." }
    [ordered]@{
        topMargin = $top.Value
        topMarginSemantics = $top.Label
        areaSliderSemantics = Get-NodeLabel $area
        namedCounterActions = $true
    }
}

function Open-DanmakuSettings {
    param([Parameter(Mandatory = $true)][string] $Phase)
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 5
    $routeOutput = @(& (Join-Path $PSScriptRoot 'android_ui.ps1') `
        -Sequence enter_first_bilibili_room -Serial $Serial -CaptureOnFailure *>&1)
    if (-not $?) { throw ($routeOutput -join "`n") }
    $routeOutput | Set-Content -LiteralPath (Join-Path $evidence "$Phase-room-route.txt") -Encoding UTF8
    Start-Sleep -Seconds 8
    $room = Save-UiState "$Phase-room"
    if ($room.OuterXml -notmatch '弹幕列表|Danmaku List' -or $room.OuterXml -notmatch '弹幕设置|Danmaku Settings') {
        throw "${Phase}: live-room danmaku tabs are missing."
    }
    Tap-LabeledNode -Document $room -Candidates @('弹幕设置', 'Danmaku Settings') -Phase "$Phase-open-settings"
    $settings = Save-UiState "$Phase-settings"
    if ($settings.OuterXml -notmatch '弹幕观看模板|Danmaku viewing templates') {
        throw "${Phase}: main danmaku settings surface did not open."
    }
    $settings
}

function Get-DeviceFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)
    $line = (Invoke-Adb -AdbArguments @('shell', "su -c `"sha256sum '$Path'`"")) -join "`n"
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Unexpected sha256sum output: $line" }
    $Matches[1].ToUpperInvariant()
}

function Get-PackageState {
    $dump = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'package', $Package)) -join "`n"
    $pathLine = Invoke-Adb -AdbArguments @('shell', 'pm', 'path', $Package) |
        Where-Object { $_ -like 'package:*' } | Select-Object -First 1
    if ($dump -notmatch '(?m)^\s*versionName=([^\s]+)' -or -not $pathLine) {
        throw 'The installed Pure Live package state is incomplete.'
    }
    $versionName = $Matches[1]
    if ($dump -notmatch '(?m)^\s*versionCode=(\d+)') { throw 'Installed versionCode is missing.' }
    $versionCode = [int64]$Matches[1]
    if ($dump -notmatch '(?m)^\s*firstInstallTime=(.+)$') { throw 'Installed firstInstallTime is missing.' }
    [ordered]@{
        versionName = $versionName
        versionCode = $versionCode
        firstInstallTime = $Matches[1].Trim()
        apkPath = ([string]$pathLine).Substring(8).Trim()
    }
}

$dataFile = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$remoteBackup = "/data/local/tmp/purelive-danmaku-template-$PID-original.hive"
$remoteRestore = "/data/local/tmp/purelive-danmaku-template-$PID-restore.hive"
$localBackup = Join-Path $evidence 'app_settings.original.hive'
$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    sourceCommit = (git -C $repo rev-parse HEAD)
    apk = [ordered]@{
        path = $apk
        sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
    }
    identity = $null
    states = [ordered]@{}
    settingsFile = [ordered]@{}
    checks = [ordered]@{}
}
$failure = $null
$settingsBackedUp = $false

try {
    $result.identity = Get-Identity
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null

    $packageState = Get-PackageState
    $result.apk.installed = $packageState
    $deviceApkHash = Get-DeviceFileHash ([string]$packageState.apkPath)
    $result.apk.deviceSha256 = $deviceApkHash
    if ($deviceApkHash -ne $result.apk.sha256) { throw 'The installed base APK differs from the selected candidate.' }
    $result.checks.installedApkMatchesCandidate = $true

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
    if ((Get-FileHash -LiteralPath $localBackup -Algorithm SHA256).Hash -ne $result.settingsFile.originalSha256) {
        throw 'The local settings backup hash differs from the device file.'
    }
    $settingsBackedUp = $true

    $baselineXml = Open-DanmakuSettings 'baseline'
    $baselineTemplate = Assert-TemplateSurface $baselineXml 'baseline-template'

    Tap-LabeledNode -Document $baselineXml -Candidates @('保存当前模板', 'Save current template') -Phase 'save-template'
    $savedXml = Save-UiState 'saved-template'
    $pureText = Get-SwitchState -Document $savedXml -Candidates @('纯文字模式', 'Pure text') -Phase 'saved-template'
    Tap-Node -Node $pureText.Node -Phase 'toggle-pure-text' -Trailing
    $pureChangedXml = Save-UiState 'pure-text-changed'
    $pureChanged = Get-SwitchState -Document $pureChangedXml -Candidates @('纯文字模式', 'Pure text') -Phase 'pure-text-changed'
    if ($pureChanged.Checked -eq $baselineTemplate.pureTextChecked) {
        throw 'The full-row pure-text toggle did not change immediately.'
    }

    $topSearch = Find-AfterScroll -InitialDocument $pureChangedXml `
        -Candidates @('增加顶部留白（像素）', 'Increase Top margin') `
        -Direction Down -EvidencePrefix 'baseline-adjustable' -Clickable
    $baselineAdjustable = Assert-AdjustableSurface $topSearch.Document 'baseline-adjustable'
    $result.states.baseline = [ordered]@{}
    foreach ($entry in $baselineTemplate.GetEnumerator()) { $result.states.baseline[$entry.Key] = $entry.Value }
    foreach ($entry in $baselineAdjustable.GetEnumerator()) { $result.states.baseline[$entry.Key] = $entry.Value }

    Tap-Node -Node $topSearch.Node -Phase 'increase-top-margin'
    $customizedXml = Save-UiState 'customized'
    $result.states.customized = Assert-AdjustableSurface $customizedXml 'customized'
    if ($result.states.customized.topMargin -ne $result.states.baseline.topMargin + 1) {
        throw 'The top-margin increment action did not advance by one.'
    }

    $restoreSearch = Find-AfterScroll -InitialDocument $customizedXml `
        -Candidates @('恢复已保存模板', 'Restore saved template') `
        -Direction Up -EvidencePrefix 'restore-template' -Clickable
    Tap-Node -Node $restoreSearch.Node -Phase 'restore-template'
    $restoredXml = Save-UiState 'restored-immediate'
    $restoredTemplate = Assert-TemplateSurface $restoredXml 'restored-immediate-template'
    $restoredAdjustSearch = Find-AfterScroll -InitialDocument $restoredXml `
        -Candidates @('增加顶部留白（像素）', 'Increase Top margin') `
        -Direction Down -EvidencePrefix 'restored-immediate-adjustable' -Clickable
    $restoredAdjustable = Assert-AdjustableSurface $restoredAdjustSearch.Document 'restored-immediate-adjustable'
    $result.states.restoredImmediate = [ordered]@{}
    foreach ($entry in $restoredTemplate.GetEnumerator()) { $result.states.restoredImmediate[$entry.Key] = $entry.Value }
    foreach ($entry in $restoredAdjustable.GetEnumerator()) { $result.states.restoredImmediate[$entry.Key] = $entry.Value }
    if ($result.states.restoredImmediate.pureTextChecked -ne $result.states.baseline.pureTextChecked -or
        $result.states.restoredImmediate.topMargin -ne $result.states.baseline.topMargin) {
        throw 'Restore did not atomically return the changed switch and counter to the saved values.'
    }

    $relaunchXml = Open-DanmakuSettings 'restored-relaunch'
    $relaunchTemplate = Assert-TemplateSurface $relaunchXml 'restored-relaunch-template'
    $relaunchAdjustSearch = Find-AfterScroll -InitialDocument $relaunchXml `
        -Candidates @('增加顶部留白（像素）', 'Increase Top margin') `
        -Direction Down -EvidencePrefix 'restored-relaunch-adjustable' -Clickable
    $relaunchAdjustable = Assert-AdjustableSurface $relaunchAdjustSearch.Document 'restored-relaunch-adjustable'
    $result.states.restoredRelaunch = [ordered]@{}
    foreach ($entry in $relaunchTemplate.GetEnumerator()) { $result.states.restoredRelaunch[$entry.Key] = $entry.Value }
    foreach ($entry in $relaunchAdjustable.GetEnumerator()) { $result.states.restoredRelaunch[$entry.Key] = $entry.Value }
    if ($result.states.restoredRelaunch.pureTextChecked -ne $result.states.baseline.pureTextChecked -or
        $result.states.restoredRelaunch.topMargin -ne $result.states.baseline.topMargin) {
        throw 'The restored template values did not persist across an app relaunch.'
    }

    $result.checks.embeddedRestoreVisible = $true
    $result.checks.namedMainControlsVisible = $true
    $result.checks.fullRowSwitchChanged = $true
    $result.checks.counterChanged = $true
    $result.checks.templateRestoredAtomically = $true
    $result.checks.restoredValuesPersistedAcrossRelaunch = $true
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
$global:LASTEXITCODE = 0
