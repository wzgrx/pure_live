[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Serial,
    [Parameter(Mandatory = $true)]
    [string] $ApkPath,
    [Parameter(Mandatory = $true)]
    [string] $ExpectedApkSha256,
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
    Join-Path $repo ("local-artifacts\diagnostics\android-room-tag-assignment-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$adb = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
) | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ -PathType Leaf }
    else { [bool] (Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'ADB executable was not found.' }

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $output = & $adb -s $Serial @AdbArguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return @($output) }
        $text = $output -join "`n"
        # These diagnostics are emitted before a command reaches the device.
        # Keep retries narrower than generic connection failures so an input or
        # install that may already have executed is never replayed blindly.
        $transportDidNotRun = $text -match 'daemon still not running|cannot connect to daemon|daemon not running|device offline'
        if (-not $transportDidNotRun -or $attempt -eq 3) {
            throw "adb failed ($exitCode): $($AdbArguments -join ' ')`n$text"
        }
        Start-Sleep -Milliseconds (700 * $attempt)
    }
}

function Get-Identity {
    $output = (Invoke-Adb @('shell', 'getprop ro.product.model; getprop ro.product.device; su -c id')) -join "`n"
    if ($output -notmatch "(?m)^$([regex]::Escape($ExpectedModel))\s*$" -or
        $output -notmatch "(?m)^$([regex]::Escape($ExpectedDevice))\s*$" -or
        $output -notmatch 'uid=0\(root\)') {
        throw "Unexpected target identity:`n$output"
    }
    [ordered]@{ model = $ExpectedModel; device = $ExpectedDevice; root = $true; raw = $output }
}

function Get-TopPackage {
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    if ($dump -match '(?m)^\s*topResumedActivity=.*?\s([A-Za-z0-9._]+)\/') { return $Matches[1] }
    ''
}

function Get-TopActivityComponent {
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    if ($dump -match '(?m)^\s*topResumedActivity=.*?\s([A-Za-z0-9._]+\/[A-Za-z0-9._$]+)') {
        return $Matches[1]
    }
    ''
}

function Assert-TargetForeground {
    $top = Get-TopPackage
    if ($top -ne $Package) { throw "Expected $Package to be top resumed; actual='$top'." }
}

function Get-DeviceFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)
    $line = (Invoke-Adb @('shell', "su -c `"sha256sum '$Path'`"")) -join ''
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Unexpected sha256sum output for ${Path}: $line" }
    $Matches[1].ToUpperInvariant()
}

function Get-PackageState {
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'package', $Package)) -join "`n"
    $pathLine = Invoke-Adb @('shell', 'pm', 'path', $Package) | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
    if (-not $pathLine -or $dump -notmatch '(?m)^\s*versionName=([^\s]+)') { throw 'Installed package state is incomplete.' }
    $versionName = $Matches[1]
    if ($dump -notmatch '(?m)^\s*versionCode=(\d+)') { throw 'Installed versionCode is missing.' }
    $versionCode = [int64] $Matches[1]
    if ($dump -notmatch '(?m)^\s*firstInstallTime=(.+)$') { throw 'Installed firstInstallTime is missing.' }
    [ordered]@{
        versionName = $versionName
        versionCode = $versionCode
        firstInstallTime = $Matches[1].Trim()
        apkPath = ([string] $pathLine).Substring(8).Trim()
    }
}

function Get-Bounds {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string] $Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "Unexpected UI bounds: $bounds" }
    [pscustomobject]@{
        Left = [int] $Matches[1]
        Top = [int] $Matches[2]
        Right = [int] $Matches[3]
        Bottom = [int] $Matches[4]
        X = [math]::Floor(([int] $Matches[1] + [int] $Matches[3]) / 2)
        Y = [math]::Floor(([int] $Matches[2] + [int] $Matches[4]) / 2)
        Width = [int] $Matches[3] - [int] $Matches[1]
        Height = [int] $Matches[4] - [int] $Matches[2]
    }
}

function Get-NodeLabel {
    param([Parameter(Mandatory = $true)] $Node)
    (([string] $Node.text) + "`n" + ([string] $Node.'content-desc')).Trim()
}

