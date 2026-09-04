[CmdletBinding()]
param(
    [string] $Serial,
    [string] $EvidenceDirectory,
    [ValidateRange(20, 300)]
    [int] $RecordSeconds = 45,
    [ValidateRange(0, 180)]
    [int] $ScreenOffSeconds = 0,
    [ValidateRange(10, 90)]
    [int] $PlatformLoadTimeoutSeconds = 45,
    [ValidateSet('bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy')]
    [string] $Platform = 'bilibili',
    [string] $Package = 'com.mystyle.purelive',
    [string] $Activity = '.MainActivity',
    [switch] $RequireLiveDanmaku
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo (
        'local-artifacts\diagnostics\android-recording-smoke-{0}' -f
        [DateTime]::Now.ToString('yyyyMMddTHHmmssfff')
    )
} else {
    $candidate = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
        $EvidenceDirectory
    } else {
        Join-Path $repo $EvidenceDirectory
    }
    [IO.Path]::GetFullPath($candidate)
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

$adbCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
)
$adb = $adbCandidates | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ -PathType Leaf }
    else { [bool](Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

$platformLabels = @{
    bilibili = '哔哩哔哩'
    douyu = '斗鱼'
    huya = '虎牙'
    douyin = '抖音'
    kuaishou = '快手'
    cc = '网易CC'
    twitch = 'Twitch'
    soop = 'Soop'
    yy = 'YY'
}
$platformLabel = $platformLabels[$Platform]
$danmakuSupported = $Platform -ne 'cc'
$script:foregroundInterferenceCount = 0
$script:foregroundRecoveryCount = 0
$script:uiProfileData = $null
$script:uiWidth = 0
$script:uiHeight = 0

function Start-AdbServer {
    $output = & $adb start-server 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb start-server failed ($LASTEXITCODE):`n$($output -join "`n")"
    }
}

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $output = & $adb -s $script:serial @AdbArguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"
    if ($exitCode -ne 0 -and $text -match '(?i)cannot connect to daemon|daemon still not running') {
        Start-AdbServer
        Start-Sleep -Milliseconds 350
        $output = & $adb -s $script:serial @AdbArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0) {
        throw "adb failed ($exitCode): $($AdbArguments -join ' ')`n$($output -join "`n")"
    }
    $output
}

function Save-Text {
    param([string] $Name, [object] $Value)
    $Value | Out-File -LiteralPath (Join-Path $evidence $Name) -Encoding utf8 -Width 4096
}

function Save-ForegroundForensics {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Foreground
    )

    Save-Text "foreground-changed-$Name.txt" $Foreground
    $processOutput = & $adb -s $script:serial shell pidof $Package 2>&1
    $processExitCode = $LASTEXITCODE
    Save-Text "foreground-changed-$Name-process.txt" @(
        "exitCode=$processExitCode"
        $processOutput
    )
    Save-Text "foreground-changed-$Name-activities.txt" (
        Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'activities')
    )
    Save-Text "foreground-changed-$Name-exit-info.txt" (
        Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'exit-info', $Package)
    )
    Save-Text "foreground-changed-$Name-logcat.txt" (
        Invoke-Adb -AdbArguments @('logcat', '-d', '-t', '800')
    )
    return $processExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace(($processOutput -join ''))
}

function Save-UiDump {
    param([string] $Name)
    # K90 Pro locks after ten minutes. Slow wireless ADB calls can cross that
    # boundary during one smoke, so refresh the no-password keyguard before
    # every UI observation instead of trusting the wrapper's initial wake.
    Wake-AndDismissKeyguard
    $remote = "/sdcard/purelive-record-$PID-$Name.xml"
    $local = Join-Path $evidence "$Name.xml"
    $failures = [Collections.Generic.List[string]]::new()
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $dumpOutput = Invoke-Adb -AdbArguments @('shell', 'uiautomator', 'dump', '--compressed', $remote)
            $dumpText = $dumpOutput -join "`n"
            if ($dumpText -match '(?i)error|exception') { throw $dumpText }
            Invoke-Adb -AdbArguments @('pull', $remote, $local) | Out-Null
            if ((Test-Path -LiteralPath $local -PathType Leaf) -and (Get-Item -LiteralPath $local).Length -gt 0) {
                $foreground = Get-Foreground
                if ($foreground -notmatch [regex]::Escape($Package)) {
                    $processAlive = Save-ForegroundForensics `
                        -Name "$Name-attempt$attempt" `
                        -Foreground $foreground
                    $script:foregroundInterferenceCount++
                    Save-Text "foreground-changed-$Name-attempt$attempt-restore.txt" (
                        Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity")
                    )
                    Start-Sleep -Milliseconds 900
                    $restoredForeground = Get-Foreground
                    $restored = $restoredForeground -match [regex]::Escape($Package)
                    if ($restored) { $script:foregroundRecoveryCount++ }
                    throw (
                        "Pure Live lost foreground during its device lease " +
                        "(processAlive=$processAlive, restored=$restored): $foreground"
                    )
                }
                return
            }
            throw 'UI dump was empty.'
        } catch {
            $failures.Add("attempt ${attempt}: $($_.Exception.Message)")
            Start-Sleep -Milliseconds (350 * $attempt)
        } finally {
            try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
        }
    }
    throw "UI dump '$Name' failed after 4 attempts:`n$($failures -join "`n")"
}

function Save-Screenshot {
    param([string] $Name)
    Wake-AndDismissKeyguard
    $remote = "/sdcard/purelive-record-$PID-$Name.png"
    try {
        Invoke-Adb -AdbArguments @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null
    }
}

function Wait-HomeRoomCard {
    param([int] $TimeoutSeconds = 45)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $name = "home-platform-ready-$attempt"
        Save-UiDump $name
        $path = Join-Path $evidence "$name.xml"
        [xml]$document = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $roomNodes = @(
            $document.SelectNodes('//node') | Where-Object {
                if ($_.GetAttribute('clickable') -ne 'true' -or
                    $_.GetAttribute('long-clickable') -ne 'true' -or
                    $_.GetAttribute('bounds') -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
                    return $false
                }
                $left = [int]$Matches[1]
                $top = [int]$Matches[2]
                $right = [int]$Matches[3]
                $bottom = [int]$Matches[4]
                ($right - $left) -ge 240 -and ($bottom - $top) -ge 180 -and $top -ge 280
            }
        )
        if ($roomNodes.Count -gt 0) {
            return Get-Content -LiteralPath $path -Raw -Encoding UTF8
        }
        if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 2 }
    } while ([DateTime]::UtcNow -lt $deadline)

    return $null
}

function Wait-UiPattern {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Pattern,
        [int] $TimeoutSeconds = 20
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Save-UiDump $Name
        $xml = Get-Content -LiteralPath (Join-Path $evidence "$Name.xml") -Raw -Encoding UTF8
        if ($xml -match $Pattern) {
            return [pscustomobject]@{ Xml = $xml; ElapsedMs = $timer.ElapsedMilliseconds }
        }
        Start-Sleep -Milliseconds 600
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "UI pattern did not settle within $TimeoutSeconds seconds: $Pattern"
}

function Test-UiSemanticEnabled {
    param(
        [Parameter(Mandatory = $true)][string] $Xml,
        [Parameter(Mandatory = $true)][string] $Semantic
    )
    try {
        [xml]$document = $Xml
        $matches = @(
            $document.SelectNodes('//node') | Where-Object {
                (
                    $_.GetAttribute('text') -eq $Semantic -or
                    $_.GetAttribute('content-desc') -eq $Semantic -or
                    $_.GetAttribute('text') -like "$Semantic`n*" -or
                    $_.GetAttribute('content-desc') -like "$Semantic`n*"
                ) -and
                $_.GetAttribute('enabled') -eq 'true' -and
                $_.GetAttribute('clickable') -eq 'true'
            }
        )
        return $matches.Count -gt 0
    } catch {
        return $false
    }
}

