[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Serial,
    [Parameter(Mandatory = $true)]
    [string] $ApkPath,
    [Parameter(Mandatory = $true)]
    [string] $ExpectedApkSha256,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Release')]
    [string] $BuildMode,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive',
    [string] $AppLabel = '纯粹直播',
    [string] $ExpectedModel = '25102RKBEC',
    [string] $ExpectedDevice = 'myron',
    [string] $DocumentsUiPackage = 'com.google.android.documentsui',
    [string] $DocumentsUiComponent = 'com.google.android.documentsui/com.android.documentsui.files.FilesActivity',
    [string] $ResolverPackage = 'com.android.intentresolver'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-documentsui-share-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null
$adb = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
) | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ -PathType Leaf }
    else { [bool] (Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb -or -not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'ADB executable was not found.' }

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $aset = & $adb -s $Serial @AdbArguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return @($aset) }
        $text = $aset -join "`n"
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

function Get-DeviceFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)
    $line = (Invoke-Adb @('shell', "su -c `"sha256sum '$Path'`"")) -join ''
    if ($line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Unexpected sha256sum output for ${Path}: $line" }
    $Matches[1].ToUpperInvariant()
}

function Get-PackageState {
    param([string] $TargetPackage = $Package)
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'package', $TargetPackage)) -join "`n"
    $pathLine = Invoke-Adb @('shell', 'pm', 'path', $TargetPackage) | Where-Object { $_ -like 'package:*' } | Select-Object -First 1
    if (-not $pathLine -or $dump -notmatch '(?m)^\s*versionName=([^\s]+)') { throw "Installed package state is incomplete: $TargetPackage" }
    $versionName = $Matches[1]
    if ($dump -notmatch '(?m)^\s*versionCode=(\d+)') { throw "Installed versionCode is missing: $TargetPackage" }
    $versionCode = [int64] $Matches[1]
    if ($dump -notmatch '(?m)^\s*firstInstallTime=(.+)$') { throw "Installed firstInstallTime is missing: $TargetPackage" }
    [ordered]@{
        package = $TargetPackage
        versionName = $versionName
        versionCode = $versionCode
        firstInstallTime = $Matches[1].Trim()
        apkPath = ([string] $pathLine).Substring(8).Trim()
    }
}

function Get-PackageUid {
    param([Parameter(Mandatory = $true)][string] $TargetPackage)
    $line = (Invoke-Adb @('shell', 'cmd', 'package', 'list', 'packages', '-U', $TargetPackage)) -join "`n"
    if ($line -notmatch "(?m)^package:$([regex]::Escape($TargetPackage))\s+uid:(\d+)\s*$") {
        throw "Package UID was not reported for $TargetPackage`: $line"
    }
    [int] $Matches[1]
}

function Get-TopPackage {
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    if ($dump -match '(?m)^\s*topResumedActivity=.*?\s([A-Za-z0-9._]+)\/') { return $Matches[1] }
    ''
}

function Wait-TopPackage {
    param(
        [Parameter(Mandatory = $true)][string] $ExpectedPackage,
        [int] $TimeoutSeconds = 20
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $top = Get-TopPackage
        if ($top -eq $ExpectedPackage) { return }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $ExpectedPackage; top package='$top'."
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
    foreach ($property in @('text', 'content-desc', 'hint')) {
        $value = [string] $Node.$property
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
    }
    ''
}

function Save-UiState {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $ExpectedTopPackage,
        [switch] $NoScreenshot
    )
    Wait-TopPackage $ExpectedTopPackage
    $xmlPath = Join-Path $evidence "$Name.xml"
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            $raw = (Invoke-Adb @('exec-out', 'uiautomator', 'dump', '/dev/tty')) -join "`n"
            $match = [regex]::Match($raw, '(?s)<\?xml.*</hierarchy>')
            if (-not $match.Success) { throw "UI hierarchy was not returned: $raw" }
            [IO.File]::WriteAllText($xmlPath, $match.Value, [Text.UTF8Encoding]::new($false))
            break
        } catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds (300 + 250 * $attempt)
        }
    }
    if (-not $NoScreenshot.IsPresent) {
        $remotePng = "/sdcard/purelive-documentsui-share-$PID-$Name.png"
        $pngPath = Join-Path $evidence "$Name.png"
        try {
            Invoke-Adb @('shell', 'screencap', '-p', $remotePng) | Out-Null
            Invoke-Adb @('pull', $remotePng, $pngPath) | Out-Null
        } finally {
            try { Invoke-Adb @('shell', 'rm', '-f', $remotePng) | Out-Null } catch {}
        }
    }
    [xml] [IO.File]::ReadAllText($xmlPath, [Text.Encoding]::UTF8)
}

