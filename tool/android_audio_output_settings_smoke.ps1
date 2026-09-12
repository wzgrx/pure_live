[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron',
    [string] $ExpectedApkSha256 = '',
    [switch] $PlaybackProbe,
    [ValidateSet('auto', 'audiotrack', 'aaudio', 'opensles', 'null')]
    [string[]] $Drivers = @('auto', 'audiotrack', 'aaudio', 'opensles', 'null')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo ("local-artifacts\diagnostics\android-audio-output-settings-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
} elseif ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    [IO.Path]::GetFullPath($EvidenceDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $repo $EvidenceDirectory))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

$adb = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
) | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ }
    else { [bool] (Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

$expectedLabels = [ordered]@{
    auto = 'auto (Automatic fallback)'
    audiotrack = 'audiotrack (Android AudioTrack)'
    aaudio = 'aaudio (Android 8.0+)'
    opensles = 'opensles (Legacy fallback)'
    null = 'null (No audio output)'
}
$expectedLabelValues = @($expectedLabels.Values)
$dataFile = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$remoteBackup = "/data/local/tmp/purelive-audio-output-$PID-original.hive"
$remoteRestore = "/data/local/tmp/purelive-audio-output-$PID-restore.hive"
$localBackup = Join-Path $evidence 'app_settings.original.hive'

function Invoke-TargetAdb {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    $output = @(& $adb -s $Serial @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $output
}

function Get-DeviceFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)
    $line = (Invoke-TargetAdb @('shell', "su -c `"sha256sum '$Path'`"")) -join "`n"
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Unexpected sha256sum output: $line" }
    $Matches[1].ToUpperInvariant()
}

function Assert-TargetForeground {
    $dump = (Invoke-TargetAdb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    if ($dump -notmatch ('(?m)^\s*topResumedActivity=.*\s' + [regex]::Escape($Package) + '/')) {
        throw 'Pure Live is not the exact top-resumed package.'
    }
}

function Get-UiHierarchy {
    param([Parameter(Mandatory = $true)][string] $Name)
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Assert-TargetForeground
        $raw = (Invoke-TargetAdb @('exec-out', 'uiautomator', 'dump', '--compressed', '/dev/tty')) -join "`n"
        $match = [regex]::Match($raw, '(?s)<\?xml\b.*?</hierarchy>')
        if ($match.Success) {
            [IO.File]::WriteAllText(
                (Join-Path $evidence "$Name.xml"),
                $match.Value,
                [Text.UTF8Encoding]::new($false)
            )
            return [xml] $match.Value
        }
        if ($attempt -lt 4) { Start-Sleep -Milliseconds (250 + 200 * $attempt) }
    }
    throw "UI hierarchy '$Name' did not return XML after four attempts."
}

function Get-NodeCenter {
    param([Parameter(Mandatory = $true)] $Node)
    if ([string] $Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Unexpected UI bounds: $($Node.bounds)"
    }
    [pscustomobject]@{
        X = [int] (([int] $Matches[1] + [int] $Matches[3]) / 2)
        Y = [int] (([int] $Matches[2] + [int] $Matches[4]) / 2)
    }
}

function Get-NodeLabel {
    param([Parameter(Mandatory = $true)] $Node)
    (([string] $Node.text) + "`n" + ([string] $Node.'content-desc')).Trim()
}

function Find-LabeledNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Labels,
        [switch] $Clickable,
        [switch] $Checkable
    )
    foreach ($label in $Labels) {
        $node = @($Document.SelectNodes('//node')) | Where-Object {
            $actual = Get-NodeLabel $_
            (-not $Clickable.IsPresent -or [string] $_.clickable -eq 'true') -and
            (-not $Checkable.IsPresent -or [string] $_.checkable -eq 'true') -and
            ($actual -eq $label -or $actual.StartsWith("$label`n"))
        } | Select-Object -First 1
        if ($node) { return $node }
    }
    $null
}

function Find-LabeledNodeWithScroll {
    param(
        [Parameter(Mandatory = $true)][string[]] $Labels,
        [Parameter(Mandatory = $true)][string] $EvidenceName,
        [switch] $Checkable
    )
    for ($attempt = 0; $attempt -lt 7; $attempt++) {
        $document = Get-UiHierarchy "$EvidenceName-$attempt"
        $node = Find-LabeledNode -Document $document -Labels $Labels -Clickable -Checkable:$Checkable
        if ($node) { return [pscustomobject]@{ Document = $document; Node = $node; Scrolls = $attempt } }
        Invoke-TargetAdb @('shell', 'input', 'swipe', '600', '2150', '600', '700', '420') | Out-Null
        Start-Sleep -Milliseconds 650
    }
    throw "Visible control was not found: $($Labels -join ' / ')"
}

function Invoke-NodeTap {
    param([Parameter(Mandatory = $true)] $Node)
    $point = Get-NodeCenter $Node
    Assert-TargetForeground
    Invoke-TargetAdb @('shell', 'input', 'tap', [string] $point.X, [string] $point.Y) | Out-Null
    Start-Sleep -Milliseconds 850
}

function Open-PlayerKernelSettings {
    param([Parameter(Mandatory = $true)][string] $Phase)
    Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
    $route = @(& (Join-Path $PSScriptRoot 'android_ui.ps1') `
        -Sequence open_player_kernel_settings -Serial $Serial -CaptureOnFailure *>&1)
    if (-not $?) { throw ($route -join "`n") }
    $route | Set-Content -LiteralPath (Join-Path $evidence "$Phase-route.txt") -Encoding utf8
    $joined = $route -join "`n"
    if ($joined -notmatch "tap semantic '" -or $joined -notmatch "assert semantic '") {
        throw "${Phase}: semantic route evidence is incomplete."
    }
    $document = Get-UiHierarchy "$Phase-kernel"
    if (-not ($document.OuterXml.Contains('核心内核设置') -or
            $document.OuterXml.Contains('Core Kernel Settings'))) {
        throw "${Phase}: player-kernel destination heading is missing."
    }
    $document
}

function Get-CustomOutputSwitch {
    param([Parameter(Mandatory = $true)][string] $Phase)
    Find-LabeledNodeWithScroll `
        -Labels @('自定义驱动与硬件加速', 'Custom Driver & Hardware Acceleration') `
        -EvidenceName "$Phase-custom" -Checkable
}

function Enable-CustomOutput {
    param([Parameter(Mandatory = $true)][string] $Phase)
    $found = Get-CustomOutputSwitch $Phase
    if ([string] $found.Node.checked -ne 'true') {
        Invoke-NodeTap $found.Node
        $found = Get-CustomOutputSwitch "$Phase-enabled"
    }
    if ([string] $found.Node.checked -ne 'true') { throw "${Phase}: custom output switch did not enable." }
    $found.Scrolls
}

function Assert-CustomOutputEnabled {
    param([Parameter(Mandatory = $true)][string] $Phase)
    $found = Get-CustomOutputSwitch $Phase
    if ([string] $found.Node.checked -ne 'true') { throw "${Phase}: custom output setting did not persist." }
    $found.Scrolls
}

function Open-AudioOutputDialog {
    param([Parameter(Mandatory = $true)][string] $Phase)
    $audio = Find-LabeledNodeWithScroll `
        -Labels @('音频输出驱动(--ao)', 'Audio Output Driver (--ao)') `
        -EvidenceName "$Phase-audio-menu"
    Invoke-NodeTap $audio.Node
    [pscustomobject]@{
        Scrolls = $audio.Scrolls
        Document = Get-UiHierarchy "$Phase-audio-dialog"
    }
}

function Assert-AudioOutputDialog {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string] $ExpectedDriver,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $buttons = @($Document.SelectNodes('//node') | Where-Object {
        [string] $_.class -eq 'android.widget.RadioButton'
    })
    $labels = @($buttons | ForEach-Object { Get-NodeLabel $_ })
    if ($buttons.Count -ne $expectedLabelValues.Count -or
        @(Compare-Object ($labels | Sort-Object) ($expectedLabelValues | Sort-Object)).Count -ne 0) {
        throw "${Phase}: Android audio-output option set differs: $($labels -join ' | ')"
    }
    $checked = @($buttons | Where-Object { [string] $_.checked -eq 'true' })
    $expectedLabel = [string] $expectedLabels[$ExpectedDriver]
    if ($checked.Count -ne 1 -or (Get-NodeLabel $checked[0]) -ne $expectedLabel) {
        throw "${Phase}: expected checked option '$expectedLabel'."
    }
    [ordered]@{ optionCount = $buttons.Count; checked = $ExpectedDriver; labels = $labels }
}

function Select-AudioOutput {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string] $Driver,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $label = [string] $expectedLabels[$Driver]
    $node = Find-LabeledNode -Document $Document -Labels @($label) -Clickable -Checkable
    if (-not $node) { throw "${Phase}: target radio option is missing: $label" }
    Invoke-NodeTap $node
    $after = Get-UiHierarchy "$Phase-after-select"
    $radioButtons = @($after.SelectNodes('//node') | Where-Object {
        [string] $_.class -eq 'android.widget.RadioButton'
    })
    if ($radioButtons.Count -gt 0) {
        Invoke-TargetAdb @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
        Start-Sleep -Milliseconds 500
        $after = Get-UiHierarchy "$Phase-after-dialog-close"
    }
    $menu = Find-LabeledNode -Document $after `
        -Labels @('音频输出驱动(--ao)', 'Audio Output Driver (--ao)') -Clickable
    if (-not $menu -or -not (Get-NodeLabel $menu).Contains($label)) {
        throw "${Phase}: kernel page did not display selected option '$label'."
    }
}

function Close-Dialog {
    Invoke-TargetAdb @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
    Start-Sleep -Milliseconds 400
}

function Save-Text {
    param([Parameter(Mandatory = $true)][string] $Name, [AllowNull()][object] $Value)
    $Value | Out-File -LiteralPath (Join-Path $evidence $Name) -Encoding utf8 -Width 8192
}

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    $remote = "/sdcard/purelive-audio-output-$PID-$Name.png"
    $local = Join-Path $evidence "$Name.png"
    try {
        Invoke-TargetAdb @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-TargetAdb @('pull', $remote, $local) | Out-Null
    } finally {
        try { Invoke-TargetAdb @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
    $local
}

function Invoke-AudioPlaybackProbe {
    param([Parameter(Mandatory = $true)][string] $Driver)
    $phase = "driver-$Driver-playback"
    Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
    $route = @(& (Join-Path $PSScriptRoot 'android_ui.ps1') `
        -Sequence enter_first_bilibili_room -Serial $Serial -CaptureOnFailure *>&1)
    if (-not $?) { throw ($route -join "`n") }
    $route | Set-Content -LiteralPath (Join-Path $evidence "$phase-route.txt") -Encoding utf8

    $roomDocument = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $candidate = Get-UiHierarchy "$phase-room-$attempt"
        $raw = $candidate.OuterXml
        if (($raw.Contains('弹幕列表') -and $raw.Contains('弹幕设置')) -or
            ($raw.Contains('Danmaku List') -and $raw.Contains('Danmaku Settings'))) {
            $roomDocument = $candidate
            break
        }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $roomDocument) { throw "${phase}: live-room semantics did not appear." }
    Start-Sleep -Seconds 8
    $roomDocument = Get-UiHierarchy "$phase-room-settled"
    $frameOnePath = Save-Screenshot "$phase-frame-1"
    Start-Sleep -Seconds 2
    $frameTwoPath = Save-Screenshot "$phase-frame-2"
    $frameOneSha256 = (Get-FileHash -LiteralPath $frameOnePath -Algorithm SHA256).Hash
    $frameTwoSha256 = (Get-FileHash -LiteralPath $frameTwoPath -Algorithm SHA256).Hash
    $screenFramesChanged = $frameOneSha256 -ne $frameTwoSha256

    $pidText = (Invoke-TargetAdb @('shell', 'pidof', $Package)) -join ' '
    if ($pidText.Trim() -notmatch '^(\d+)$') { throw "${phase}: expected one app PID, got '$pidText'." }
    $appProcessId = $Matches[1]
    $logcat = Invoke-TargetAdb @('logcat', '-d', '-v', 'threadtime', "--pid=$appProcessId", '-t', '4000')
    Save-Text "$phase-logcat.txt" $logcat
    $logText = $logcat -join "`n"

    $audioFlinger = Invoke-TargetAdb @('shell', 'dumpsys', 'media.audio_flinger')
    Save-Text "$phase-audio-flinger.txt" $audioFlinger
    $audioFlingerText = $audioFlinger -join "`n"
    $surfaceLayers = @(
        Invoke-TargetAdb @('shell', 'dumpsys', 'SurfaceFlinger', '--list') |
            Where-Object { [string] $_ -match [regex]::Escape($Package) }
    )
    Save-Text "$phase-surface-layers.txt" $surfaceLayers

    $audioTrackStartCount = ([regex]::Matches($logText, '(?im)\bAudioTrack:\s+start\(')).Count
    $aaudioLineCount = ([regex]::Matches($logText, '(?im)\bAAudio[A-Za-z_]*')).Count
    $openSlesLineCount = ([regex]::Matches($logText, '(?im)(?:OpenSL\s*ES|OpenSLES|libOpenSLES)')).Count
    $mediaKitLoaded = ([regex]::Matches(
        $logText,
        '(?im)media_kit:\s+NativeReferenceHolder:\s+Allocated\b'
    )).Count -gt 0
    $fijkLoaded = ([regex]::Matches(
        $logText,
        '(?im)(?:\[fijk\].*create player id:|IJKMEDIA:\s+ijkmediaplayer version)'
    )).Count -gt 0
    $betterPlayerLoaded = ([regex]::Matches(
        $logText,
        '(?im)(?:\bExoPlayerImpl\b|\bandroidx\.media3\b)'
    )).Count -gt 0
    $audioSuppressionAppliedCount = ([regex]::Matches(
        $logText,
        '(?im)PlayerManager:\s+Suppressing audio output for automatic fallback engine:'
    )).Count
    $fijkAudioDisableOptionCount = ([regex]::Matches(
        $logText,
        '(?im)\[fijk\].*setOption k:an, v:1\b'
    )).Count
    $fijkAudioRenderCount = ([regex]::Matches(
        $logText,
        '(?im)(?:first audio frame rendered|FFP_MSG_AUDIO_RENDERING_START|\[fijk\].*audio rendering started)'
    )).Count
    $activeAudioFlingerTrackCount = ([regex]::Matches(
        $audioFlingerText,
        "(?m)^\s*\d+\s+yes\s+$appProcessId/\s+\d+\b"
    )).Count
    $backendSignalMatched = switch ($Driver) {
        'auto' { $audioTrackStartCount -gt 0 }
        'audiotrack' { $audioTrackStartCount -gt 0 }
        'aaudio' { $aaudioLineCount -gt 0 }
        'opensles' { $openSlesLineCount -gt 0 }
        'null' {
            $audioTrackStartCount -eq 0 -and
            $aaudioLineCount -eq 0 -and
            $openSlesLineCount -eq 0 -and
            $activeAudioFlingerTrackCount -eq 0 -and
            $fijkAudioRenderCount -eq 0 -and
            (-not $fijkLoaded -or $fijkAudioDisableOptionCount -gt 0)
        }
        default { $false }
    }
    $nativeVideoLineCount = ([regex]::Matches(
        $logText,
        '(?im)(?:CCodec.*c2\..*decoder|MediaCodec.*setState:\s*STARTED)'
    )).Count
    $fatalOrAnrCount = ([regex]::Matches($logText, '(?im)FATAL EXCEPTION|ANR in com\.mystyle\.purelive')).Count

    [ordered]@{
        pid = [int] $appProcessId
        roomSemanticsVisible = $true
        packageSurfaceLayerCount = $surfaceLayers.Count
        nativeVideoLineCount = $nativeVideoLineCount
        frameOneSha256 = $frameOneSha256
        frameTwoSha256 = $frameTwoSha256
        screenFramesChanged = $screenFramesChanged
        mediaKitLoaded = $mediaKitLoaded
        fijkLoaded = $fijkLoaded
        betterPlayerLoaded = $betterPlayerLoaded
        audioSuppressionAppliedCount = $audioSuppressionAppliedCount
        fijkAudioDisableOptionCount = $fijkAudioDisableOptionCount
        fijkAudioRenderCount = $fijkAudioRenderCount
        audioTrackStartCount = $audioTrackStartCount
        aaudioLineCount = $aaudioLineCount
        openSlesLineCount = $openSlesLineCount
        binderDeathRecipientWarningCount = ([regex]::Matches($logText, 'AIBinder_linkToDeath')).Count
        activeAudioFlingerTrackCount = $activeAudioFlingerTrackCount
        backendSignalMatched = [bool] $backendSignalMatched
        noFatalOrAnr = $fatalOrAnrCount -eq 0
    }
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    requestedDrivers = @($Drivers)
    playbackProbe = $PlaybackProbe.IsPresent
    expectedOptions = @($expectedLabelValues)
    identity = $null
    apk = [ordered]@{}
    settingsFile = [ordered]@{}
    driverResults = @()
    checks = [ordered]@{}
    error = $null
    restoreError = $null
    passed = $false
}
$failure = $null
$settingsBackedUp = $false
$ownerUid = $null
$ownerGid = $null
$mode = $null