function Test-UiSemanticSelected {
    param(
        [Parameter(Mandatory = $true)][string] $Xml,
        [Parameter(Mandatory = $true)][string] $Semantic
    )
    try {
        [xml]$document = $Xml
        $matches = @($document.SelectNodes('//node') | Where-Object {
            (
                $_.GetAttribute('text') -eq $Semantic -or
                $_.GetAttribute('content-desc') -eq $Semantic -or
                $_.GetAttribute('text') -like "$Semantic`n*" -or
                $_.GetAttribute('content-desc') -like "$Semantic`n*"
            ) -and $_.GetAttribute('selected') -eq 'true'
        })
        $matches.Count -gt 0
    } catch {
        $false
    }
}

function Select-UiSemanticTab {
    param(
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $EvidencePrefix
    )
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $name = "$EvidencePrefix-$attempt"
        Save-UiDump $name
        $xml = Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw -Encoding UTF8
        if (Test-UiSemanticSelected -Xml $xml -Semantic $Label) { return $xml }
        if (-not (Test-UiSemanticEnabled -Xml $xml -Semantic $Label)) {
            throw "UI tab '$Label' was not visible and enabled."
        }
        Invoke-Ui -Action TapSemantic -Value $Label -Xml $xml
        Start-Sleep -Milliseconds 900
    }
    throw "UI tab '$Label' did not become selected after bounded retries."
}