function Find-LabeledNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string[]] $Candidates,
        [switch] $Exact,
        [switch] $Clickable
    )
    @($Document.SelectNodes('//node') | Where-Object {
        $node = $_
        $label = Get-NodeLabel $node
        $matched = @($Candidates | Where-Object { if ($Exact) { $label -eq $_ } else { $label.Contains($_) } }).Count -gt 0
        $matched -and (-not $Clickable -or [string] $node.clickable -eq 'true')
    } | Sort-Object { (Get-Bounds $_).Top } | Select-Object -First 1)
}

function Get-ClickableAncestor {
    param([Parameter(Mandatory = $true)] $Node)
    $current = $Node
    while ($current -and [string] $current.clickable -ne 'true') { $current = $current.ParentNode }
    if (-not $current) { throw "UI node has no clickable ancestor: $(Get-NodeLabel $Node)" }
    $current
}

function Invoke-TapNode {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [Parameter(Mandatory = $true)][string] $ExpectedTopPackage
    )
    Wait-TopPackage $ExpectedTopPackage
    $bounds = Get-Bounds (Get-ClickableAncestor $Node)
    Invoke-Adb @('shell', 'input', 'tap', $bounds.X, $bounds.Y) | Out-Null
}

function Invoke-LongPressNode {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [Parameter(Mandatory = $true)][string] $ExpectedTopPackage
    )
    Wait-TopPackage $ExpectedTopPackage
    $bounds = Get-Bounds (Get-ClickableAncestor $Node)
    Invoke-Adb @('shell', 'input', 'swipe', $bounds.X, $bounds.Y, $bounds.X, $bounds.Y, '900') | Out-Null
}

function Wait-SelectionCount {
    param(
        [Parameter(Mandatory = $true)][int] $Count,
        [Parameter(Mandatory = $true)][string] $Prefix,
        [int] $TimeoutSeconds = 8
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiState "$Prefix-$attempt" $DocumentsUiPackage -NoScreenshot
        $title = @($document.SelectNodes('//node') | Where-Object {
            [string] $_.'resource-id' -eq 'com.google.android.documentsui:id/action_bar_title'
        } | Select-Object -First 1)
        $label = if ($title) { Get-NodeLabel $title } else { '' }
        if ($label -match "(?:已选择\s*$Count\s*项|$Count\s+(?:items?\s+)?selected)") {
            return Save-UiState "$Prefix-ready" $DocumentsUiPackage
        }
        Start-Sleep -Milliseconds 450
    } while ((Get-Date) -lt $deadline)
    throw "DocumentsUI selection count did not become $Count; last label='$label'."
}

