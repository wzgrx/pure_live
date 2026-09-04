[CmdletBinding()]
param(
    [string] $ApkPath,
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $PlatformLabel = '虎牙',
    [string] $Package = 'com.mystyle.purelive',
    [string] $Activity = '.MainActivity'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-favorite-offline-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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

function Get-NodeLabel {
    param([Parameter(Mandatory = $true)] $Node)
    "{0}`n{1}" -f ([string]$Node.text), ([string]$Node.'content-desc')
}

function Find-UiNode {
    param([Parameter(Mandatory = $true)][xml] $Document, [Parameter(Mandatory = $true)][string] $Needle)
    @($Document.SelectNodes('//node') | Where-Object { (Get-NodeLabel $_).Contains($Needle) }) |
        Sort-Object { if ([string]$_.clickable -eq 'true') { 0 } else { 1 } } |
        Select-Object -First 1
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
    param([Parameter(Mandatory = $true)][string] $Text, [Parameter(Mandatory = $true)][string] $EvidenceName)
    $document = Save-UiDump $EvidenceName
    $node = Find-UiNode -Document $document -Needle $Text
    if (-not $node) { throw "UI text not found: $Text" }
    Tap-Node $node
    Start-Sleep -Seconds 2
}

function Is-SelectedNode {
    param([Parameter(Mandatory = $true)][xml] $Document, [Parameter(Mandatory = $true)][string] $Needle)
    @($Document.SelectNodes('//node') | Where-Object {
        (Get-NodeLabel $_).Contains($Needle) -and [string]$_.selected -eq 'true'
    }).Count -gt 0
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    platformLabel = $PlatformLabel
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
    Start-Sleep -Seconds 12

    $compatibility = Save-UiDump 'home-initial'
    $confirm = Find-UiNode -Document $compatibility -Needle '确定'
    if ($confirm) {
        Tap-Node $confirm
        Start-Sleep -Seconds 1
    }

    Tap-Text -Text '未开播' -EvidenceName 'home-before-offline'
    Tap-Text -Text $PlatformLabel -EvidenceName 'offline-before-platform'
    $page = Save-UiDump 'offline-platform'
    Save-Screenshot 'offline-platform'
    $labels = @($page.SelectNodes('//node') | ForEach-Object { Get-NodeLabel $_ }) -join "`n"

    $result.checks.offlineTabSelected = Is-SelectedNode -Document $page -Needle '未开播'
    $result.checks.platformSelected = Is-SelectedNode -Document $page -Needle $PlatformLabel
    $result.checks.emptyStateVisible = $labels.Contains('当前筛选暂无未开播直播')
    $count = $null
    if ($labels -match '关注数据仍在，共\s*(\d+)\s*个') { $count = [int]$Matches[1] }
    $result.checks.emptyStateReportedFollowCount = $count
    $result.checks.contradictoryEmptyCount = $result.checks.emptyStateVisible -and $null -ne $count -and $count -gt 0

    $logcat = (Invoke-Adb -AdbArguments @('shell', 'logcat', '-d', '-v', 'threadtime')) -join "`n"
    $logcat | Out-File -LiteralPath (Join-Path $evidence 'logcat.txt') -Encoding utf8
    $result.checks.noFatal = $logcat -notmatch 'FATAL EXCEPTION|AndroidRuntime: Process: com\.mystyle\.purelive|SIGABRT|Fatal signal'
    $result.checks.passed =
        $result.checks.offlineTabSelected -and
        $result.checks.platformSelected -and
        -not $result.checks.contradictoryEmptyCount -and
        $result.checks.noFatal
    if (-not $result.checks.passed) { throw 'Favorite offline bucket assertions failed.' }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
    $result.checks.passed = $false
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $summaryPath = Join-Path $evidence 'summary.json'
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $summaryPath -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