function Get-UiLabels {
    param([Parameter(Mandatory = $true)][string] $Xml)
    [xml]$document = $Xml
    @(
        $document.SelectNodes('//node') | ForEach-Object {
            @($_.GetAttribute('text'), $_.GetAttribute('content-desc'))
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
    )
}

function Select-PlatformTab {
    param([Parameter(Mandatory = $true)][string] $Label)

    $targetIndex = @{
        # Current Flutter semantics include the aggregate "全部" item in the
        # platform TabBar. Keep these in sync with the accessibility ordinals;
        # unrelated status/bottom tabs are filtered by their smaller totals.
        '哔哩哔哩' = 2
        '斗鱼' = 3
        '虎牙' = 4
        '抖音' = 5
        '快手' = 6
        '网易CC' = 7
        'Twitch' = 8
        'Soop' = 9
        'YY' = 10
    }[$Label]
    if (-not $targetIndex) { throw "No platform tab index is registered for '$Label'." }

    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $name = "home-platform-tab-$attempt"
        Save-UiDump $name
        $xmlText = Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw -Encoding UTF8
        if (Test-UiSemanticEnabled -Xml $xmlText -Semantic $Label) {
            if (Test-UiSemanticSelected -Xml $xmlText -Semantic $Label) { return }
            Invoke-Ui -Action TapSemantic -Value $Label -Xml $xmlText
            Start-Sleep -Milliseconds 900
            continue
        }
        if ($attempt -eq 4) { break }

        [xml]$document = $xmlText
        $visibleTabs = @(
            $document.SelectNodes('//node') | ForEach-Object {
                $semantic = if (-not [string]::IsNullOrWhiteSpace($_.GetAttribute('content-desc'))) {
                    $_.GetAttribute('content-desc')
                } else {
                    $_.GetAttribute('text')
                }
                if (
                    $_.GetAttribute('enabled') -eq 'true' -and
                    $_.GetAttribute('clickable') -eq 'true' -and
                    $semantic -match '^(.+?)[\r\n]+第\s*(\d+)\s*个标签，共\s*(\d+)\s*个$' -and
                    [int]([regex]::Match($semantic, '共\s*(\d+)\s*个').Groups[1].Value) -ge 9 -and
                    $_.GetAttribute('bounds') -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'
                ) {
                    $ordinal = [int]([regex]::Match($semantic, '第\s*(\d+)\s*个标签').Groups[1].Value)
                    $null = $_.GetAttribute('bounds') -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'
                    [pscustomobject]@{
                        Index = $ordinal
                        Left = [int]$Matches[1]
                        Top = [int]$Matches[2]
                        Right = [int]$Matches[3]
                        Bottom = [int]$Matches[4]
                        Selected = $_.GetAttribute('selected') -eq 'true'
                    }
                }
            }
        )
        if ($visibleTabs.Count -eq 0) {
            throw "No visible platform tabs were available while locating '$Label'."
        }
        $left = ($visibleTabs | Measure-Object Left -Minimum).Minimum
        $right = ($visibleTabs | Measure-Object Right -Maximum).Maximum
        $top = ($visibleTabs | Measure-Object Top -Minimum).Minimum
        $bottom = ($visibleTabs | Measure-Object Bottom -Maximum).Maximum
        $minIndex = ($visibleTabs | Measure-Object Index -Minimum).Minimum
        $maxIndex = ($visibleTabs | Measure-Object Index -Maximum).Maximum
        $y = [math]::Round(($top + $bottom) / 2)
        $selectedIndex = @($visibleTabs | Where-Object Selected | Select-Object -ExpandProperty Index -First 1)
        if ($selectedIndex.Count -eq 1 -and $selectedIndex[0] -ne $targetIndex) {
            # Change the TabBarView itself rather than only scrolling the tab
            # header. Flutter recentres a selected tab after app resume; a
            # shared-device foreground switch can therefore undo header-only
            # scrolling. The selected page index survives that interruption.
            $distance = [math]::Abs($targetIndex - $selectedIndex[0])
            $swipeCount = [math]::Min(4, $distance)
            $screenSize = (Invoke-Adb -AdbArguments @('shell', 'wm', 'size')) -join "`n"
            if ($screenSize -notmatch '(\d+)x(\d+)') { throw "Could not parse device size: $screenSize" }
            $screenWidth = [int]$Matches[1]
            $screenHeight = [int]$Matches[2]
            $pageY = [math]::Round($screenHeight * 0.5)
            if ($targetIndex -gt $selectedIndex[0]) {
                $pageX1 = [math]::Round($screenWidth * 0.84)
                $pageX2 = [math]::Round($screenWidth * 0.16)
            } else {
                $pageX1 = [math]::Round($screenWidth * 0.16)
                $pageX2 = [math]::Round($screenWidth * 0.84)
            }
            for ($swipe = 0; $swipe -lt $swipeCount; $swipe++) {
                Invoke-Adb -AdbArguments @(
                    'shell', 'input', 'swipe', $pageX1, $pageY, $pageX2, $pageY, '220'
                ) | Out-Null
                Start-Sleep -Milliseconds 420
            }
            Start-Sleep -Milliseconds 500
            continue
        }
        $averageWidth = [math]::Round((($visibleTabs | ForEach-Object { $_.Right - $_.Left } | Measure-Object -Average).Average))
        if ($targetIndex -gt $maxIndex) {
            $distance = $targetIndex - $maxIndex
            $swipeCount = [math]::Max(1, [math]::Min(4, [math]::Ceiling($distance / 2)))
            $delta = [math]::Max(260, [math]::Min(640, [math]::Round($averageWidth * 2.4)))
            $x1 = $right - 24
            $x2 = $x1 - $delta
        } elseif ($targetIndex -lt $minIndex) {
            $distance = $minIndex - $targetIndex
            $swipeCount = [math]::Max(1, [math]::Min(4, [math]::Ceiling($distance / 2)))
            $delta = [math]::Max(260, [math]::Min(640, [math]::Round($averageWidth * 2.4)))
            $x1 = $left + 24
            $x2 = $x1 + $delta
        } else {
            throw "Platform tab '$Label' is absent inside the visible platform index range $minIndex-$maxIndex."
        }
        # Issue a short bounded batch instead of dumping after every small
        # scroll. This reaches far-right tabs before another shared-device
        # client can steal the foreground and keeps the gesture away from the
        # system edge/navigation regions.
        for ($swipe = 0; $swipe -lt $swipeCount; $swipe++) {
            Invoke-Adb -AdbArguments @('shell', 'input', 'swipe', $x1, $y, $x2, $y, '240') | Out-Null
            Start-Sleep -Milliseconds 180
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Platform tab '$Label' did not become visible after bounded horizontal scrolling."
}

function Wait-UiSemanticEnabled {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Semantic,
        [int] $TimeoutSeconds = 20
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        Save-UiDump $Name
        $xml = Get-Content -LiteralPath (Join-Path $evidence "$Name.xml") -Raw -Encoding UTF8
        if (Test-UiSemanticEnabled -Xml $xml -Semantic $Semantic) {
            return [pscustomobject]@{ Xml = $xml; ElapsedMs = $timer.ElapsedMilliseconds }
        }
        Start-Sleep -Milliseconds 700
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Enabled UI semantic did not settle within $TimeoutSeconds seconds: $Semantic"
}

function Get-Foreground {
    $line = Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'activities') |
        Select-String 'topResumedActivity|mResumedActivity' |
        Select-Object -First 1
    if ($line) { return $line.Line.Trim() }
    ''
}

function Wake-AndDismissKeyguard {
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
    Start-Sleep -Milliseconds 250
    $policy = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'window', 'policy')) -join "`n"
    $locked = $policy -match '(?im)(?:mShowingLockscreen|mKeyguardShowing|isKeyguardShowing|keyguardShowing|mDreamingLockscreen|isStatusBarKeyguard)\s*=\s*true'
    if (-not $locked) { return }

    $size = (Invoke-Adb -AdbArguments @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected device size output: $size" }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    Invoke-Adb -AdbArguments @(
        'shell', 'input', 'swipe',
        [math]::Round($width * 0.5),
        [math]::Round($height * 0.84),
        [math]::Round($width * 0.5),
        [math]::Round($height * 0.24),
        '350'
    ) | Out-Null
    Start-Sleep -Milliseconds 350
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