function Get-SharedStagingEntries {
    @(Invoke-Adb @(
        'shell',
        "su -c `"if [ -e '/data/user/0/$Package/cache/share_handler' ]; then find '/data/user/0/$Package/cache/share_handler' -mindepth 0 -print; fi`""
    ))
}

function Wait-SharedStagingEmpty {
    param([int] $TimeoutSeconds = 18)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $entries = @(Get-SharedStagingEntries)
        if ($entries.Count -eq 0) { return }
        Start-Sleep -Milliseconds 450
    } while ((Get-Date) -lt $deadline)
    throw "Shared-media staging entries remained: $($entries -join ', ')"
}

function Get-TreeManifest {
    param([Parameter(Mandatory = $true)][string] $Path)
    $metadata = @(Invoke-Adb @('shell', "su -c `"find '$Path' -exec stat -c '%F|%u|%g|%a|%s|%n' '{}' ';' | sort`""))
    $hashes = @(Invoke-Adb @('shell', "su -c `"find '$Path' -type f -exec sha256sum '{}' ';' | sort`""))
    [ordered]@{
        metadata = @($metadata | ForEach-Object { [string] $_ })
        hashes = @($hashes | ForEach-Object { [string] $_ })
    }
}

function Assert-TreeManifestEqual {
    param([Parameter(Mandatory = $true)] $Expected, [Parameter(Mandatory = $true)] $Actual, [string] $Phase)
    if (($Expected.metadata -join "`n") -ne ($Actual.metadata -join "`n") -or
        ($Expected.hashes -join "`n") -ne ($Actual.hashes -join "`n")) {
        throw "$Phase changed the preserved IPTV cache tree."
    }
}

function Copy-RootFileToHost {
    param(
        [Parameter(Mandatory = $true)][string] $DevicePath,
        [Parameter(Mandatory = $true)][string] $RemoteTemporary,
        [Parameter(Mandatory = $true)][string] $HostPath
    )
    Invoke-Adb @('shell', "su -c `"cp '$DevicePath' '$RemoteTemporary' && chown shell:shell '$RemoteTemporary' && chmod 600 '$RemoteTemporary'`"") | Out-Null
    Invoke-Adb @('pull', $RemoteTemporary, $HostPath) | Out-Null
}

function Get-ProcessLog {
    $pidText = (Invoke-Adb @('shell', 'pidof', '-s', $Package)) -join ''
    if ($pidText -notmatch '^\d+$') { return [ordered]@{ pid = $null; text = '' } }
    $text = (Invoke-Adb @('logcat', '--pid', $pidText, '-d', '-v', 'threadtime')) -join "`n"
    [ordered]@{ pid = [int] $pidText; text = $text }
}

function Test-ExternalUriGrant {
    param(
        [Parameter(Mandatory = $true)][string] $PermissionDump,
        [Parameter(Mandatory = $true)][string] $FileName
    )
    $pattern = "(?m)^\s*UriPermission\{[^\r\n]*content://com\.android\.externalstorage\.documents[^\r\n]*$([regex]::Escape($FileName))[^\r\n]*\}\r?\n\s*targetUserId=\d+\s+sourcePkg=com\.android\.externalstorage\s+targetPkg=$([regex]::Escape($Package))\s*$"
    $PermissionDump -match $pattern
}

$settingsPath = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$pureLiveRoot = "/data/user/0/$Package/app_flutter/PURE_LIVE"
$iptvCachePath = "$pureLiveRoot/IPTV_CACHE"
$databasePath = "$iptvCachePath/pure_live_tv/pure_live_tv.db"
$remoteSettingsBackup = "/data/local/tmp/purelive-documentsui-$PID-original.hive"
$remoteSettingsRestore = "/data/local/tmp/purelive-documentsui-$PID-restore.hive"
$remoteCacheBackup = "/data/local/tmp/purelive-documentsui-$PID-cache.tar"
$remoteCacheRestore = "/data/local/tmp/purelive-documentsui-$PID-cache-restore.tar"
$remoteDbSnapshot = "/data/local/tmp/purelive-documentsui-$PID.db"
$localSettingsBackup = Join-Path $evidence 'app_settings.original.hive'
$localCacheBackup = Join-Path $evidence 'iptv_cache.original.tar'
$localDbSnapshot = Join-Path $evidence 'iptv_after_documentsui_share.db'
$fixtureTag = Get-Date -Format 'yyMMddHHmmssff'
$directoryName = "PureLiveShareProbe-$fixtureTag"
$externalDirectory = "/sdcard/Download/$directoryName"
$directoryUri = "content://com.android.externalstorage.documents/document/primary%3ADownload%2F$directoryName"
$playlistBaseName = "documentsui-playlist-$fixtureTag"
$epgBaseName = "documentsui-epg-$fixtureTag"
$playlistFileName = "$playlistBaseName.m3u"
$epgFileName = "$epgBaseName.xml"
$externalPlaylist = "$externalDirectory/$playlistFileName"
$externalEpg = "$externalDirectory/$epgFileName"
$localPlaylist = Join-Path $evidence $playlistFileName
$localEpg = Join-Path $evidence $epgFileName
$playlistChannel = "DocumentsUI Playlist $fixtureTag"
$epgChannelId = "documentsui-$fixtureTag"
$epgChannel = "DocumentsUI EPG $fixtureTag"
$programme = "DocumentsUI Programme $fixtureTag"
[IO.File]::WriteAllText(
    $localPlaylist,
    "#EXTM3U`n#EXTINF:-1 tvg-id=`"$fixtureTag`" group-title=`"Fixture`",$playlistChannel`nhttps://example.invalid/$fixtureTag/documentsui.m3u8`n",
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $localEpg,
    "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<tv><channel id=`"$epgChannelId`"><display-name>$epgChannel</display-name></channel><programme channel=`"$epgChannelId`" start=`"20360101000000 +0000`" stop=`"20360101010000 +0000`"><title>$programme</title></programme></tv>`n",
    [Text.UTF8Encoding]::new($false)
)

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    evidenceDirectory = $evidence
    serial = $Serial
    package = $Package
    buildMode = $BuildMode
    identity = $null
    apk = [ordered]@{ path = $apk; expectedSha256 = $ExpectedApkSha256.ToUpperInvariant() }
    sender = [ordered]@{ package = $DocumentsUiPackage; component = $DocumentsUiComponent; resolverPackage = $ResolverPackage }
    fixture = [ordered]@{
        directory = $externalDirectory
        directoryUri = $directoryUri
        playlistFileName = $playlistFileName
        playlistChannel = $playlistChannel
        epgFileName = $epgFileName
        epgChannel = $epgChannel
        programme = $programme
    }
    preservedState = [ordered]@{}
    uiFlow = [ordered]@{}
    import = [ordered]@{}
    checks = [ordered]@{}
}
$failure = $null
$settingsBackedUp = $false
$cacheBackedUp = $false
$externalDirectoryCreated = $false
$settingsUid = $null
$settingsGid = $null
$settingsMode = $null

try {
    $result.identity = Get-Identity
    $localHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToUpperInvariant()
    $result.apk.actualSha256 = $localHash
    if ($localHash -ne $result.apk.expectedSha256) { throw 'Candidate APK hash differs from the expected clean-build hash.' }

    $result.sender.state = Get-PackageState $DocumentsUiPackage
    $result.sender.uid = Get-PackageUid $DocumentsUiPackage
    $result.sender.targetUid = Get-PackageUid $Package
    if ($result.sender.uid -eq $result.sender.targetUid) { throw 'DocumentsUI and Pure Live unexpectedly share one UID.' }
    $result.checks.senderUsesIndependentPackageAndUid = $true

    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
    $settingsStat = (Invoke-Adb @('shell', "su -c `"stat -c '%u:%g:%a' '$settingsPath'`"")) -join ''
    if ($settingsStat -notmatch '^(\d+):(\d+):(\d+)$') { throw "Unexpected settings metadata: $settingsStat" }
    $settingsUid = $Matches[1]
    $settingsGid = $Matches[2]
    $settingsMode = $Matches[3]
    $result.preservedState.settingsMetadata = $settingsStat
    $result.preservedState.settingsSelinuxBefore = (Invoke-Adb @('shell', "su -c `"ls -Zd '$settingsPath'`"")) -join "`n"
    $result.preservedState.settingsSha256Before = Get-DeviceFileHash $settingsPath
    Copy-RootFileToHost $settingsPath $remoteSettingsBackup $localSettingsBackup
    if ((Get-FileHash -LiteralPath $localSettingsBackup -Algorithm SHA256).Hash.ToUpperInvariant() -ne $result.preservedState.settingsSha256Before) {
        throw 'Local settings backup differs from the device source.'
    }
    $settingsBackedUp = $true

    $result.preservedState.iptvTreeBefore = Get-TreeManifest $iptvCachePath
    Invoke-Adb @('shell', "su -c `"tar -C '$pureLiveRoot' -cpf '$remoteCacheBackup' IPTV_CACHE && chown shell:shell '$remoteCacheBackup' && chmod 600 '$remoteCacheBackup'`"") | Out-Null
    Invoke-Adb @('pull', $remoteCacheBackup, $localCacheBackup) | Out-Null
    if ((Get-Item -LiteralPath $localCacheBackup).Length -lt 1024) { throw 'IPTV cache backup is unexpectedly small.' }
    $result.preservedState.iptvBackupSha256 = (Get-FileHash -LiteralPath $localCacheBackup -Algorithm SHA256).Hash.ToUpperInvariant()
    $cacheBackedUp = $true

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
    if ((Get-DeviceFileHash $settingsPath) -ne $result.preservedState.settingsSha256Before) {
        throw 'Overlay install changed settings before launch.'
    }
    Assert-TreeManifestEqual $result.preservedState.iptvTreeBefore (Get-TreeManifest $iptvCachePath) 'Overlay install'
    $packageDump = (Invoke-Adb @('shell', 'dumpsys', 'package', $Package)) -join "`n"
    $debugProbePattern = 'ShareIntentProbeReceiver|ShareIntentProbeProvider|RecorderLifecycleProbeReceiver'
    if ($packageDump -match $debugProbePattern) { throw "Release package exposed a debug-only probe component: $($Matches[0])" }
    $result.checks.overlayInstallPreservedData = $true
    $result.checks.installedApkMatchesCandidate = $true
    $result.checks.releaseDebugProbesExcluded = $true

    $preExisting = (Invoke-Adb @('shell', "if [ -e '$externalDirectory' ]; then echo exists; fi")) -join ''
    if ($preExisting.Trim()) { throw 'Unique external fixture directory already exists.' }
    Invoke-Adb @('shell', 'mkdir', $externalDirectory) | Out-Null
    $externalDirectoryCreated = $true
    Invoke-Adb @('push', $localPlaylist, $externalPlaylist) | Out-Null
    Invoke-Adb @('push', $localEpg, $externalEpg) | Out-Null
    $result.fixture.playlistSha256 = Get-DeviceFileHash $externalPlaylist
    $result.fixture.epgSha256 = Get-DeviceFileHash $externalEpg
    if ($result.fixture.playlistSha256 -ne (Get-FileHash -LiteralPath $localPlaylist -Algorithm SHA256).Hash.ToUpperInvariant() -or
        $result.fixture.epgSha256 -ne (Get-FileHash -LiteralPath $localEpg -Algorithm SHA256).Hash.ToUpperInvariant()) {
        throw 'External fixture hash differs after transfer.'
    }
    $result.checks.externalFixturesMatchHost = $true

    $logStartTime = ((Invoke-Adb @('shell', "date '+%m-%d %H:%M:%S.000'")) -join '').Trim()
    $result.uiFlow.logStartTime = $logStartTime
    $result.uiFlow.documentsUiLaunchOutput = (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW', '-d', $directoryUri, '-n', $DocumentsUiComponent
    )) -join "`n"
    Wait-TopPackage $DocumentsUiPackage
    $initial = Save-UiState '01-documentsui-directory' $DocumentsUiPackage
    $playlistNode = Find-LabeledNode $initial @($playlistFileName) -Exact
    $epgNode = Find-LabeledNode $initial @($epgFileName) -Exact
    if (-not $playlistNode -or -not $epgNode -or -not $initial.OuterXml.Contains($directoryName)) {
        throw 'DocumentsUI did not expose the expected external directory and both fixtures.'
    }
    $result.checks.documentsUiDisplayedBothFixtures = $true

    Invoke-LongPressNode $playlistNode $DocumentsUiPackage
    $selectedOne = Wait-SelectionCount 1 '02-documentsui-selected-one'
    $epgNode = Find-LabeledNode $selectedOne @($epgFileName) -Exact
    if (-not $epgNode) { throw 'XMLTV fixture disappeared after selecting the playlist.' }
    Invoke-TapNode $epgNode $DocumentsUiPackage
    $selectedTwo = Wait-SelectionCount 2 '03-documentsui-selected-two'
    $shareNode = @($selectedTwo.SelectNodes('//node') | Where-Object {
        [string] $_.'resource-id' -eq 'com.google.android.documentsui:id/action_menu_share' -and
        [string] $_.clickable -eq 'true' -and
        (Get-NodeLabel $_) -match '^(分享|Share)$'
    } | Select-Object -First 1)
    if (-not $shareNode) { throw 'DocumentsUI share action was not available after two-file selection.' }
    $result.uiFlow.shareAction = [ordered]@{ label = Get-NodeLabel $shareNode; bounds = [string] $shareNode.bounds }
    $result.checks.documentsUiSelectedTwoFiles = $true

    Invoke-TapNode $shareNode $DocumentsUiPackage
    Wait-TopPackage $ResolverPackage
    $chooser = Save-UiState '04-system-share-chooser' $ResolverPackage
    $chooserDump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'chooser-activity.txt'), $chooserDump, [Text.UTF8Encoding]::new($false))
    if ($chooserDump -notmatch 'com\.android\.intentresolver/\.ChooserActivity' -or
        $chooserDump -notmatch "launchedFromPackage=$([regex]::Escape($DocumentsUiPackage))") {
        throw 'Activity evidence did not prove that DocumentsUI launched the system chooser.'
    }
    $targetNode = Find-LabeledNode $chooser @($AppLabel, 'Pure Live', 'PureLive') -Exact
    if (-not $targetNode) { throw 'Pure Live was not listed in the system share chooser.' }
    $targetCell = Get-ClickableAncestor $targetNode
    $result.uiFlow.chooserTarget = [ordered]@{ label = Get-NodeLabel $targetNode; bounds = [string] $targetCell.bounds }
    $result.checks.documentsUiLaunchedChooser = $true
    $result.checks.pureLiveListedInChooser = $true

    Invoke-TapNode $targetNode $ResolverPackage
    Wait-TopPackage $Package 30
    Start-Sleep -Seconds 10
    Wait-TopPackage $Package
    $targetUi = Save-UiState '05-pure-live-after-share' $Package
    $result.uiFlow.targetHierarchyLength = $targetUi.OuterXml.Length
    Wait-SharedStagingEmpty
    $result.import.sharedStagingEntriesAfterImport = @(Get-SharedStagingEntries)
    $uriPermissionDump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'permissions')) -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'uri-permissions.txt'), $uriPermissionDump, [Text.UTF8Encoding]::new($false))
    $targetActivityDump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'target-activity.txt'), $targetActivityDump, [Text.UTF8Encoding]::new($false))
    $systemLog = (Invoke-Adb @('logcat', '-d', '-v', 'threadtime', '-T', $logStartTime)) -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'system-since-share.log'), $systemLog, [Text.UTF8Encoding]::new($false))
    $playlistGrant = Test-ExternalUriGrant $uriPermissionDump $playlistFileName
    $epgGrant = Test-ExternalUriGrant $uriPermissionDump $epgFileName
    $result.import.uriGrantEvidence = [ordered]@{ playlistToTarget = $playlistGrant; epgToTarget = $epgGrant }
    if (-not $playlistGrant -or -not $epgGrant) {
        throw 'Runtime permission state did not retain both external DocumentsProvider content URI grants to Pure Live.'
    }
    $uriEvidence = $uriPermissionDump + "`n" + $targetActivityDump + "`n" + $systemLog
    if ($uriEvidence -notmatch 'android\.intent\.action\.SEND_MULTIPLE') {
        throw 'Runtime evidence did not identify the UI-driven intent as ACTION_SEND_MULTIPLE.'
    }
    $result.checks.externalDocumentsProviderUrisGranted = $true
    $result.checks.uiProducedSendMultipleIntent = $true

    $processLog = Get-ProcessLog
    $result.import.processId = $processLog.pid
    if ($processLog.text) {
        [IO.File]::WriteAllText((Join-Path $evidence 'pure-live-process.log'), $processLog.text, [Text.UTF8Encoding]::new($false))
    }
    $fatalPattern = '(?im)FATAL EXCEPTION|ANR in com\.mystyle\.purelive|EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS) LIBRARY|Shared media intake failed|Shared IPTV Import Process Crash|IPTV Import Error:'
    if ($processLog.text -match $fatalPattern) { throw "Fatal or intake failure evidence was found in the app process log: $($Matches[0])" }
    $result.checks.noFatalOrAnr = $true

    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Copy-RootFileToHost $databasePath $remoteDbSnapshot $localDbSnapshot
    $queryCode = @'