function Save-UiState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [switch] $NoScreenshot,
        [switch] $AllowSystemSurface
    )
    if (-not $AllowSystemSurface.IsPresent) { Assert-TargetForeground }
    $xmlPath = Join-Path $evidence "$Name.xml"
    $pngPath = Join-Path $evidence "$Name.png"
    $captured = $false
    for ($attempt = 1; $attempt -le 4 -and -not $captured; $attempt++) {
        try {
            $raw = (Invoke-Adb @('exec-out', 'uiautomator', 'dump', '--compressed', '/dev/tty')) -join "`n"
            $match = [regex]::Match($raw, '(?s)<\?xml\b.*?</hierarchy>')
            if (-not $match.Success) { throw 'uiautomator returned no hierarchy.' }
            [IO.File]::WriteAllText($xmlPath, $match.Value, [Text.UTF8Encoding]::new($false))
            $captured = $true
        } catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds (300 + 250 * $attempt)
        }
    }
    if (-not $NoScreenshot.IsPresent) {
        $remotePng = "/sdcard/purelive-room-tag-$PID-$Name.png"
        try {
            Invoke-Adb @('shell', 'screencap', '-p', $remotePng) | Out-Null
            Invoke-Adb @('pull', $remotePng, $pngPath) | Out-Null
        } finally {
            try { Invoke-Adb @('shell', 'rm', '-f', $remotePng) | Out-Null } catch {}
        }
    }
    [xml] [IO.File]::ReadAllText($xmlPath, [Text.Encoding]::UTF8)
}