function Initialize-UiProfile {
    if ($null -ne $script:uiProfileData) { return }
    $map = Get-Content -LiteralPath (Join-Path $repo 'tool\device_ui_map.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $size = (Invoke-Adb -AdbArguments @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected device size output: $size" }
    $script:uiWidth = [int]$Matches[1]
    $script:uiHeight = [int]$Matches[2]
    $orientation = if ($script:uiWidth -gt $script:uiHeight) { 'landscape' } else { 'portrait' }
    $profile = @($map.profiles.PSObject.Properties | Where-Object {
        $_.Value.width -eq $script:uiWidth -and
        $_.Value.height -eq $script:uiHeight -and
        $_.Value.orientation -eq $orientation
    } | Select-Object -First 1)
    if ($profile.Count -eq 0) {
        $profile = @($map.profiles.PSObject.Properties[$map.defaultProfile])
    }
    if ($profile.Count -ne 1 -or $profile[0].Value.orientation -ne $orientation) {
        throw "No $orientation UI profile is available for $($script:uiWidth)x$($script:uiHeight)."
    }
    $script:uiProfileData = $profile[0].Value
}

function Get-SemanticTapTarget {
    param(
        [Parameter(Mandatory = $true)][string] $Semantic,
        [string] $Xml
    )
    if ([string]::IsNullOrWhiteSpace($Xml)) {
        $name = 'ui-semantic-' + ([Guid]::NewGuid().ToString('N'))
        Save-UiDump $name
        [xml]$document = Get-Content -LiteralPath (Join-Path $evidence "$name.xml") -Raw -Encoding UTF8
    } else {
        [xml]$document = $Xml
    }
    $matches = @($document.SelectNodes('//node') | ForEach-Object {
        $description = $_.GetAttribute('content-desc')
        $text = $_.GetAttribute('text')
        if (-not (
            $description -eq $Semantic -or $text -eq $Semantic -or
            $description -like "$Semantic`n*" -or $text -like "$Semantic`n*"
        )) { return }
        $bounds = $_.GetAttribute('bounds')
        if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { return }
        $left = [int]$Matches[1]
        $top = [int]$Matches[2]
        $right = [int]$Matches[3]
        $bottom = [int]$Matches[4]
        [pscustomobject]@{
            X = [math]::Floor(($left + $right) / 2)
            Y = [math]::Floor(($top + $bottom) / 2)
            Clickable = $_.GetAttribute('clickable') -eq 'true'
            Area = [math]::Max(0, ($right - $left) * ($bottom - $top))
        }
    } | Sort-Object @{ Expression = { -not $_.Clickable } }, Area)
    if ($matches.Count -eq 0) { throw "Semantic target '$Semantic' is not visible." }
    $matches[0]
}

function Invoke-Ui {
    param(
        [ValidateSet('Tap', 'TapSemantic', 'Sequence')]
        [string] $Action,
        [string] $Value,
        [string] $Xml
    )
    Wake-AndDismissKeyguard
    Initialize-UiProfile
    if ($Action -eq 'TapSemantic') {
        $target = Get-SemanticTapTarget -Semantic $Value -Xml $Xml
        Write-Output ("tap semantic '{0}' ({1},{2})" -f $Value, $target.X, $target.Y)
        Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $target.X, $target.Y) | Out-Null
        return
    }
    if ($Action -eq 'Tap') {
        $property = $script:uiProfileData.points.PSObject.Properties[$Value]
        if (-not $property) { throw "Unknown UI point '$Value'." }
        $point = $property.Value
        $x = [math]::Round(([double]$point.x / [double]$script:uiProfileData.width) * $script:uiWidth)
        $y = [math]::Round(([double]$point.y / [double]$script:uiProfileData.height) * $script:uiHeight)
        Write-Output ("tap {0} ({1},{2}) [cached once]" -f $Value, $x, $y)
        Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
        return
    }
    throw "Unsupported in-process UI action: $Action"
}

function Get-PrivateRecordingFiles {
    $files = @(
        Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'find', '.', '-type', 'f') |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object {
                $_ -match '(?i)[\\/]RECORDS[\\/].+\.(?:mp4|ts|flv|mkv)$'
            }
    )
    @($files | Sort-Object -Unique)
}

function ConvertTo-PosixLiteral {
    param([Parameter(Mandatory = $true)][string] $Value)
    "'" + $Value.Replace("'", "'\''") + "'"
}

function Get-PrivateFileInfo {
    param([Parameter(Mandatory = $true)][string] $Path)
    $literalPath = ConvertTo-PosixLiteral $Path
    $bytes = (Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'stat', '-c', '%s', $literalPath)) -join ''
    $modified = (Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'stat', '-c', '%Y', $literalPath)) -join ''
    if ($bytes -notmatch '^\d+$' -or $modified -notmatch '^\d+$') {
        throw "Unexpected stat output for ${Path}: bytes=$bytes modified=$modified"
    }
    [pscustomobject]@{
        Path = $Path
        Bytes = [long]$bytes
        ModifiedEpoch = [long]$modified
    }
}

function Wait-RecordingFileGrowth {
    param(
        [Parameter(Mandatory = $true)][string[]] $BeforeFiles,
        [int] $TimeoutSeconds = 30
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $previousBytes = @{}
    do {
        $currentFiles = @(Get-PrivateRecordingFiles)
        foreach ($path in $currentFiles) {
            if ($path -in $BeforeFiles) { continue }
            $info = Get-PrivateFileInfo $path
            if ($previousBytes.ContainsKey($path)) {
                $earlierBytes = [long]$previousBytes[$path]
                if ($earlierBytes -gt 0 -and $info.Bytes -gt $earlierBytes) {
                    return [pscustomobject]@{
                        Path = $path
                        InitialBytes = $earlierBytes
                        FinalBytes = $info.Bytes
                        ElapsedMs = $timer.ElapsedMilliseconds
                    }
                }
            }
            $previousBytes[$path] = $info.Bytes
        }
        Start-Sleep -Seconds 2
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw 'The active recording file did not show positive byte growth.'
}

function Copy-PrivateFile {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )
    $sourceLiteral = ConvertTo-PosixLiteral $Source
    $stagingPath = "./cache/purelive-recording-smoke-$PID.mp4"
    $stagingLiteral = ConvertTo-PosixLiteral $stagingPath
    Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'mkdir', '-p', './cache') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'cp', '--', $sourceLiteral, $stagingLiteral) | Out-Null

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $adb
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @(
        '-s', $script:serial,
        'exec-out', 'run-as', $Package, 'cat', '--', $stagingPath
    )) {
        $startInfo.ArgumentList.Add([string]$argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $destinationStream = $null
    try {
        if (-not $process.Start()) { throw 'Failed to start adb exec-out.' }
        $destinationStream = [IO.File]::Create($Destination)
        $process.StandardOutput.BaseStream.CopyTo($destinationStream)
        $destinationStream.Flush()
        $destinationStream.Dispose()
        $destinationStream = $null
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "adb exec-out failed ($($process.ExitCode)): $errorText"
        }
    } finally {
        if ($destinationStream) { $destinationStream.Dispose() }
        $process.Dispose()
        try { Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'rm', '-f', $stagingLiteral) | Out-Null } catch {}
    }
}

Start-AdbServer
$deviceRows = & $adb devices -l
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = @(
        $deviceRows | ForEach-Object {
            if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] }
        }
    )
    $wireless = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($devices.Count -eq 1) { $script:serial = $devices[0] }
    elseif ($wireless.Count -eq 1) { $script:serial = $wireless[0] }
    else { throw 'Specify -Serial when a unique network ADB transport cannot be selected.' }
} else {
    $matched = @(
        $deviceRows | ForEach-Object {
            if ($_ -match '^(\S+)\s+device(?:\s|$)' -and $Matches[1] -eq $Serial) { $Matches[1] }
        }
    )
    if ($matched.Count -ne 1) { throw "Requested ADB serial '$Serial' is not online." }
    $script:serial = $Serial
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = [DateTime]::Now.ToString('o')
    serial = $script:serial
    package = $Package
    platform = $Platform
    platformLabel = $platformLabel
    requestedRecordSeconds = $RecordSeconds
    requestedScreenOffSeconds = $ScreenOffSeconds
    checks = [ordered]@{}
}
$monitorRemoved = $false
$recordingWallTimer = $null

