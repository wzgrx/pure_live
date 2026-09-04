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
    Join-Path $repo ("local-artifacts\diagnostics\android-danmaku-filter-settings-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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
    $result
}

$deviceRows = & $adb devices -l
if (-not $Serial) {
    $devices = @($deviceRows | ForEach-Object { if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] } })
    $network = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($network.Count -eq 1) { $Serial = $network[0] }
    elseif ($devices.Count -eq 1) { $Serial = $devices[0] }
    else { throw "Specify -Serial; devices=$($devices.Count), network=$($network.Count)." }
}

function Ensure-Awake {
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

function Save-UiDump {
    param([Parameter(Mandatory = $true)][string] $Name)
    Ensure-Awake
    $remote = "/sdcard/purelive-$PID-$Name.xml"
    $local = Join-Path $evidence "$Name.xml"
    try {
        Invoke-Adb -AdbArguments @('shell', 'timeout', '12', 'uiautomator', 'dump', '--compressed', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, $local) | Out-Null
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

function Find-UiNode {
    param([Parameter(Mandatory = $true)][xml] $Document, [Parameter(Mandatory = $true)][string] $Text)
    @($Document.SelectNodes('//node') | Where-Object {
        $label = "{0}`n{1}" -f ([string]$_.text), ([string]$_.'content-desc')
        $label.Contains($Text)
    }) | Sort-Object {
        if ([string]$_.clickable -eq 'true') { 0 } else { 1 }
    } | Select-Object -First 1
}

function Get-SwitchNodes {
    param([Parameter(Mandatory = $true)][xml] $Document)
    @($Document.SelectNodes('//node') | Where-Object {
        [string]$_.checkable -eq 'true' -and [string]$_.bounds -match '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'
    }) | Sort-Object {
        if ([string]$_.bounds -match '^\[(\d+),(\d+)\]') { [int]$Matches[2] } else { [int]::MaxValue }
    }
}

function Tap-UiNode {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "Unexpected UI bounds: $bounds" }
    $x = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
    $y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
}

function Tap-SwitchNode {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "Unexpected switch bounds: $bounds" }
    # Flutter merges the row label and control into one accessibility node, so
    # its semantic centre lies over the text rather than the visual switch.
    # Tap inside the trailing control while still deriving the coordinate from
    # the current semantic bounds and viewport.
    $x = [math]::Max([int]$Matches[1] + 1, [int]$Matches[3] - 64)
    $y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
}

function Tap-Text {
    param([Parameter(Mandatory = $true)][string] $Text, [Parameter(Mandatory = $true)][string] $EvidenceName)
    $document = Save-UiDump $EvidenceName
    $node = Find-UiNode -Document $document -Text $Text
    if (-not $node) { throw "UI text not found: $Text" }
    Tap-UiNode $node
    Start-Sleep -Milliseconds 900
}

function Dismiss-DebugCompatibilityDialog {
    $document = Save-UiDump 'debug-compatibility'
    $button = Find-UiNode -Document $document -Text '确定'
    if ($button) {
        Tap-UiNode $button
        Start-Sleep -Milliseconds 700
    }
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    apk = $apk
    checks = [ordered]@{}
}
$failure = $null
try {
    $install = Invoke-Adb -AdbArguments @('install', '-r', '-t', $apk)
    $result.checks.install = ($install -join "`n").Trim()
    Ensure-Awake
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
    Dismiss-DebugCompatibilityDialog

    & (Join-Path $repo 'tool\android_ui.ps1') -Sequence enter_first_bilibili_room -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Opening a live room failed.' }
    Start-Sleep -Seconds 10
    Tap-Text -Text '屏蔽管理' -EvidenceName 'live-room'

    $page = Save-UiDump 'filter-settings-initial'
    $xml = $page.OuterXml
    $result.checks.platformSectionVisible = $xml.Contains('平台弹幕过滤')
    $result.checks.douyuFilterVisible = $xml.Contains('过滤斗鱼疑似自动弹幕')
    $result.checks.douyuFilterDescriptionVisible = $xml.Contains('关闭后显示平台收到的全部聊天')
    $result.checks.similaritySectionVisible = $xml.Contains('相似弹幕过滤')
    Save-Screenshot 'filter-settings-initial'
    if (-not $result.checks.platformSectionVisible -or
        -not $result.checks.douyuFilterVisible -or
        -not $result.checks.douyuFilterDescriptionVisible -or
        -not $result.checks.similaritySectionVisible) {
        throw 'The platform filter controls are incomplete.'
    }

    $switches = Get-SwitchNodes $page
    if ($switches.Count -lt 2) { throw "Expected at least two filter switches, found $($switches.Count)." }
    $platformSwitch = $switches[0]
    $initialChecked = [string]$platformSwitch.checked -eq 'true'
    $initialSimilarityChecked = [string]$switches[1].checked -eq 'true'
    $result.checks.initialPlatformFilterEnabled = $initialChecked
    $result.checks.initialSimilarityFilterEnabled = $initialSimilarityChecked
    Tap-SwitchNode $platformSwitch
    Start-Sleep -Milliseconds 700

    $changedPage = Save-UiDump 'filter-settings-toggled'
    $changedSwitches = Get-SwitchNodes $changedPage
    if ($changedSwitches.Count -lt 2) { throw 'Filter switches disappeared after changing the platform setting.' }
    $changedChecked = [string]$changedSwitches[0].checked -eq 'true'
    $result.checks.platformFilterChangedImmediately = $changedChecked -ne $initialChecked
    $result.checks.similarityFilterUnaffected =
        ([string]$changedSwitches[1].checked -eq 'true') -eq $initialSimilarityChecked
    Save-Screenshot 'filter-settings-toggled'
    if (-not $result.checks.platformFilterChangedImmediately) { throw 'The platform filter switch did not change immediately.' }
    if (-not $result.checks.similarityFilterUnaffected) { throw 'Changing the platform filter also changed the similarity filter.' }

    Tap-SwitchNode $changedSwitches[0]
    Start-Sleep -Milliseconds 700
    $restoredPage = Save-UiDump 'filter-settings-restored'
    $restoredSwitches = Get-SwitchNodes $restoredPage
    $restoredChecked = $restoredSwitches.Count -ge 2 -and ([string]$restoredSwitches[0].checked -eq 'true')
    $result.checks.platformFilterRestored = $restoredChecked -eq $initialChecked
    if (-not $result.checks.platformFilterRestored) { throw 'The original platform filter setting was not restored.' }

    $result.checks.passed = $true
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
    $result.checks.passed = $false
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $summary = Join-Path $evidence 'summary.json'
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $summary -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