try {
    $identityText = (Invoke-TargetAdb @('shell', 'getprop ro.product.model; getprop ro.product.device; su -c id')) -join "`n"
    if ($identityText -notmatch "(?m)^$([regex]::Escape($ExpectedModel))\s*$" -or
        $identityText -notmatch "(?m)^$([regex]::Escape($ExpectedDevice))\s*$" -or
        $identityText -notmatch 'uid=0\(root\)') {
        throw "Unexpected target identity:`n$identityText"
    }
    $result.identity = [ordered]@{ model = $ExpectedModel; device = $ExpectedDevice; root = $true }
    $result.checks.identityMatched = $true

    $packagePath = (Invoke-TargetAdb @('shell', 'pm', 'path', $Package) |
        Where-Object { $_ -like 'package:*' } | Select-Object -First 1)
    if (-not $packagePath) { throw 'Installed Pure Live package path is missing.' }
    $packagePath = ([string] $packagePath).Substring(8).Trim()
    $result.apk.path = $packagePath
    $result.apk.sha256 = Get-DeviceFileHash $packagePath
    $result.apk.expectedSha256 = if ($ExpectedApkSha256) { $ExpectedApkSha256.ToUpperInvariant() } else { $null }
    $result.apk.matchesExpected = if ($ExpectedApkSha256) {
        $result.apk.sha256 -eq $ExpectedApkSha256.ToUpperInvariant()
    } else { $null }
    if ($ExpectedApkSha256 -and -not $result.apk.matchesExpected) {
        throw "Installed APK SHA-256 differs: $($result.apk.sha256)"
    }
    $result.checks.installedApkRecorded = $true

    Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
    $metadata = (Invoke-TargetAdb @('shell', "su -c `"stat -c '%u:%g:%a' '$dataFile'`"")) -join ''
    if ($metadata -notmatch '^(\d+):(\d+):(\d+)$') { throw "Unexpected settings metadata: $metadata" }
    $ownerUid = $Matches[1]
    $ownerGid = $Matches[2]
    $mode = $Matches[3]
    $result.settingsFile.metadata = $metadata
    $result.settingsFile.originalSha256 = Get-DeviceFileHash $dataFile
    Invoke-TargetAdb @(
        'shell',
        "su -c `"cp '$dataFile' '$remoteBackup' && chown shell:shell '$remoteBackup' && chmod 600 '$remoteBackup'`""
    ) | Out-Null
    Invoke-TargetAdb @('pull', $remoteBackup, $localBackup) | Out-Null
    $localHash = (Get-FileHash -LiteralPath $localBackup -Algorithm SHA256).Hash
    $result.settingsFile.localBackupSha256 = $localHash
    if ($localHash -ne $result.settingsFile.originalSha256) { throw 'Settings backup hash differs from device file.' }
    $settingsBackedUp = $true
    $result.checks.settingsBackedUpExactly = $true

    $driverResults = [Collections.Generic.List[object]]::new()
    foreach ($driver in $Drivers) {
        $phase = "driver-$driver"
        Open-PlayerKernelSettings "$phase-before" | Out-Null
        $customScrolls = Enable-CustomOutput "$phase-before"
        $dialog = Open-AudioOutputDialog "$phase-select"
        Select-AudioOutput -Document $dialog.Document -Driver $driver -Phase "$phase-select"

        $immediateDialog = Open-AudioOutputDialog "$phase-immediate"
        $immediate = Assert-AudioOutputDialog `
            -Document $immediateDialog.Document -ExpectedDriver $driver -Phase "$phase-immediate"
        Close-Dialog

        Open-PlayerKernelSettings "$phase-relaunch" | Out-Null
        $relaunchCustomScrolls = Assert-CustomOutputEnabled "$phase-relaunch"
        $relaunchDialog = Open-AudioOutputDialog "$phase-relaunch"
        $relaunch = Assert-AudioOutputDialog `
            -Document $relaunchDialog.Document -ExpectedDriver $driver -Phase "$phase-relaunch"
        Close-Dialog
        $playback = if ($PlaybackProbe.IsPresent) { Invoke-AudioPlaybackProbe $driver } else { $null }
        Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null

        $driverResults.Add([ordered]@{
            driver = $driver
            label = [string] $expectedLabels[$driver]
            customSwitchScrolls = $customScrolls
            relaunchCustomSwitchScrolls = $relaunchCustomScrolls
            selectDialogScrolls = $dialog.Scrolls
            relaunchDialogScrolls = $relaunchDialog.Scrolls
            immediate = $immediate
            relaunch = $relaunch
            playback = $playback
            settingsSha256 = Get-DeviceFileHash $dataFile
        })
        $result.driverResults = @($driverResults)
        Write-Output "PASS Android audio output '$driver' immediate and relaunch persistence"
    }
    $result.driverResults = @($driverResults)
    $result.checks.exactAndroidOptionSet = @($driverResults | Where-Object {
        $_.immediate.optionCount -ne 5 -or $_.relaunch.optionCount -ne 5
    }).Count -eq 0
    $result.checks.allChoicesAppliedImmediately = $driverResults.Count -eq $Drivers.Count
    $result.checks.allChoicesPersistedAcrossRelaunch = $driverResults.Count -eq $Drivers.Count
    if ($PlaybackProbe.IsPresent) {
        $result.checks.allPlaybackRoomsReached = @($driverResults | Where-Object {
            -not $_.playback.roomSemanticsVisible
        }).Count -eq 0
        $result.checks.allPlaybackVideoPathsObserved = @($driverResults | Where-Object {
            $_.playback.packageSurfaceLayerCount -lt 1 -or
            $_.playback.nativeVideoLineCount -lt 1 -or
            -not $_.playback.screenFramesChanged
        }).Count -eq 0
        $result.checks.allBackendSignalsMatched = @($driverResults | Where-Object {
            -not $_.playback.backendSignalMatched
        }).Count -eq 0
        $result.checks.allPlaybackRunsFreeOfFatalOrAnr = @($driverResults | Where-Object {
            -not $_.playback.noFatalOrAnr
        }).Count -eq 0
    }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
} finally {
    try { Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    if ($settingsBackedUp) {
        try {
            Invoke-TargetAdb @('push', $localBackup, $remoteRestore) | Out-Null
            Invoke-TargetAdb @(
                'shell',
                "su -c `"cat '$remoteRestore' > '$dataFile' && chown ${ownerUid}:${ownerGid} '$dataFile' && chmod '$mode' '$dataFile' && restorecon '$dataFile'`""
            ) | Out-Null
            $result.settingsFile.restoredSha256 = Get-DeviceFileHash $dataFile
            $result.checks.settingsRestoredExactly = `
                $result.settingsFile.restoredSha256 -eq $result.settingsFile.originalSha256
            if (-not $result.checks.settingsRestoredExactly -and -not $failure) {
                $failure = [InvalidOperationException]::new('Original settings hash was not restored.')
            }
        } catch {
            $result.restoreError = $_.Exception.Message
            if (-not $failure) { $failure = $_ }
        }
    }
    try { Invoke-TargetAdb @('shell', 'rm', '-f', $remoteBackup, $remoteRestore) | Out-Null } catch {}
    try { Invoke-TargetAdb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try { Invoke-TargetAdb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $pidOutput = @(& $adb -s $Serial shell pidof $Package 2>&1)
    $pidCode = $LASTEXITCODE
    $result.checks.appStopped = $pidCode -in @(0, 1) -and [string]::IsNullOrWhiteSpace(($pidOutput -join ''))
    if (-not $result.checks.appStopped -and -not $failure) {
        $failure = [InvalidOperationException]::new("Pure Live remained active after cleanup: $($pidOutput -join ' ')")
    }
    $failedChecks = @($result.checks.GetEnumerator() | Where-Object { -not [bool] $_.Value })
    $result.passed = $null -eq $failure -and $failedChecks.Count -eq 0
    if (-not $result.passed -and -not $result.error) {
        $result.error = if ($failure) { $failure.Exception.Message } else {
            "Failed checks: $($failedChecks.Key -join ', ')"
        }
    }
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
if (-not $result.passed) { throw $result.error }
$global:LASTEXITCODE = 0