try {
    $result.checks.deviceState = ((Invoke-Adb -AdbArguments @('get-state')) -join '').Trim()
    $runAsIdentity = (Invoke-Adb -AdbArguments @('shell', 'run-as', $Package, 'id')) -join "`n"
    Save-Text 'run-as.txt' $runAsIdentity
    $result.checks.runAsAvailable = $runAsIdentity -match 'uid=\d+'

    Wake-AndDismissKeyguard
    Save-Text 'keyguard-after-wake.txt' (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'window', 'policy'))
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Save-Text 'cold-start.txt' (
        Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/$Activity")
    )
    Start-Sleep -Seconds 7

    $beforeFiles = @(Get-PrivateRecordingFiles)
    Save-Text 'record-files-before.txt' $beforeFiles

    Select-UiSemanticTab -Label '热门' -EvidencePrefix 'home-mode-popular' | Out-Null
    Select-PlatformTab -Label $platformLabel
    $homeRoomXml = Wait-HomeRoomCard -TimeoutSeconds $PlatformLoadTimeoutSeconds
    $result.checks.platformRoomListReady = -not [string]::IsNullOrWhiteSpace($homeRoomXml)
    if (-not $result.checks.platformRoomListReady) {
        throw "The $Platform room list did not become ready within $PlatformLoadTimeoutSeconds seconds."
    }
    Invoke-Ui -Action Tap -Value 'home.first_left_room'
    Start-Sleep -Seconds 12
    $result.checks.roomForeground = Get-Foreground
    Save-UiDump 'room-before-record'
    Save-Screenshot 'room-before-record'
    $roomXml = Get-Content -LiteralPath (Join-Path $evidence 'room-before-record.xml') -Raw -Encoding UTF8
    $result.checks.roomUiAlive = $roomXml.Contains('弹幕列表') -and $roomXml.Contains('弹幕设置')
    if (-not $result.checks.roomUiAlive) { throw "A live $Platform room did not open." }
    $visibleDanmakuLines = @(
        Get-UiLabels -Xml $roomXml | Where-Object { $_ -match '^.{1,48}[:：]\s*.+$' }
    )
    Save-Text 'visible-danmaku-lines.txt' $visibleDanmakuLines
    $liveDanmakuLines = @(
        $visibleDanmakuLines | Where-Object { $_ -notmatch '^系统消息[:：]\s*' }
    )
    Save-Text 'live-danmaku-lines.txt' $liveDanmakuLines
    $result.checks.visibleDanmakuLineCount = $visibleDanmakuLines.Count
    $result.checks.liveDanmakuLineCount = $liveDanmakuLines.Count
    $result.checks.danmakuSupported = $danmakuSupported
    $result.checks.liveDanmakuVisible = $liveDanmakuLines.Count -gt 0
    # Busy rooms can push the one-time "connected" system row out of the
    # virtualized list before this snapshot. A real platform chat line is
    # stronger end-to-end proof that the socket joined and decoded correctly.
    $result.checks.danmakuConnectionReady =
        [bool]($visibleDanmakuLines | Where-Object { $_ -match '^系统消息[:：]\s*弹幕服务器连接正常$' }) -or
        [bool]$result.checks.liveDanmakuVisible

    # The quality/line row moves down for portrait live streams. Semantic taps
    # follow the actual control instead of reusing a coordinate learned from a
    # landscape room, which otherwise taps the video and enters portrait
    # fullscreen rather than opening the menu.
    $roomLabels = @(Get-UiLabels -Xml $roomXml)
    $currentQualityLabel = @(
        $roomLabels | Where-Object {
            $_ -match '^(?i:(?:.*(?:原画|蓝光|超清|高清|标清|流畅|省流|自动).*)|(?:\d{3,4}p(?:\d{2,3})?(?:\s*\([^)]*\)|（[^）]*）)?)|(?:source|origin|uhd|fhd|hd|sd|ld|high|medium|low))$'
        }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($currentQualityLabel)) {
        Invoke-Ui -Action Tap -Value 'live.quality'
    } else {
        Invoke-Ui -Action TapSemantic -Value $currentQualityLabel
    }
    $qualityState = Wait-UiPattern `
        -Name 'quality-before-record' `
        -Pattern '关闭菜单' `
        -TimeoutSeconds 12
    Save-Screenshot 'quality-before-record'
    $qualityOptions = @(
        Get-UiLabels -Xml $qualityState.Xml | Where-Object {
            # Platform labels are not consistently prefix-based. Twitch, for
            # example, exposes `1080P60（原画）`, while Chinese providers use
            # values such as `原画2K60` or `蓝光10M`. Match the quality token
            # anywhere, or a complete resolution/FPS label, without treating
            # unrelated room text as a quality option.
            $_ -match '^(?i:(?:.*(?:原画|蓝光|超清|高清|标清|流畅|省流|自动).*)|(?:\d{3,4}p(?:\d{2,3})?(?:\s*\([^)]*\)|（[^）]*）)?)|(?:source|origin|uhd|fhd|hd|sd|ld|high|medium|low))$'
        }
    )
    $audioOnlyQualityLabels = @(
        Get-UiLabels -Xml $qualityState.Xml | Where-Object { $_ -match '^(?i:ao|audio|audio[_ -]?only)$' }
    )
    $result.checks.qualityOptions = $qualityOptions
    $result.checks.qualitySheetVisible = $qualityOptions.Count -gt 0
    $result.checks.audioOnlyQualityLabels = $audioOnlyQualityLabels
    $result.checks.audioOnlyQualityAbsent = $audioOnlyQualityLabels.Count -eq 0
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', '4') | Out-Null
    Wait-UiPattern -Name 'room-after-quality-check' -Pattern '弹幕列表' -TimeoutSeconds 12 | Out-Null

    $currentLineLabel = @(
        $roomLabels | Where-Object { $_ -match '^(?:线路\s*\d+|主线路|备用线路)$' }
    ) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($currentLineLabel)) {
        Invoke-Ui -Action Tap -Value 'live.line'
    } else {
        Invoke-Ui -Action TapSemantic -Value $currentLineLabel
    }
    $lineState = Wait-UiPattern `
        -Name 'line-before-record' `
        -Pattern '关闭菜单' `
        -TimeoutSeconds 12
    Save-Screenshot 'line-before-record'
    $lineOptions = @(
        Get-UiLabels -Xml $lineState.Xml | Where-Object {
            $_ -match '^(?:线路\s*\d+|主线路|备用线路|播放线路.*)$'
        }
    )
    $result.checks.lineOptions = $lineOptions
    $result.checks.lineSheetVisible = $lineOptions.Count -gt 0
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', '4') | Out-Null
    Wait-UiPattern -Name 'room-after-line-check' -Pattern '弹幕列表' -TimeoutSeconds 12 | Out-Null

    Invoke-Ui -Action Tap -Value 'live.record'
    $preflightDialog = Wait-UiPattern `
        -Name 'record-dialog-preflight' `
        -Pattern '立即启动录制|停止录制|取消监控' `
        -TimeoutSeconds 10
    if (Test-UiSemanticEnabled -Xml $preflightDialog.Xml -Semantic '停止录制') {
        Invoke-Ui -Action TapSemantic -Value '停止录制' -Xml $preflightDialog.Xml
        $preflightDialog = Wait-UiSemanticEnabled `
            -Name 'record-dialog-after-preflight-stop' `
            -Semantic '取消监控' `
            -TimeoutSeconds 60
    }
    if (Test-UiSemanticEnabled -Xml $preflightDialog.Xml -Semantic '取消监控') {
        Invoke-Ui -Action TapSemantic -Value '取消监控' -Xml $preflightDialog.Xml
        Wait-UiPattern -Name 'room-after-preflight-cleanup' -Pattern '弹幕列表' -TimeoutSeconds 12 | Out-Null
        Start-Sleep -Seconds 2
        Invoke-Ui -Action Tap -Value 'live.record'
        $preflightDialog = Wait-UiSemanticEnabled `
            -Name 'record-dialog-before-start' `
            -Semantic '立即启动录制' `
            -TimeoutSeconds 10
    }
    if (-not (Test-UiSemanticEnabled -Xml $preflightDialog.Xml -Semantic '立即启动录制')) {
        throw 'The record action did not reach the one-shot start state.'
    }
    Invoke-Ui -Action TapSemantic -Value '立即启动录制' -Xml $preflightDialog.Xml
    $runningState = Wait-UiPattern -Name 'room-recording' -Pattern '录制中' -TimeoutSeconds 30
    $recordingWallTimer = [Diagnostics.Stopwatch]::StartNew()
    $result.checks.recordStartMs = $runningState.ElapsedMs
    Save-Screenshot 'room-recording'

    $growth = $null
    if ($ScreenOffSeconds -gt 0) {
        # Prove recorder continuity while the panel and keyguard are off. This
        # is deliberately stronger than checking a notification or process:
        # the same private TS must continue growing during the dark interval.
        $growth = Wait-RecordingFileGrowth -BeforeFiles $beforeFiles -TimeoutSeconds 30
        $screenOffStart = Get-PrivateFileInfo $growth.Path
        Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_SLEEP') | Out-Null
        Start-Sleep -Milliseconds 750
        $screenOffPower = (Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'power')) -join "`n"
        Save-Text 'power-during-screen-off.txt' $screenOffPower
        # Always-on-display devices report Dozing rather than Asleep while the
        # interactive panel is dark and locked. Both states satisfy this gate;
        # Awake does not.
        $result.checks.screenOffConfirmed =
            $screenOffPower -match '(?im)mWakefulness\s*=\s*(?:Asleep|Dozing)|mInteractive\s*=\s*false|Display Power:\s*state=OFF'
        Start-Sleep -Seconds $ScreenOffSeconds
        $screenOffEnd = Get-PrivateFileInfo $growth.Path
        $result.checks.screenOffRecordingPath = $growth.Path
        $result.checks.screenOffInitialBytes = $screenOffStart.Bytes
        $result.checks.screenOffFinalBytes = $screenOffEnd.Bytes
        $result.checks.screenOffGrowthBytes = $screenOffEnd.Bytes - $screenOffStart.Bytes
        $result.checks.screenOffRecordingContinued = $screenOffEnd.Bytes -gt $screenOffStart.Bytes
        $result.checks.processAliveDuringScreenOff =
            -not [string]::IsNullOrWhiteSpace(((Invoke-Adb -AdbArguments @('shell', 'pidof', $Package)) -join '').Trim())
        Save-Text 'services-during-screen-off.txt' (
            Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'activity', 'services', $Package)
        )
        Wake-AndDismissKeyguard
        Start-Sleep -Seconds 2
        $result.checks.roomForegroundAfterScreenOff = Get-Foreground
        Wait-UiPattern -Name 'room-after-screen-off' -Pattern '弹幕列表' -TimeoutSeconds 15 | Out-Null
    } else {
        # File growth is the machine-readable running-recorder gate. Check it
        # while the room stays foregrounded so slow network ADB/UIAutomator
        # calls do not silently turn a 20-second smoke into a multi-minute
        # recording before the stop action is even attempted.
        $growth = Wait-RecordingFileGrowth -BeforeFiles $beforeFiles -TimeoutSeconds 30
    }
    # The shell uiautomator command hard-codes a one-second quiet window. A
    # recorder page that legitimately publishes time/size every second may
    # never become idle, so use two real private-file samples for the running
    # gate. The stopped recording-center state is captured below without
    # extending the live recording by another navigation round trip.
    $result.checks.runningFileGrowthObserved = $growth.FinalBytes -gt $growth.InitialBytes
    $result.checks.runningFilePath = $growth.Path
    $result.checks.runningFileInitialBytes = $growth.InitialBytes
    $result.checks.runningFileFinalBytes = $growth.FinalBytes
    $result.checks.runningFileGrowthMs = $growth.ElapsedMs

    $remainingSeconds = [math]::Max(
        0,
        [math]::Ceiling($RecordSeconds - $recordingWallTimer.Elapsed.TotalSeconds)
    )
    if ($remainingSeconds -gt 0) { Start-Sleep -Seconds $remainingSeconds }

    Invoke-Ui -Action Tap -Value 'live.record'
    $stopDialog = Wait-UiSemanticEnabled -Name 'record-dialog-before-stop' -Semantic '停止录制' -TimeoutSeconds 10
    Invoke-Ui -Action TapSemantic -Value '停止录制' -Xml $stopDialog.Xml
    $recordingWallTimer.Stop()
    $result.checks.recordingWallSeconds = [math]::Round($recordingWallTimer.Elapsed.TotalSeconds, 3)
    $stoppedHeader = Wait-UiPattern -Name 'room-record-stopped' -Pattern '已监控|录制任务' -TimeoutSeconds 60
    $result.checks.stopFinalizeMs = $stoppedHeader.ElapsedMs
    Save-Screenshot 'room-record-stopped'

    Invoke-Ui -Action Tap -Value 'live.record'
    $afterStopDialog = Wait-UiSemanticEnabled -Name 'record-dialog-after-stop' -Semantic '进入录制中心' -TimeoutSeconds 10
    Invoke-Ui -Action TapSemantic -Value '进入录制中心' -Xml $afterStopDialog.Xml
    $finalCenter = Wait-UiPattern -Name 'record-center-stopped' -Pattern '已停止' -TimeoutSeconds 20
    Save-Screenshot 'record-center-stopped'
    $recordCenterScreenshot = Join-Path $evidence 'record-center-stopped.png'
    $result.checks.recordingCenterScreenshotCaptured =
        (Test-Path -LiteralPath $recordCenterScreenshot -PathType Leaf) -and
        (Get-Item -LiteralPath $recordCenterScreenshot).Length -gt 0
    $result.checks.stoppedStatusVisible = $finalCenter.Xml.Contains('已停止')
    [xml]$finalCenterDocument = $finalCenter.Xml
    $currentStoppedCards = @(
        $finalCenterDocument.SelectNodes('//node') | ForEach-Object {
            $_.GetAttribute('content-desc')
        } | Where-Object {
            $_ -like "已停止`n*" -and
            $_ -match '(?m)^\d{2}:\d{2}:\d{2}$' -and
            $_ -match '(?m)^\d+(?:\.\d+)?\s+(?:KB|MB|GB)$'
        }
    )
    # The app keeps active status groups first and sorts each group newest
    # first. Scope the failure check to the just-finished card; historical
    # failures elsewhere in the visible list are valid persisted evidence and
    # must not invalidate a successful new recording.
    $currentStoppedCard = $currentStoppedCards | Select-Object -First 1
    $result.checks.currentStoppedCardVisible = -not [string]::IsNullOrWhiteSpace($currentStoppedCard)
    $result.checks.failureAbsent =
        $result.checks.currentStoppedCardVisible -and
        $currentStoppedCard -notmatch '录制失败|最近失败|输入的直播流地址格式有误'

    $afterFiles = @(Get-PrivateRecordingFiles)
    Save-Text 'record-files-after.txt' $afterFiles
    $newFinalFiles = @(
        $afterFiles | Where-Object {
            $_ -notin $beforeFiles -and $_ -match '(?i)\.mp4$'
        }
    )
    $newFileInfo = @($newFinalFiles | ForEach-Object { Get-PrivateFileInfo $_ })
    $newest = $newFileInfo | Sort-Object ModifiedEpoch -Descending | Select-Object -First 1
    if (-not $newest) { throw 'The stopped recording did not create a new MP4 file.' }
    $result.checks.recordingPath = $newest.Path
    $result.checks.recordingBytes = $newest.Bytes
    $result.checks.recordingFileNonEmpty = $newest.Bytes -gt 100000

    $localRecording = Join-Path $evidence 'recording.mp4'
    Copy-PrivateFile -Source $newest.Path -Destination $localRecording
    $localHash = (Get-FileHash -LiteralPath $localRecording -Algorithm SHA256).Hash
    $result.checks.recordingSha256 = $localHash

    $ffprobe = Get-Command ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ffprobe) { throw 'ffprobe.exe is required for the Android recording smoke.' }
    $probeOutput = & $ffprobe.Source -v error -show_format -show_streams -of json $localRecording 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed:`n$($probeOutput -join "`n")" }
    $probeText = $probeOutput -join "`n"
    Save-Text 'recording-ffprobe.json' $probeText
    $probe = $probeText | ConvertFrom-Json
    $durationSeconds = [double]::Parse(
        [string]$probe.format.duration,
        [Globalization.CultureInfo]::InvariantCulture
    )
    $result.checks.mediaDurationSeconds = $durationSeconds
    $recordingWallSeconds = [double]$result.checks.recordingWallSeconds
    # HLS startup includes stream resolution, manifest selection, demux probing
    # and the interval until two growing-file samples are observed. Do not
    # require the final media to cover time before media output existed. Keep a
    # five-second sampling/finalization tolerance after subtracting the
    # measured, bounded startup interval.
    $startupSeconds = [double]$result.checks.runningFileGrowthMs / 1000.0
    $result.checks.recordingStartupSeconds = [math]::Round($startupSeconds, 3)
    $minimumMediaSeconds = [math]::Max(8, $recordingWallSeconds - $startupSeconds - 5)
    $result.checks.mediaDurationPlausible =
        $durationSeconds -ge $minimumMediaSeconds -and
        $durationSeconds -le ($recordingWallSeconds + 12)
    $result.checks.hasVideoStream = @($probe.streams | Where-Object codec_type -eq 'video').Count -gt 0
    $result.checks.hasAudioStream = @($probe.streams | Where-Object codec_type -eq 'audio').Count -gt 0

    # Remove only the scheduler entry created by this smoke; retain the MP4 as
    # evidence. This prevents the next device turn from inheriting a monitor.
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', '4') | Out-Null
    Wait-UiPattern -Name 'room-before-monitor-cleanup' -Pattern '弹幕列表' -TimeoutSeconds 15 | Out-Null
    Invoke-Ui -Action Tap -Value 'live.record'
    $cleanupDialog = Wait-UiSemanticEnabled -Name 'record-dialog-cleanup' -Semantic '取消监控' -TimeoutSeconds 10
    Invoke-Ui -Action TapSemantic -Value '取消监控' -Xml $cleanupDialog.Xml
    $cleanupState = Wait-UiPattern -Name 'room-after-monitor-cleanup' -Pattern '录制' -TimeoutSeconds 10
    $monitorRemoved = -not ($cleanupState.Xml -match '已监控|录制中')
    $result.checks.monitorRemoved = $monitorRemoved

    $appPid = ((Invoke-Adb -AdbArguments @('shell', 'pidof', $Package)) -join '').Trim().Split(' ')[0]
    if ($appPid -match '^\d+$') {
        Save-Text 'logcat-tail.txt' (
            Invoke-Adb -AdbArguments @('logcat', '-d', '-v', 'threadtime', "--pid=$appPid", '-t', '3000')
        )
    } else {
        Save-Text 'logcat-tail.txt' ''
    }
    $logText = Get-Content -LiteralPath (Join-Path $evidence 'logcat-tail.txt') -Raw -Encoding UTF8
    $result.checks.noFatal = -not ($logText -match 'FATAL EXCEPTION|ANR in com\.mystyle\.purelive')
} finally {
    $result.checks.foregroundInterferenceCount = $script:foregroundInterferenceCount
    $result.checks.foregroundRecoveryCount = $script:foregroundRecoveryCount
    try {
        $logPath = Join-Path $evidence 'logcat-tail.txt'
        if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
            $activePid = ((Invoke-Adb -AdbArguments @('shell', 'pidof', $Package)) -join '').Trim().Split(' ')[0]
            if ($activePid -match '^\d+$') {
                Save-Text 'logcat-tail.txt' (
                    Invoke-Adb -AdbArguments @('logcat', '-d', '-v', 'threadtime', "--pid=$activePid", '-t', '3000')
                )
            }
        }
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $finalLogText = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            $result.checks.noFatal = -not ($finalLogText -match 'FATAL EXCEPTION|ANR in com\.mystyle\.purelive')
        }
    } catch {
        $result.checks.noFatal = $false
    }
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    Start-Sleep -Seconds 2
    $processAfterStop = & $adb -s $script:serial shell pidof $Package 2>&1
    $processAfterStopExitCode = $LASTEXITCODE
    Save-Text 'process-after-stop.txt' @(
        "exitCode=$processAfterStopExitCode"
        $processAfterStop
    )
    $result.checks.processGoneAfterStop =
        $processAfterStopExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($processAfterStop -join ''))
    try {
        $powerAfterStop = Invoke-Adb -AdbArguments @('shell', 'dumpsys', 'power')
        Save-Text 'wake-locks-after-stop.txt' $powerAfterStop
        # dumpsys power also contains historical wake-lock events. Restrict the
        # assertion to the current "Wake Locks" section so an earlier ACQ/REL
        # event for Pure Live does not turn a clean shutdown into a false fail.
        $powerText = $powerAfterStop -join "`n"
        $activeWakeLockMatch = [regex]::Match(
            $powerText,
            '(?ms)^Wake Locks:\s*size=\d+\s*\r?\n.*?(?=^Suspend Blockers:)'
        )
        $activeWakeLockText = if ($activeWakeLockMatch.Success) {
            $activeWakeLockMatch.Value.TrimEnd()
        } else {
            ''
        }
        Save-Text 'active-wake-locks-after-stop.txt' $activeWakeLockText
        $result.checks.activeWakeLockSectionParsed = $activeWakeLockMatch.Success
        $result.checks.wakeLockGoneAfterStop =
            $activeWakeLockMatch.Success -and
            -not ($activeWakeLockText -match [regex]::Escape($Package))
    } catch {
        $result.checks.activeWakeLockSectionParsed = $false
        $result.checks.wakeLockGoneAfterStop = $false
    }
    $result.completedAt = [DateTime]::Now.ToString('o')
    $result.monitorRemoved = $monitorRemoved
    $result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
}