function Wait-SystemShareSurface {
    param([int] $TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $component = Get-TopActivityComponent
        $isSystemChooser = $component -match '^(android|com\.android\.intentresolver)/' -and
            $component -match '(?i)(Chooser|Resolver|Intent)'
        if ($isSystemChooser) {
            $document = Save-UiState "share-surface-$attempt" -AllowSystemSurface
            $observedComponent = Get-TopActivityComponent
            $rootNode = $document.SelectSingleNode('/hierarchy/node')
            $surfacePackage = if ($rootNode) { [string] $rootNode.package } else { '' }
            $headlineNode = $document.SelectSingleNode("//node[contains(@resource-id, 'headline')]")
            $previewNode = $document.SelectSingleNode("//node[contains(@resource-id, 'content_preview_text')]")
            $previewText = if ($previewNode) { [string] $previewNode.text } else { '' }
            if ($observedComponent -eq $component -and
                $surfacePackage -match '^(android|com\.android\.intentresolver)$' -and
                $headlineNode -and $previewText.Length -ge 20) {
                return [pscustomobject]@{
                    component = $component
                    package = $surfacePackage
                    headline = [string] $headlineNode.text
                    previewLength = $previewText.Length
                    document = $document
                }
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for the system share surface; top activity='$(Get-TopActivityComponent)'."
}

function Wait-TargetForeground {
    param([int] $TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if ((Get-TopPackage) -eq $Package) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Timed out returning to $Package; top package='$(Get-TopPackage)'."
}

function Find-LabeledNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [switch] $Clickable,
        [switch] $Exact,
        [switch] $BottomMost
    )
    $matches = @($Document.SelectNodes('//node') | Where-Object {
        $node = $_
        $label = Get-NodeLabel $node
        $labelMatches = @($Candidates | Where-Object {
            if ($Exact.IsPresent) { $label -eq $_ } else { $label.Contains($_) }
        }).Count -gt 0
        $labelMatches -and (-not $Clickable.IsPresent -or [string] $node.clickable -eq 'true')
    })
    if ($BottomMost.IsPresent) {
        $matches | Sort-Object { (Get-Bounds $_).Top } -Descending | Select-Object -First 1
    } else {
        $matches | Sort-Object {
            $label = Get-NodeLabel $_
            if (@($Candidates | Where-Object { $label -eq $_ }).Count -gt 0) { 0 } else { 1 }
        }, { (Get-Bounds $_).Top } | Select-Object -First 1
    }
}

function Invoke-TapNode {
    param([Parameter(Mandatory = $true)] $Node)
    Assert-TargetForeground
    $b = Get-Bounds $Node
    Invoke-Adb @('shell', 'input', 'tap', $b.X, $b.Y) | Out-Null
}

function Set-EditorText {
    param([Parameter(Mandatory = $true)] $Node, [Parameter(Mandatory = $true)][string] $Text)
    Invoke-TapNode $Node
    Start-Sleep -Milliseconds 1200
    Invoke-Adb @('shell', 'input', 'keycombination', 'KEYCODE_CTRL_LEFT', 'KEYCODE_A') | Out-Null
    Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_DEL') | Out-Null
    Invoke-Adb @('shell', 'input', 'text', $Text) | Out-Null
    Start-Sleep -Milliseconds 900
}

function Invoke-TapLabel {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [switch] $Exact,
        [switch] $BottomMost
    )
    $node = Find-LabeledNode -Document $Document -Candidates $Candidates -Clickable -Exact:$Exact -BottomMost:$BottomMost
    if (-not $node) { throw "Clickable label not found: $($Candidates -join ' / ')." }
    Invoke-TapNode $node
    Start-Sleep -Milliseconds 700
}

function Test-ContainsAny {
    param([Parameter(Mandatory = $true)][string] $Text, [Parameter(Mandatory = $true)][string[]] $Candidates)
    foreach ($candidate in $Candidates) { if ($Text.Contains($candidate)) { return $true } }
    $false
}

function Wait-UiContains {
    param(
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $Prefix,
        [int] $TimeoutSeconds = 15
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiState "$Prefix-$attempt" -NoScreenshot
        if (Test-ContainsAny $document.OuterXml $Candidates) { return $document }
        Start-Sleep -Milliseconds 700
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for UI: $($Candidates -join ' / ')."
}

function Wait-UiExcludes {
    param(
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [Parameter(Mandatory = $true)][string] $Prefix,
        [int] $TimeoutSeconds = 15
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiState "$Prefix-$attempt" -NoScreenshot
        if (-not (Test-ContainsAny $document.OuterXml $Candidates)) { return $document }
        Start-Sleep -Milliseconds 700
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for UI to close: $($Candidates -join ' / ')."
}

function Assert-VisibleBounds {
    param([Parameter(Mandatory = $true)] $Node, [int] $Width, [int] $Height, [string] $Name)
    $b = Get-Bounds $Node
    if ($b.Left -lt 0 -or $b.Top -lt 0 -or $b.Right -gt $Width -or $b.Bottom -gt $Height -or $b.Width -lt 40 -or $b.Height -lt 40) {
        throw "${Name} has clipped or undersized bounds: $([string] $Node.bounds)."
    }
    [ordered]@{ label = Get-NodeLabel $Node; bounds = [string] $Node.bounds; width = $b.Width; height = $b.Height }
}

function Open-PopularBilibili {
    $start = (Invoke-Adb @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity")) -join "`n"
    $result.launchOutput = $start
    Start-Sleep -Seconds 3
    $initial = Save-UiState 'launch-initial'
    $compat = Find-LabeledNode -Document $initial -Candidates @('确定', 'OK') -Clickable -Exact
    if ($compat) {
        Invoke-TapNode $compat
        Start-Sleep -Milliseconds 700
        $initial = Save-UiState 'launch-after-compatibility'
    }
    $popular = Find-LabeledNode -Document $initial -Candidates @('热门', 'Popular') -Clickable
    if (-not $popular) { throw 'The Popular navigation action is absent.' }
    Invoke-TapNode $popular
    Start-Sleep -Seconds 2
    $popularUi = Save-UiState 'popular-before-platform'
    $bilibili = Find-LabeledNode -Document $popularUi -Candidates @('哔哩哔哩', 'Bilibili') -Clickable
    if (-not $bilibili) { throw 'The Bilibili platform action is absent.' }
    Invoke-TapNode $bilibili
    Start-Sleep -Seconds 8
    Save-UiState 'popular-bilibili-ready'
}

function Get-RoomTarget {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $nodes = @($Document.SelectNodes('//node') | Where-Object {
        if ([string] $_.'long-clickable' -ne 'true') { return $false }
        $b = Get-Bounds $_
        $b.Top -ge 430 -and $b.Bottom -le 2400 -and $b.Width -ge 350 -and $b.Height -ge 250
    } | Sort-Object { (Get-Bounds $_).Top }, { (Get-Bounds $_).Left })
    if ($nodes.Count -gt 0) {
        $b = Get-Bounds $nodes[0]
        return [ordered]@{ x = $b.X; y = $b.Y; bounds = [string] $nodes[0].bounds; semantic = Get-NodeLabel $nodes[0]; source = 'long-clickable-semantics' }
    }
    $size = (Invoke-Adb @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected display size: $size" }
    [ordered]@{
        x = [math]::Round([int] $Matches[1] * 0.264)
        y = [math]::Round([int] $Matches[2] * 0.284)
        bounds = $null
        semantic = $null
        source = 'validated-k90-first-card-ratio'
    }
}

function Open-RoomDialog {
    param([Parameter(Mandatory = $true)] $RoomTarget, [Parameter(Mandatory = $true)][string] $Phase)
    Assert-TargetForeground
    Invoke-Adb @('shell', 'input', 'swipe', $RoomTarget.x, $RoomTarget.y, $RoomTarget.x, $RoomTarget.y, '900') | Out-Null
    Start-Sleep -Milliseconds 900
    $dialog = Save-UiState $Phase
    $required = [ordered]@{
        share = [ordered]@{ labels = @('分享', 'Share'); bottomMost = $false }
        tags = [ordered]@{ labels = @('设置房间标签', 'Set Room Tags'); bottomMost = $false }
        follow = [ordered]@{ labels = @('关注', 'Follow', '取消关注', 'Unfollow'); bottomMost = $true }
        close = [ordered]@{ labels = @('关闭', 'Close'); bottomMost = $true }
    }
    $controls = [ordered]@{}
    foreach ($entry in $required.GetEnumerator()) {
        $node = Find-LabeledNode -Document $dialog -Candidates $entry.Value.labels -Clickable -BottomMost:$entry.Value.bottomMost
        if (-not $node) { throw "${Phase}: missing $($entry.Key) control." }
        $controls[$entry.Key] = Assert-VisibleBounds $node $result.display.width $result.display.height "$Phase/$($entry.Key)"
    }
    [pscustomobject]@{ document = $dialog; controls = $controls }
}

function Get-RoomFollowControl {
    param([Parameter(Mandatory = $true)][xml] $Document)
    $unfollow = Find-LabeledNode -Document $Document -Candidates @('取消关注', 'Unfollow') -Clickable -Exact -BottomMost
    if ($unfollow) {
        return [pscustomobject]@{ node = $unfollow; isFavorite = $true; label = Get-NodeLabel $unfollow }
    }
    $follow = Find-LabeledNode -Document $Document -Candidates @('关注', 'Follow') -Clickable -Exact -BottomMost
    if ($follow) {
        return [pscustomobject]@{ node = $follow; isFavorite = $false; label = Get-NodeLabel $follow }
    }
    throw 'Room dialog exposes neither an exact Follow nor Unfollow action.'
}

function Wait-RoomDialogClosed {
    param([Parameter(Mandatory = $true)][string] $Prefix, [int] $TimeoutSeconds = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiState "$Prefix-$attempt" -NoScreenshot
        $close = Find-LabeledNode -Document $document -Candidates @('关闭', 'Close') -Clickable -Exact -BottomMost
        if (-not $close) { return $document }
        Start-Sleep -Milliseconds 700
    } while ((Get-Date) -lt $deadline)
    throw 'Room details remained open after the follow action completed.'
}

function Invoke-UnfollowContract {
    param(
        [Parameter(Mandatory = $true)] $Dialog,
        [Parameter(Mandatory = $true)] $RoomTarget,
        [Parameter(Mandatory = $true)][string] $Phase
    )
    $control = Get-RoomFollowControl $Dialog.document
    if (-not $control.isFavorite) { throw "${Phase}: expected an Unfollow action before opening confirmation." }
    Invoke-TapNode $control.node
    $promptLabels = @('确定要取消关注', 'Are you sure to unfollow')
    Wait-UiContains $promptLabels "$Phase-prompt-ready" | Out-Null
    $prompt = Save-UiState "$Phase-prompt"
    $message = Find-LabeledNode -Document $prompt -Candidates $promptLabels
    $cancel = Find-LabeledNode -Document $prompt -Candidates @('取消', 'Cancel') -Clickable -Exact -BottomMost
    $confirm = Find-LabeledNode -Document $prompt -Candidates @('确认', 'Confirm') -Clickable -Exact -BottomMost
    if (-not $message -or -not $cancel -or -not $confirm) { throw "${Phase}: unfollow confirmation is incomplete." }
    $promptEvidence = [ordered]@{
        message = [ordered]@{ label = Get-NodeLabel $message; bounds = [string] $message.bounds }
        cancel = Assert-VisibleBounds $cancel $result.display.width $result.display.height "$Phase/cancel"
        confirm = Assert-VisibleBounds $confirm $result.display.width $result.display.height "$Phase/confirm"
    }

    Invoke-TapNode $cancel
    $afterCancel = Wait-UiExcludes $promptLabels "$Phase-after-cancel"
    $afterCancelControl = Get-RoomFollowControl $afterCancel
    if (-not $afterCancelControl.isFavorite) { throw "${Phase}: cancelling unfollow changed the favorite state." }

    Invoke-TapNode $afterCancelControl.node
    $confirmPrompt = Wait-UiContains $promptLabels "$Phase-confirm-ready"
    Invoke-TapLabel $confirmPrompt @('确认', 'Confirm') -Exact -BottomMost
    Wait-RoomDialogClosed "$Phase-after-confirm" | Out-Null
    $reopened = Open-RoomDialog $RoomTarget "$Phase-reopened"
    $afterConfirmControl = Get-RoomFollowControl $reopened.document
    if ($afterConfirmControl.isFavorite) { throw "${Phase}: confirming unfollow did not change the room action to Follow." }

    [pscustomobject]@{
        dialog = $reopened
        evidence = [ordered]@{
            prompt = $promptEvidence
            cancelPreservedFavorite = $true
            confirmClosedOwningDialog = $true
            reopenedLabel = $afterConfirmControl.label
        }
    }
}

$settingsPath = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$remoteBackup = "/data/local/tmp/purelive-room-tag-$PID-original.hive"
$remoteRestore = "/data/local/tmp/purelive-room-tag-$PID-restore.hive"
$localBackup = Join-Path $evidence 'app_settings.original.hive'
$fixtureTag = Get-Date -Format 'yyMMddHHmmssff'
$fixtureDescription = '31415926'
$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    identity = $null
    display = [ordered]@{}
    apk = [ordered]@{ path = $apk; expectedSha256 = $ExpectedApkSha256.ToUpperInvariant() }
    settingsFile = [ordered]@{}
    roomTarget = $null
    fixtureTag = $fixtureTag
    states = [ordered]@{}
    checks = [ordered]@{}
}
$failure = $null
$settingsBackedUp = $false
$ownerUid = $null
$ownerGid = $null
$mode = $null

try {
    $result.identity = Get-Identity
    $size = (Invoke-Adb @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected display size: $size" }
    $result.display.width = [int] $Matches[1]
    $result.display.height = [int] $Matches[2]

    $localHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToUpperInvariant()
    $result.apk.actualSha256 = $localHash
    if ($localHash -ne $result.apk.expectedSha256) { throw 'Candidate APK hash differs from the expected clean-build hash.' }

    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    $stat = (Invoke-Adb @('shell', "su -c `"stat -c '%u:%g:%a' '$settingsPath'`"")) -join ''
    if ($stat -notmatch '^(\d+):(\d+):(\d+)$') { throw "Unexpected settings metadata: $stat" }
    $ownerUid = $Matches[1]
    $ownerGid = $Matches[2]
    $mode = $Matches[3]
    $result.settingsFile.metadata = $stat
    $result.settingsFile.selinuxBefore = (Invoke-Adb @('shell', "su -c `"ls -Z '$settingsPath'`"")) -join "`n"
    $result.settingsFile.originalSha256 = Get-DeviceFileHash $settingsPath
    Invoke-Adb @('shell', "su -c `"cp '$settingsPath' '$remoteBackup' && chown shell:shell '$remoteBackup' && chmod 600 '$remoteBackup'`"") | Out-Null
    Invoke-Adb @('pull', $remoteBackup, $localBackup) | Out-Null
    if ((Get-FileHash -LiteralPath $localBackup -Algorithm SHA256).Hash.ToUpperInvariant() -ne $result.settingsFile.originalSha256) {
        throw 'Local settings backup differs from the device source.'
    }
    $settingsBackedUp = $true

    $result.apk.installedBefore = Get-PackageState
    $install = (Invoke-Adb @('install', '-r', '-t', $apk)) -join "`n"
    if ($install -notmatch '(?m)^Success\s*$') { throw "Unexpected install result: $install" }
    $result.apk.installOutput = $install.Trim()
    $result.apk.installedAfter = Get-PackageState
    if ($result.apk.installedAfter.firstInstallTime -ne $result.apk.installedBefore.firstInstallTime) {
        throw 'Overlay install changed firstInstallTime.'
    }
    $result.apk.deviceSha256 = Get-DeviceFileHash ([string] $result.apk.installedAfter.apkPath)
    if ($result.apk.deviceSha256 -ne $localHash) { throw 'Installed base.apk differs from the selected candidate.' }
    $result.settingsFile.afterInstallSha256 = Get-DeviceFileHash $settingsPath
    if ($result.settingsFile.afterInstallSha256 -ne $result.settingsFile.originalSha256) {
        throw 'Overlay install changed settings before launch.'
    }
    $result.checks.overlayInstallPreservedData = $true
    $result.checks.installedApkMatchesCandidate = $true

    $ready = Open-PopularBilibili
    $roomTarget = Get-RoomTarget $ready
    $result.roomTarget = $roomTarget
    $firstDialog = Open-RoomDialog $roomTarget 'room-dialog-first'
    $result.states.firstDialogControls = $firstDialog.controls
    $result.checks.longPressDialogControlsReachable = $true

    $shareAction = Find-LabeledNode -Document $firstDialog.document -Candidates @('分享', 'Share') -Clickable -Exact
    if (-not $shareAction) { throw 'Room details expose no exact Share action.' }
    Invoke-TapNode $shareAction
    $shareSurface = Wait-SystemShareSurface
    $result.states.shareSurface = [ordered]@{
        component = $shareSurface.component
        package = $shareSurface.package
        headline = $shareSurface.headline
        previewLength = $shareSurface.previewLength
        hierarchyLength = $shareSurface.document.OuterXml.Length
    }
    $result.checks.shareActionOpenedSystemSurface = $true
    Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
    Wait-TargetForeground
    $firstDialog = Open-RoomDialog $roomTarget 'room-dialog-after-share'
    $result.states.afterShareDialogControls = $firstDialog.controls
    $result.checks.shareSurfaceReturnedToOwningApp = $true

    $currentDialog = $firstDialog
    $initialFollow = Get-RoomFollowControl $currentDialog.document
    $result.states.initialFollowAction = [ordered]@{
        label = $initialFollow.label
        isFavorite = $initialFollow.isFavorite
        bounds = [string] $initialFollow.node.bounds
    }
    if ($initialFollow.isFavorite) {
        $normalized = Invoke-UnfollowContract $currentDialog $roomTarget 'normalize-initial-favorite'
        $result.states.initialFavoriteNormalization = $normalized.evidence
        $currentDialog = $normalized.dialog
    }

    $followControl = Get-RoomFollowControl $currentDialog.document
    if ($followControl.isFavorite) { throw 'Expected an unfollowed room before the direct Follow action.' }
    Invoke-TapNode $followControl.node
    Wait-RoomDialogClosed 'direct-follow-closed' | Out-Null
    $currentDialog = Open-RoomDialog $roomTarget 'room-dialog-after-direct-follow'
    $followedControl = Get-RoomFollowControl $currentDialog.document
    if (-not $followedControl.isFavorite) { throw 'Direct Follow did not persist when the room dialog reopened.' }
    $result.states.directFollow = [ordered]@{
        initialLabel = $followControl.label
        reopenedLabel = $followedControl.label
    }
    $result.checks.followActionClosesOwningDialog = $true
    $result.checks.followStateRetainedOnReopen = $true

    $unfollowed = Invoke-UnfollowContract $currentDialog $roomTarget 'direct-unfollow'
    $result.states.directUnfollow = $unfollowed.evidence
    $result.checks.unfollowRequiresConfirmation = $true
    $result.checks.unfollowCancelPreservesFavorite = $true
    $result.checks.unfollowConfirmClosesOwningDialog = $true
    $currentDialog = $unfollowed.dialog

    $refollowControl = Get-RoomFollowControl $currentDialog.document
    if ($refollowControl.isFavorite) { throw 'Expected Follow after the direct unfollow contract.' }
    Invoke-TapNode $refollowControl.node
    Wait-RoomDialogClosed 'refollow-closed' | Out-Null
    $currentDialog = Open-RoomDialog $roomTarget 'room-dialog-after-refollow'
    if (-not (Get-RoomFollowControl $currentDialog.document).isFavorite) {
        throw 'Room did not return to a followed state before tag assignment.'
    }

    Invoke-TapLabel $currentDialog.document @('设置房间标签', 'Set Room Tags')
    $afterTag = Save-UiState 'after-tag-action'
    if (-not (Test-ContainsAny $afterTag.OuterXml @('设置房间标签', 'Set Room Tags'))) {
        if (-not (Test-ContainsAny $afterTag.OuterXml @('是否关注', '关注主播', 'Would you like to follow'))) {
            throw 'Tag action reached neither the follow prompt nor tag selector.'
        }
        Invoke-TapLabel $afterTag @('关注', 'Follow') -Exact -BottomMost
        $afterTag = Wait-UiContains @('设置房间标签', 'Set Room Tags') 'tag-selector-after-follow'
        $result.states.followPromptHandled = $true
    } else {
        $result.states.followPromptHandled = $false
    }

    $selector = Save-UiState 'tag-selector-initial'
    foreach ($entry in @(
        @{ name = 'title'; labels = @('设置房间标签', 'Set Room Tags'); clickable = $false },
        @{ name = 'add'; labels = @('添加标签', 'Add Tag'); clickable = $true },
        @{ name = 'cancel'; labels = @('取消', 'Cancel'); clickable = $true },
        @{ name = 'confirm'; labels = @('确认', 'Confirm'); clickable = $true }
    )) {
        $node = Find-LabeledNode -Document $selector -Candidates $entry.labels -Clickable:$entry.clickable
        if (-not $node) { throw "Initial tag selector is missing $($entry.name)." }
        $result.states["selector_$($entry.name)"] = Assert-VisibleBounds $node $result.display.width $result.display.height "selector/$($entry.name)"
    }
    $result.checks.tagSelectorControlsReachable = $true

    Invoke-TapLabel $selector @('添加标签', 'Add Tag')
    $addForm = Save-UiState 'tag-add-form'
    $editors = @($addForm.SelectNodes('//node') | Where-Object { [string] $_.class -eq 'android.widget.EditText' } | Sort-Object { (Get-Bounds $_).Top })
    if ($editors.Count -ne 2) { throw "Tag add form exposed $($editors.Count) editor(s), expected 2." }
    $result.states.addFormEditors = @($editors | ForEach-Object { Assert-VisibleBounds $_ $result.display.width $result.display.height 'tag-add/editor' })
    Set-EditorText $editors[0] $fixtureTag
    $afterName = Save-UiState 'tag-add-after-name' -NoScreenshot
    $shiftedEditors = @($afterName.SelectNodes('//node') | Where-Object { [string] $_.class -eq 'android.widget.EditText' } | Sort-Object { (Get-Bounds $_).Top })
    if ($shiftedEditors.Count -ne 2) { throw "Keyboard-adjusted tag form exposed $($shiftedEditors.Count) editor(s), expected 2." }
    if ([string] $shiftedEditors[0].text -ne $fixtureTag) { throw "Tag name injection mismatch: '$([string] $shiftedEditors[0].text)'." }
    Set-EditorText $shiftedEditors[1] $fixtureDescription
    $filledForm = Save-UiState 'tag-add-form-filled'
    $filledEditors = @($filledForm.SelectNodes('//node') | Where-Object { [string] $_.class -eq 'android.widget.EditText' } | Sort-Object { (Get-Bounds $_).Top })
    if ($filledEditors.Count -ne 2 -or [string] $filledEditors[0].text -ne $fixtureTag -or [string] $filledEditors[1].text -ne $fixtureDescription) {
        throw 'Tag form did not retain the deterministic name and description input.'
    }
    Invoke-TapLabel $filledForm @('添加标签', 'Add Tag')

    $created = Wait-UiContains @($fixtureTag) 'tag-created'
    $createdNode = Find-LabeledNode -Document $created -Candidates @($fixtureTag) -Clickable
    if (-not $createdNode) { throw 'New fixture tag is absent from the selector.' }
    if ([string] $createdNode.selected -ne 'true') { throw 'New fixture tag was not auto-selected.' }
    $result.states.createdTag = [ordered]@{ label = Get-NodeLabel $createdNode; selected = [string] $createdNode.selected; bounds = [string] $createdNode.bounds }
    $result.checks.newTagAutoSelected = $true
    Invoke-TapLabel $created @('确认', 'Confirm') -Exact -BottomMost
    Start-Sleep -Seconds 1

    $secondDialog = Open-RoomDialog $roomTarget 'room-dialog-second'
    Invoke-TapLabel $secondDialog.document @('设置房间标签', 'Set Room Tags')
    $reopened = Wait-UiContains @($fixtureTag) 'tag-selector-reopened'
    $reopenedNode = Find-LabeledNode -Document $reopened -Candidates @($fixtureTag) -Clickable
    if (-not $reopenedNode -or [string] $reopenedNode.selected -ne 'true') { throw 'Reopened selector did not retain the assigned fixture tag.' }
    $result.states.reopenedTag = [ordered]@{ label = Get-NodeLabel $reopenedNode; selected = [string] $reopenedNode.selected; bounds = [string] $reopenedNode.bounds }
    $result.checks.assignmentRetainedOnReopen = $true
    Invoke-TapLabel $reopened @('取消', 'Cancel') -Exact -BottomMost

    $pidText = (Invoke-Adb @('shell', 'pidof', $Package)) -join ''
    if ($pidText -notmatch '^\d+$') { throw "Unexpected app PID: $pidText" }
    $result.pid = [int] $pidText
    $logcat = (Invoke-Adb @('shell', 'logcat', '--pid', $pidText, '-d', '-v', 'threadtime')) -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'app-logcat.txt'), $logcat, [Text.UTF8Encoding]::new($false))
    $fatalLines = @($logcat -split "`r?`n" | Where-Object { $_ -match 'FATAL EXCEPTION|ANR in|Fatal signal|SIGABRT' })
    $result.states.fatalLines = $fatalLines
    $result.checks.noFatalOrAnr = $fatalLines.Count -eq 0
    if (-not $result.checks.noFatalOrAnr) { throw 'App process log contains a fatal or ANR marker.' }
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
    try {
        $failureState = Save-UiState 'failure'
        $result.failureUi = $failureState.OuterXml
    } catch {}
} finally {
    try { Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    if ($settingsBackedUp) {
        try {
            Invoke-Adb @('push', $localBackup, $remoteRestore) | Out-Null
            Invoke-Adb @('shell', "su -c `"cat '$remoteRestore' > '$settingsPath' && chown ${ownerUid}:${ownerGid} '$settingsPath' && chmod '$mode' '$settingsPath' && restorecon '$settingsPath'`"") | Out-Null
            $result.settingsFile.restoredSha256 = Get-DeviceFileHash $settingsPath
            $result.settingsFile.selinuxAfter = (Invoke-Adb @('shell', "su -c `"ls -Z '$settingsPath'`"")) -join "`n"
            $result.checks.settingsFileRestoredExactly = $result.settingsFile.restoredSha256 -eq $result.settingsFile.originalSha256
            if (-not $result.checks.settingsFileRestoredExactly -and -not $failure) {
                $failure = [InvalidOperationException]::new('Original settings hash was not restored.')
            }
        } catch {
            $result.restoreError = $_.Exception.Message
            if (-not $failure) { $failure = $_ }
        }
    }
    try { Invoke-Adb @('shell', 'rm', '-f', $remoteBackup, $remoteRestore) | Out-Null } catch {}
    try { Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try { Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $pidOutput = @(& $adb -s $Serial shell pidof $Package 2>&1)
    $pidExitCode = $LASTEXITCODE
    $result.checks.appStopped = $pidExitCode -in @(0, 1) -and [string]::IsNullOrWhiteSpace(($pidOutput -join ''))
    if (-not $result.checks.appStopped -and -not $failure) {
        $failure = [InvalidOperationException]::new("Pure Live remained active after cleanup: $($pidOutput -join ' ')")
    }
    $result.checks.passed = $null -eq $failure
    $result.completedAt = (Get-Date).ToString('o')
    $result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
$global:LASTEXITCODE = 0