import json, sqlite3, sys
db, provider_name, playlist_channel, epg_name, epg_channel, programme = sys.argv[1:]
connection = sqlite3.connect(db)
try:
    provider_rows = connection.execute(
        "SELECT id, name, type FROM providers WHERE name = ?", (provider_name,)
    ).fetchall()
    channel_rows = connection.execute(
        "SELECT provider_id, name, stream_url FROM channels WHERE name = ?", (playlist_channel,)
    ).fetchall()
    source_rows = connection.execute(
        "SELECT id, name FROM epg_sources WHERE name = ?", (epg_name,)
    ).fetchall()
    epg_channel_rows = connection.execute(
        "SELECT source_id, channel_id, display_name FROM epg_channels WHERE display_name = ?", (epg_channel,)
    ).fetchall()
    programme_rows = connection.execute(
        "SELECT source_id, title FROM epg_programmes WHERE title = ?", (programme,)
    ).fetchall()
    print(json.dumps({
        "providers": provider_rows,
        "channels": channel_rows,
        "epgSources": source_rows,
        "epgChannels": epg_channel_rows,
        "programmes": programme_rows,
    }, ensure_ascii=True))
finally:
    connection.close()
'@
    $queryText = (& python -c $queryCode $localDbSnapshot $playlistBaseName $playlistChannel $epgBaseName $epgChannel $programme 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "DocumentsUI share SQLite evidence query failed: $queryText" }
    $query = $queryText | ConvertFrom-Json
    if (@($query.providers).Count -ne 1 -or @($query.channels).Count -ne 1 -or
        @($query.epgSources).Count -ne 1 -or @($query.epgChannels).Count -ne 1 -or
        @($query.programmes).Count -ne 1) {
        throw "DocumentsUI fixtures were not committed exactly once: $queryText"
    }
    if ([string] $query.providers[0][1] -ne $playlistBaseName -or [string] $query.epgSources[0][1] -ne $epgBaseName) {
        throw "DocumentsUI source names did not preserve the external filenames: $queryText"
    }
    $result.import.databaseEvidence = $query
    $result.checks.uiDrivenMultipleShareImported = $true
} catch {
    $failure = $_
} finally {
    try { Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    if ($cacheBackedUp) {
        try {
            Invoke-Adb @('push', $localCacheBackup, $remoteCacheRestore) | Out-Null
            $guardedCachePath = "/data/user/0/$Package/app_flutter/PURE_LIVE/IPTV_CACHE"
            if ($iptvCachePath -ne $guardedCachePath) { throw 'IPTV cache cleanup target guard rejected the path.' }
            Invoke-Adb @('shell', "su -c `"rm -rf '$iptvCachePath' && tar -C '$pureLiveRoot' -xpf '$remoteCacheRestore' && restorecon -RF '$iptvCachePath'`"") | Out-Null
            $afterRestoreTree = Get-TreeManifest $iptvCachePath
            $result.preservedState.iptvTreeAfterRestore = $afterRestoreTree
            Assert-TreeManifestEqual $result.preservedState.iptvTreeBefore $afterRestoreTree 'Final restoration'
            $result.checks.iptvCacheRestoredExactly = $true
        } catch {
            if (-not $failure) { $failure = $_ } else { Write-Warning "IPTV cache restoration also failed: $($_.Exception.Message)" }
        }
    }
    if ($settingsBackedUp) {
        try {
            Invoke-Adb @('push', $localSettingsBackup, $remoteSettingsRestore) | Out-Null
            Invoke-Adb @('shell', "su -c `"cat '$remoteSettingsRestore' > '$settingsPath' && chown ${settingsUid}:${settingsGid} '$settingsPath' && chmod '$settingsMode' '$settingsPath' && restorecon '$settingsPath'`"") | Out-Null
            $result.preservedState.settingsSha256AfterRestore = Get-DeviceFileHash $settingsPath
            $result.preservedState.settingsSelinuxAfter = (Invoke-Adb @('shell', "su -c `"ls -Zd '$settingsPath'`"")) -join "`n"
            if ($result.preservedState.settingsSha256AfterRestore -ne $result.preservedState.settingsSha256Before) {
                throw 'Final settings restoration differs from the original file.'
            }
            $result.checks.settingsFileRestoredExactly = $true
        } catch {
            if (-not $failure) { $failure = $_ } else { Write-Warning "Settings restoration also failed: $($_.Exception.Message)" }
        }
    }
    foreach ($remote in @($remoteSettingsBackup, $remoteSettingsRestore, $remoteCacheBackup, $remoteCacheRestore, $remoteDbSnapshot)) {
        try { Invoke-Adb @('shell', "su -c `"rm -f '$remote'`"") | Out-Null } catch {}
    }
    if ($externalDirectoryCreated) {
        try {
            $guardedExternalPrefix = '/sdcard/Download/PureLiveShareProbe-'
            if (-not $externalDirectory.StartsWith($guardedExternalPrefix) -or $externalDirectory.Substring($guardedExternalPrefix.Length) -notmatch '^\d{14}$') {
                throw 'External fixture cleanup target guard rejected the path.'
            }
            Invoke-Adb @('shell', 'rm', '-f', $externalPlaylist) | Out-Null
            Invoke-Adb @('shell', 'rm', '-f', $externalEpg) | Out-Null
            Invoke-Adb @('shell', 'rmdir', $externalDirectory) | Out-Null
            $leftover = (Invoke-Adb @('shell', "if [ -e '$externalDirectory' ]; then echo exists; fi")) -join ''
            if ($leftover.Trim()) { throw 'External fixture directory remained after exact cleanup.' }
            $result.checks.externalFixturesRemovedExactly = $true
        } catch {
            if (-not $failure) { $failure = $_ } else { Write-Warning "External fixture cleanup also failed: $($_.Exception.Message)" }
        }
    }
    try { Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    try { Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try {
        $result.finalTopPackage = Get-TopPackage
        $result.checks.appStoppedAndHomeVisible = $result.finalTopPackage -ne $Package -and $result.finalTopPackage -ne $DocumentsUiPackage -and $result.finalTopPackage -ne $ResolverPackage
    } catch {}
    $result.finishedAt = (Get-Date).ToString('o')
    $result.status = if ($failure) { 'failed' } else { 'passed' }
    if ($failure) { $result.failure = $failure.Exception.Message }
    [IO.File]::WriteAllText(
        (Join-Path $evidence 'summary.json'),
        ($result | ConvertTo-Json -Depth 12),
        [Text.UTF8Encoding]::new($false)
    )
}

if ($failure) { throw $failure }
$result | ConvertTo-Json -Depth 12