$assertions = [ordered]@{
    deviceReady = ($result.checks.deviceState -eq 'device')
    runAsAvailable = [bool]$result.checks.runAsAvailable
    roomForeground = ($result.checks.roomForeground -match $Package)
    platformRoomListReady = [bool]$result.checks.platformRoomListReady
    roomUiAlive = [bool]$result.checks.roomUiAlive
    danmakuConnectionReady = (-not [bool]$result.checks.danmakuSupported) -or [bool]$result.checks.danmakuConnectionReady
    qualitySheetVisible = [bool]$result.checks.qualitySheetVisible
    audioOnlyQualityAbsent = [bool]$result.checks.audioOnlyQualityAbsent
    lineSheetVisible = [bool]$result.checks.lineSheetVisible
    recordingCenterScreenshotCaptured = [bool]$result.checks.recordingCenterScreenshotCaptured
    runningFileGrowthObserved = [bool]$result.checks.runningFileGrowthObserved
    screenOffConfirmed = ($ScreenOffSeconds -eq 0 -or [bool]$result.checks.screenOffConfirmed)
    screenOffRecordingContinued = ($ScreenOffSeconds -eq 0 -or [bool]$result.checks.screenOffRecordingContinued)
    processAliveDuringScreenOff = ($ScreenOffSeconds -eq 0 -or [bool]$result.checks.processAliveDuringScreenOff)
    roomRestoredAfterScreenOff = (
        $ScreenOffSeconds -eq 0 -or
        ([string]$result.checks.roomForegroundAfterScreenOff -match $Package)
    )
    stoppedStatusVisible = [bool]$result.checks.stoppedStatusVisible
    currentStoppedCardVisible = [bool]$result.checks.currentStoppedCardVisible
    failureAbsent = [bool]$result.checks.failureAbsent
    recordingFileNonEmpty = [bool]$result.checks.recordingFileNonEmpty
    mediaDurationPlausible = [bool]$result.checks.mediaDurationPlausible
    hasVideoStream = [bool]$result.checks.hasVideoStream
    hasAudioStream = [bool]$result.checks.hasAudioStream
    monitorRemoved = [bool]$result.checks.monitorRemoved
    noFatal = [bool]$result.checks.noFatal
    processGoneAfterStop = [bool]$result.checks.processGoneAfterStop
    activeWakeLockSectionParsed = [bool]$result.checks.activeWakeLockSectionParsed
    wakeLockGoneAfterStop = [bool]$result.checks.wakeLockGoneAfterStop
}
if ($RequireLiveDanmaku -and $danmakuSupported) {
    # A real chat line is a useful end-to-end signal only when the selected
    # room is known to be active. Quiet rooms must not turn an otherwise valid
    # protocol/recording smoke into a deterministic false failure.
    $assertions.liveDanmakuVisible = [bool]$result.checks.liveDanmakuVisible
}
$result.assertions = $assertions
$result | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $evidence 'summary.json') -Encoding utf8
$failed = @($assertions.GetEnumerator() | Where-Object { -not [bool]$_.Value })
if ($failed.Count -gt 0) {
    throw "Android recording smoke assertions failed: $((@($failed | ForEach-Object Key)) -join ', '). See $evidence\summary.json"
}

Write-Output (Join-Path $evidence 'summary.json')
