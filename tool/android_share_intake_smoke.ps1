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
    [string] $ExpectedDevice = 'myron',
    [string] $ExpectedPlatform = 'bilibili',
    [string] $ExpectedRoomId = '27632810',
    [string] $ShareCommand = 'iKFtqXB1cmVfbGl2ZaFwqGJpbGliaWxpoXKoMjc2MzI4MTCidGnZJeOAkOmHkeeJjOeCueWUsSDjgJHlhajpuqbpopzlgLzmrYzmiYuhbr3nuqblrpot5pyd5pqu5YWJ5bm0LeWdj-eUt-S6uqFsoKFj2WJodHRwczovL2kwLmhkc2xiLmNvbS9iZnMvbGl2ZS9uZXdfcm9vbV9jb3Zlci9kOTFmMTc0OWY0Zjk3ZjE1NWNlZDg0MmIxZThiM2UwYjJlZjc1YjM5LmpwZ0A0MDB3LmpwZ6Fh2UpodHRwczovL2kxLmhkc2xiLmNvbS9iZnMvZmFjZS9kNzU3MzgyOGU0OTY2OTBhZTc4NDk5NDg4MTcyYzY4YTNhNjU1OTczLmpwZw',
    [string] $ExpectedWarmRoomId = '27632811',
    [string] $WarmShareCommand = 'iKFtqXB1cmVfbGl2ZaFwqGJpbGliaWxpoXKoMjc2MzI4MTGidGnZJeOAkOmHkeeJjOeCueWUsSDjgJHlhajpuqbpopzlgLzmrYzmiYuhbr3nuqblrpot5pyd5pqu5YWJ5bm0LeWdj-eUt-S6uqFsoKFj2WJodHRwczovL2kwLmhkc2xiLmNvbS9iZnMvbGl2ZS9uZXdfcm9vbV9jb3Zlci9kOTFmMTc0OWY0Zjk3ZjE1NWNlZDg0MmIxZThiM2UwYjJlZjc1YjM5LmpwZ0A0MDB3LmpwZ6Fh2UpodHRwczovL2kxLmhkc2xiLmNvbS9iZnMvZmFjZS9kNzU3MzgyOGU0OTY2OTBhZTc4NDk5NDg4MTcyYzY4YTNhNjU1OTczLmpwZw'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-share-intake-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
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
        $output = & $adb -s $Serial @AdbArguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return @($output) }
        $text = $output -join "`n"
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

function Get-TopPackage {
    $dump = (Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities')) -join "`n"
    if ($dump -match '(?m)^\s*topResumedActivity=.*?\s([A-Za-z0-9._]+)\/') { return $Matches[1] }
    ''
}

function Assert-TargetForeground {
    $top = Get-TopPackage
    if ($top -ne $Package) { throw "Expected $Package to be top resumed; actual='$top'." }
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
    param([Parameter(Mandatory = $true)][string] $Name, [switch] $NoScreenshot)
    Assert-TargetForeground
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
        $remotePng = "/sdcard/purelive-share-intake-$PID-$Name.png"
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
        [switch] $Clickable,
        [switch] $Exact
    )
    @($Document.SelectNodes('//node') | Where-Object {
        $node = $_
        $label = Get-NodeLabel $node
        $matched = @($Candidates | Where-Object { if ($Exact) { $label -eq $_ } else { $label.Contains($_) } }).Count -gt 0
        $matched -and (-not $Clickable -or [string] $node.clickable -eq 'true')
    } | Sort-Object { (Get-Bounds $_).Top } | Select-Object -First 1)
}

function Test-ShareDialog {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [string] $RoomId = $ExpectedRoomId
    )
    $xml = $Document.OuterXml
    $cancel = Find-LabeledNode -Document $Document -Candidates @('取消', 'Cancel') -Clickable -Exact
    $enter = Find-LabeledNode -Document $Document -Candidates @('进入房间', '进入直播间', 'Enter Room', 'Enter room') -Clickable
    $share = Find-LabeledNode -Document $Document -Candidates @('分享', 'Share') -Exact
    $hasPlatform = $xml.Contains($ExpectedPlatform)
    $hasRoom = $xml.Contains($RoomId)
    [bool] ($cancel -and $enter -and $share -and $hasPlatform -and $hasRoom)
}

function Wait-ShareDialog {
    param(
        [Parameter(Mandatory = $true)][string] $Prefix,
        [string] $RoomId = $ExpectedRoomId,
        [int] $TimeoutSeconds = 25
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        if ((Get-TopPackage) -eq $Package) {
            $document = Save-UiState "$Prefix-$attempt" -NoScreenshot
            if (Test-ShareDialog $document $RoomId) { return Save-UiState "$Prefix-ready" }
        }
        Start-Sleep -Milliseconds 650
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for the shared-room import dialog; top package='$(Get-TopPackage)'."
}

function Wait-ShareDialogClosed {
    param(
        [Parameter(Mandatory = $true)][string] $Prefix,
        [string] $RoomId = $ExpectedRoomId,
        [int] $TimeoutSeconds = 12
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    do {
        $attempt++
        $document = Save-UiState "$Prefix-$attempt" -NoScreenshot
        if (-not (Test-ShareDialog $document $RoomId)) { return $document }
        Start-Sleep -Milliseconds 650
    } while ((Get-Date) -lt $deadline)
    throw 'The shared-room import dialog remained visible after cancellation.'
}

function Invoke-TapNode {
    param([Parameter(Mandatory = $true)] $Node)
    Assert-TargetForeground
    $bounds = Get-Bounds $Node
    Invoke-Adb @('shell', 'input', 'tap', $bounds.X, $bounds.Y) | Out-Null
}

function Close-ShareDialog {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string] $Prefix,
        [string] $RoomId = $ExpectedRoomId
    )
    $cancel = Find-LabeledNode -Document $Document -Candidates @('取消', 'Cancel') -Clickable -Exact
    if (-not $cancel) { throw 'The shared-room import dialog has no Cancel action.' }
    Invoke-TapNode $cancel
    Start-Sleep -Milliseconds 500
    Wait-ShareDialogClosed $Prefix $RoomId | Out-Null
}

function Assert-DialogBounds {
    param([Parameter(Mandatory = $true)][xml] $Document, [int] $Width, [int] $Height)
    $result = [ordered]@{}
    foreach ($entry in ([ordered]@{
        cancel = @('取消', 'Cancel')
        enter = @('进入房间', '进入直播间', 'Enter Room', 'Enter room')
    }).GetEnumerator()) {
        $node = Find-LabeledNode -Document $Document -Candidates $entry.Value -Clickable
        if (-not $node) { throw "Missing dialog action: $($entry.Key)." }
        $bounds = Get-Bounds $node
        if ($bounds.Left -lt 0 -or $bounds.Top -lt 0 -or $bounds.Right -gt $Width -or $bounds.Bottom -gt $Height -or
            $bounds.Width -lt 40 -or $bounds.Height -lt 40) {
            throw "$($entry.Key) has clipped or undersized bounds: $([string] $node.bounds)."
        }
        $result[$entry.Key] = [ordered]@{ label = Get-NodeLabel $node; bounds = [string] $node.bounds }
    }
    $result
}

function Start-ShareTextIntent {
    param([string] $Command = $ShareCommand)
    (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-a', 'android.intent.action.SEND', '-t', 'text/plain',
        '--es', 'android.intent.extra.TEXT', $Command, '-n', "$Package/.MainActivity"
    )) -join "`n"
}

function Get-SharedStagingEntries {
    @(Invoke-Adb @(
        'shell',
        "su -c `"if [ -e '/data/user/0/$Package/cache/share_handler' ]; then find '/data/user/0/$Package/cache/share_handler' -mindepth 0 -print; fi`""
    ))
}

function Wait-SharedStagingEmpty {
    param([int] $TimeoutSeconds = 12)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $entries = @(Get-SharedStagingEntries)
        if ($entries.Count -eq 0) { return }
        Start-Sleep -Milliseconds 400
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
    $expectedMetadata = $Expected.metadata -join "`n"
    $actualMetadata = $Actual.metadata -join "`n"
    $expectedHashes = $Expected.hashes -join "`n"
    $actualHashes = $Actual.hashes -join "`n"
    if ($expectedMetadata -ne $actualMetadata -or $expectedHashes -ne $actualHashes) {
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

$settingsPath = "/data/user/0/$Package/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive"
$pureLiveRoot = "/data/user/0/$Package/app_flutter/PURE_LIVE"
$iptvCachePath = "$pureLiveRoot/IPTV_CACHE"
$databasePath = "$iptvCachePath/pure_live_tv/pure_live_tv.db"
$remoteSettingsBackup = "/data/local/tmp/purelive-share-intake-$PID-original.hive"
$remoteSettingsRestore = "/data/local/tmp/purelive-share-intake-$PID-restore.hive"
$remoteCacheBackup = "/data/local/tmp/purelive-share-intake-$PID-cache.tar"
$remoteCacheRestore = "/data/local/tmp/purelive-share-intake-$PID-cache-restore.tar"
$remoteDbSnapshot = "/data/local/tmp/purelive-share-intake-$PID.db"
$remoteMixedDbSnapshot = "/data/local/tmp/purelive-share-intake-$PID-mixed.db"
$remoteMultipleDbSnapshot = "/data/local/tmp/purelive-share-intake-$PID-multiple.db"
$remoteProviderEdgeDbSnapshot = "/data/local/tmp/purelive-share-intake-$PID-provider-edge.db"
$localSettingsBackup = Join-Path $evidence 'app_settings.original.hive'
$localCacheBackup = Join-Path $evidence 'iptv_cache.original.tar'
$localDbSnapshot = Join-Path $evidence 'iptv_after_share.db'
$localMixedDbSnapshot = Join-Path $evidence 'iptv_after_mixed_share.db'
$localMultipleDbSnapshot = Join-Path $evidence 'iptv_after_multiple_share.db'
$localProviderEdgeDbSnapshot = Join-Path $evidence 'iptv_after_provider_edge_share.db'
$fixtureTag = Get-Date -Format 'yyMMddHHmmssff'
$fixtureBaseName = "purelive-share-intake-$fixtureTag"
$fixtureChannel = "Share Intake Fixture $fixtureTag"
$localFixture = Join-Path $evidence "$fixtureBaseName.m3u"
$stagedDeviceFixture = "/data/local/tmp/$fixtureBaseName.m3u"
$deviceFixture = "/data/user/0/$Package/cache/$fixtureBaseName.m3u"
$deviceFixtureUri = "content://$Package.fileProvider/cache-path/$fixtureBaseName.m3u"
$multiplePlaylistBaseName = "$fixtureBaseName-multiple-playlist"
$multiplePlaylistChannel = "Share Multiple Playlist $fixtureTag"
$multipleEpgBaseName = "$fixtureBaseName-multiple-epg"
$multipleEpgChannelId = "share-multiple-$fixtureTag"
$multipleEpgChannel = "Share Multiple EPG $fixtureTag"
$multipleProgramme = "Share Multiple Programme $fixtureTag"
$localMultiplePlaylist = Join-Path $evidence "$multiplePlaylistBaseName.m3u"
$localMultipleEpg = Join-Path $evidence "$multipleEpgBaseName.xml"
$stagedMultiplePlaylist = "/data/local/tmp/$multiplePlaylistBaseName.m3u"
$stagedMultipleEpg = "/data/local/tmp/$multipleEpgBaseName.xml"
$probeRoot = "/data/user/0/$Package/cache/share_probe"
$deviceMultiplePlaylist = "$probeRoot/$multiplePlaylistBaseName.m3u"
$deviceMultipleEpg = "$probeRoot/$multipleEpgBaseName.xml"
$providerFallbackBaseName = "$fixtureBaseName-provider-query-fallback"
$providerFallbackChannel = "Share Provider Fallback $fixtureTag"
$providerLongUnderlyingBaseName = "$fixtureBaseName-provider-long-source"
$providerLongChannel = "Share Provider Long Name $fixtureTag"
$providerLongExpectedPrefix = '共享_附件_'
$localProviderFallback = Join-Path $evidence "$providerFallbackBaseName.m3u"
$localProviderLong = Join-Path $evidence "$providerLongUnderlyingBaseName.m3u"
$stagedProviderFallback = "/data/local/tmp/$providerFallbackBaseName.m3u"
$stagedProviderLong = "/data/local/tmp/$providerLongUnderlyingBaseName.m3u"
$deviceProviderFallback = "$probeRoot/$providerFallbackBaseName.m3u"
$deviceProviderLong = "$probeRoot/$providerLongUnderlyingBaseName.m3u"
[IO.File]::WriteAllText(
    $localFixture,
    "#EXTM3U`n#EXTINF:-1 tvg-id=`"$fixtureTag`" group-title=`"Fixture`",$fixtureChannel`nhttps://example.invalid/$fixtureTag/live.m3u8`n",
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $localMultiplePlaylist,
    "#EXTM3U`n#EXTINF:-1 tvg-id=`"multiple-$fixtureTag`" group-title=`"Fixture`",$multiplePlaylistChannel`nhttps://example.invalid/$fixtureTag/multiple.m3u8`n",
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $localMultipleEpg,
    "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<tv><channel id=`"$multipleEpgChannelId`"><display-name>$multipleEpgChannel</display-name></channel><programme channel=`"$multipleEpgChannelId`" start=`"20360101000000 +0000`" stop=`"20360101010000 +0000`"><title>$multipleProgramme</title></programme></tv>`n",
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $localProviderFallback,
    "#EXTM3U`n#EXTINF:-1 tvg-id=`"provider-fallback-$fixtureTag`" group-title=`"Fixture`",$providerFallbackChannel`nhttps://example.invalid/$fixtureTag/provider-fallback.m3u8`n",
    [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
    $localProviderLong,
    "#EXTM3U`n#EXTINF:-1 tvg-id=`"provider-long-$fixtureTag`" group-title=`"Fixture`",$providerLongChannel`nhttps://example.invalid/$fixtureTag/provider-long.m3u8`n",
    [Text.UTF8Encoding]::new($false)
)

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    package = $Package
    identity = $null
    display = [ordered]@{}
    apk = [ordered]@{ path = $apk; expectedSha256 = $ExpectedApkSha256.ToUpperInvariant() }
    preservedState = [ordered]@{}
    commandShare = [ordered]@{}
    mixedShare = [ordered]@{}
    fileShare = [ordered]@{ fixtureBaseName = $fixtureBaseName; fixtureChannel = $fixtureChannel }
    multipleShare = [ordered]@{
        playlistBaseName = $multiplePlaylistBaseName
        playlistChannel = $multiplePlaylistChannel
        epgBaseName = $multipleEpgBaseName
        epgChannel = $multipleEpgChannel
        programme = $multipleProgramme
    }
    providerEdgeShare = [ordered]@{
        fallbackBaseName = $providerFallbackBaseName
        fallbackChannel = $providerFallbackChannel
        longUnderlyingBaseName = $providerLongUnderlyingBaseName
        longChannel = $providerLongChannel
        expectedSafePrefix = $providerLongExpectedPrefix
    }
    checks = [ordered]@{}
}
$failure = $null
$settingsBackedUp = $false
$cacheBackedUp = $false
$settingsUid = $null
$settingsGid = $null
$settingsMode = $null
$processLogs = [Collections.Generic.List[string]]::new()

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
    $result.checks.overlayInstallPreservedData = $true
    $result.checks.installedApkMatchesCandidate = $true

    $result.commandShare.coldLaunchOutput = Start-ShareTextIntent
    $coldDialog = Wait-ShareDialog 'cold-share'
    $result.commandShare.coldDialogActions = Assert-DialogBounds $coldDialog $result.display.width $result.display.height
    $result.commandShare.coldHierarchyLength = $coldDialog.OuterXml.Length
    $result.checks.coldShareCommandAcceptedAfterSplash = $true
    Close-ShareDialog $coldDialog 'cold-share-closed'

    $result.commandShare.warmLaunchOutput = Start-ShareTextIntent $WarmShareCommand
    $warmDialog = Wait-ShareDialog 'warm-share' $ExpectedWarmRoomId
    $result.commandShare.duplicateLaunchOutput = Start-ShareTextIntent $WarmShareCommand
    Start-Sleep -Milliseconds 500
    Close-ShareDialog $warmDialog 'warm-share-closed' $ExpectedWarmRoomId
    Start-Sleep -Seconds 2
    $afterDuplicate = Save-UiState 'warm-share-after-duplicate'
    if (Test-ShareDialog $afterDuplicate $ExpectedWarmRoomId) { throw 'A duplicate warm share reopened the import dialog.' }
    $result.checks.warmShareCommandAccepted = $true
    $result.checks.duplicateWarmShareSuppressed = $true

    Invoke-Adb @('push', $localFixture, $stagedDeviceFixture) | Out-Null
    Invoke-Adb @('shell', "su -c `"cp '$stagedDeviceFixture' '$deviceFixture' && chown ${settingsUid}:${settingsGid} '$deviceFixture' && chmod 600 '$deviceFixture' && restorecon '$deviceFixture'`"") | Out-Null
    $result.fileShare.deviceFixtureSha256 = Get-DeviceFileHash $deviceFixture
    $result.mixedShare.launchOutput = (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-a', 'android.intent.action.SEND', '-t', 'application/x-mpegURL',
        '--grant-read-uri-permission', '--es', 'android.intent.extra.TEXT', $WarmShareCommand,
        '--eu', 'android.intent.extra.STREAM', $deviceFixtureUri, '-n', "$Package/.MainActivity"
    )) -join "`n"
    Start-Sleep -Seconds 2
    Assert-TargetForeground
    $afterMixed = Save-UiState 'mixed-command-attachment-after'
    if (Test-ShareDialog $afterMixed $ExpectedWarmRoomId) { throw 'A duplicate command with an attachment reopened the import dialog.' }
    Wait-SharedStagingEmpty
    $result.mixedShare.sharedStagingEntriesAfterCommand = @(Get-SharedStagingEntries)
    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Copy-RootFileToHost $databasePath $remoteMixedDbSnapshot $localMixedDbSnapshot
    $mixedQueryCode = @'
import sqlite3, sys
db, channel_name = sys.argv[1:]
connection = sqlite3.connect(db)
try:
    print(connection.execute("SELECT count(*) FROM channels WHERE name = ?", (channel_name,)).fetchone()[0])
finally:
    connection.close()
'@
    $mixedCountText = (& python -c $mixedQueryCode $localMixedDbSnapshot $fixtureChannel 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $mixedCountText.Trim() -ne '0') {
        throw "A command-priority attachment was imported instead of only being released: $mixedCountText"
    }
    $result.mixedShare.databaseChannelCount = 0
    $result.checks.commandPriorityAttachmentReleased = $true

    $result.fileShare.launchOutput = (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-a', 'android.intent.action.SEND', '-t', 'application/x-mpegURL',
        '--grant-read-uri-permission', '--eu', 'android.intent.extra.STREAM', $deviceFixtureUri, '-n', "$Package/.MainActivity"
    )) -join "`n"
    Start-Sleep -Seconds 5
    Assert-TargetForeground
    $log = Get-ProcessLog
    if ($log.text) { $processLogs.Add($log.text); [IO.File]::WriteAllText((Join-Path $evidence 'process.log'), $log.text, [Text.UTF8Encoding]::new($false)) }
    $result.fileShare.processId = $log.pid
    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Copy-RootFileToHost $databasePath $remoteDbSnapshot $localDbSnapshot
    Wait-SharedStagingEmpty
    $sharedStagingFiles = @(Invoke-Adb @('shell', "su -c `"if [ -d '/data/user/0/$Package/cache/share_handler' ]; then find '/data/user/0/$Package/cache/share_handler' -type f; fi`""))
    $result.fileShare.sharedStagingFilesAfterImport = @($sharedStagingFiles | ForEach-Object { [string] $_ })
    $result.fileShare.sharedStagingEntriesAfterImport = @(Get-SharedStagingEntries)
    if ($sharedStagingFiles.Count -ne 0) { throw 'Shared-media staging files remained after import.' }
    $result.checks.sharedMediaStagingCleaned = $true
    $pythonCode = @'
import json, sqlite3, sys
db, _provider_name, channel_name = sys.argv[1:]
connection = sqlite3.connect(db)
try:
    channel_rows = connection.execute("SELECT provider_id, name, stream_url FROM channels WHERE name = ?", (channel_name,)).fetchall()
    provider_rows = connection.execute(
        "SELECT id, name, type, url FROM providers WHERE id IN "
        "(SELECT provider_id FROM channels WHERE name = ?)",
        (channel_name,),
    ).fetchall()
    print(json.dumps({"providers": provider_rows, "channels": channel_rows}, ensure_ascii=False))
finally:
    connection.close()
'@
    $queryText = (& python -c $pythonCode $localDbSnapshot $fixtureBaseName $fixtureChannel 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "SQLite evidence query failed: $queryText" }
    $query = $queryText | ConvertFrom-Json
    if (@($query.providers).Count -ne 1 -or @($query.channels).Count -ne 1 -or
        [string] $query.providers[0][1] -ne $fixtureBaseName) {
      throw "Shared playlist fixture was not committed exactly once: $queryText"
    }
    $result.fileShare.databaseEvidence = $query
    $result.checks.sharedPlaylistAttachmentImported = $true

    Invoke-Adb @('push', $localMultiplePlaylist, $stagedMultiplePlaylist) | Out-Null
    Invoke-Adb @('push', $localMultipleEpg, $stagedMultipleEpg) | Out-Null
    Invoke-Adb @(
        'shell',
        "su -c `"mkdir -p '$probeRoot' && cp '$stagedMultiplePlaylist' '$deviceMultiplePlaylist' && cp '$stagedMultipleEpg' '$deviceMultipleEpg' && chown -R ${settingsUid}:${settingsGid} '$probeRoot' && chmod 700 '$probeRoot' && chmod 600 '$deviceMultiplePlaylist' '$deviceMultipleEpg' && restorecon -RF '$probeRoot'`""
    ) | Out-Null
    $result.multipleShare.playlistSha256 = Get-DeviceFileHash $deviceMultiplePlaylist
    $result.multipleShare.epgSha256 = Get-DeviceFileHash $deviceMultipleEpg
    $result.multipleShare.appLaunchOutput = (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity"
    )) -join "`n"
    Start-Sleep -Seconds 3
    Assert-TargetForeground
    $result.multipleShare.probeOutput = (Invoke-Adb @(
        'shell', 'am', 'broadcast', '--receiver-foreground',
        '-a', 'com.mystyle.purelive.debug.SEND_MULTIPLE_PROBE',
        '-n', "$Package/.ShareIntentProbeReceiver",
        '--esa', 'paths', "$deviceMultiplePlaylist,$deviceMultipleEpg"
    )) -join "`n"
    if ($result.multipleShare.probeOutput -notmatch 'result=-1' -or
        $result.multipleShare.probeOutput -notmatch 'data="ok:send_multiple:2"') {
        throw "SEND_MULTIPLE probe was rejected: $($result.multipleShare.probeOutput)"
    }
    Start-Sleep -Seconds 6
    Assert-TargetForeground
    Wait-SharedStagingEmpty
    $result.multipleShare.sharedStagingEntriesAfterImport = @(Get-SharedStagingEntries)
    $multipleLog = Get-ProcessLog
    if ($multipleLog.text) {
        $processLogs.Add($multipleLog.text)
        [IO.File]::WriteAllText(
            (Join-Path $evidence 'multiple-process.log'),
            $multipleLog.text,
            [Text.UTF8Encoding]::new($false)
        )
    }
    $result.multipleShare.processId = $multipleLog.pid
    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Copy-RootFileToHost $databasePath $remoteMultipleDbSnapshot $localMultipleDbSnapshot
    $multipleQueryCode = @'
import json, sqlite3, sys
db, provider_name, channel_name, epg_name, epg_channel, programme = sys.argv[1:]
connection = sqlite3.connect(db)
try:
    provider_rows = connection.execute(
        "SELECT id, name, type FROM providers WHERE name = ?", (provider_name,)
    ).fetchall()
    channel_rows = connection.execute(
        "SELECT provider_id, name, stream_url FROM channels WHERE name = ?", (channel_name,)
    ).fetchall()
    source_rows = connection.execute(
        "SELECT id, name FROM epg_sources WHERE name = ?", (epg_name,)
    ).fetchall()
    epg_channel_rows = connection.execute(
        "SELECT source_id, channel_id, display_name FROM epg_channels WHERE display_name = ?",
        (epg_channel,),
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
    }, ensure_ascii=False))
finally:
    connection.close()
'@
    $multipleQueryText = (& python -c $multipleQueryCode $localMultipleDbSnapshot $multiplePlaylistBaseName $multiplePlaylistChannel $multipleEpgBaseName $multipleEpgChannel $multipleProgramme 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "SEND_MULTIPLE SQLite evidence query failed: $multipleQueryText" }
    $multipleQuery = $multipleQueryText | ConvertFrom-Json
    if (@($multipleQuery.providers).Count -ne 1 -or @($multipleQuery.channels).Count -ne 1 -or
        @($multipleQuery.epgSources).Count -ne 1 -or @($multipleQuery.epgChannels).Count -ne 1 -or
        @($multipleQuery.programmes).Count -ne 1) {
        throw "SEND_MULTIPLE fixtures were not committed exactly once: $multipleQueryText"
    }
    if ([string] $multipleQuery.providers[0][1] -ne $multiplePlaylistBaseName -or
        [string] $multipleQuery.epgSources[0][1] -ne $multipleEpgBaseName) {
        throw "SEND_MULTIPLE source names did not preserve attachment names: $multipleQueryText"
    }
    $result.multipleShare.databaseEvidence = $multipleQuery
    $result.checks.multiplePlaylistAndEpgAttachmentsImported = $true

    Invoke-Adb @('push', $localProviderFallback, $stagedProviderFallback) | Out-Null
    Invoke-Adb @('push', $localProviderLong, $stagedProviderLong) | Out-Null
    Invoke-Adb @(
        'shell',
        "su -c `"cp '$stagedProviderFallback' '$deviceProviderFallback' && cp '$stagedProviderLong' '$deviceProviderLong' && chown ${settingsUid}:${settingsGid} '$deviceProviderFallback' '$deviceProviderLong' && chmod 600 '$deviceProviderFallback' '$deviceProviderLong' && restorecon '$deviceProviderFallback' '$deviceProviderLong'`""
    ) | Out-Null
    $result.providerEdgeShare.fallbackSha256 = Get-DeviceFileHash $deviceProviderFallback
    $result.providerEdgeShare.longSha256 = Get-DeviceFileHash $deviceProviderLong
    $result.providerEdgeShare.appLaunchOutput = (Invoke-Adb @(
        'shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity"
    )) -join "`n"
    Start-Sleep -Seconds 3
    Assert-TargetForeground
    $result.providerEdgeShare.probeOutput = (Invoke-Adb @(
        'shell', 'am', 'broadcast', '--receiver-foreground',
        '-a', 'com.mystyle.purelive.debug.PROVIDER_EDGE_PROBE',
        '-n', "$Package/.ShareIntentProbeReceiver",
        '--esa', 'paths', "$deviceProviderFallback,$deviceProviderLong"
    )) -join "`n"
    if ($result.providerEdgeShare.probeOutput -notmatch 'result=-1' -or
        $result.providerEdgeShare.probeOutput -notmatch 'data="ok:provider_edges:3"') {
        throw "Provider-edge probe was rejected: $($result.providerEdgeShare.probeOutput)"
    }
    Start-Sleep -Seconds 8
    Assert-TargetForeground
    Wait-SharedStagingEmpty
    $result.providerEdgeShare.sharedStagingEntriesAfterImport = @(Get-SharedStagingEntries)
    $providerEdgeLog = Get-ProcessLog
    if ($providerEdgeLog.text) {
        $processLogs.Add($providerEdgeLog.text)
        [IO.File]::WriteAllText(
            (Join-Path $evidence 'provider-edge-process.log'),
            $providerEdgeLog.text,
            [Text.UTF8Encoding]::new($false)
        )
    }
    $result.providerEdgeShare.processId = $providerEdgeLog.pid
    if ($providerEdgeLog.text -notmatch 'Shared URI attachment failed' -or
        $providerEdgeLog.text -notmatch 'Shared URI display name query failed') {
        throw 'Provider-edge process log did not prove both injected failure paths were exercised.'
    }
    $result.checks.providerFailuresExercised = $true
    Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null
    Copy-RootFileToHost $databasePath $remoteProviderEdgeDbSnapshot $localProviderEdgeDbSnapshot
    $providerEdgeQueryCode = @'
import json, sqlite3, sys
db, fallback_channel, long_channel = sys.argv[1:]
connection = sqlite3.connect(db)
try:
    fallback_rows = connection.execute(
        "SELECT p.name, c.name, c.stream_url FROM providers p JOIN channels c ON c.provider_id = p.id WHERE c.name = ?",
        (fallback_channel,),
    ).fetchall()
    long_rows = connection.execute(
        "SELECT p.name, c.name, c.stream_url FROM providers p JOIN channels c ON c.provider_id = p.id WHERE c.name = ?",
        (long_channel,),
    ).fetchall()
    print(json.dumps({"fallback": fallback_rows, "longName": long_rows}, ensure_ascii=False))
finally:
    connection.close()
'@
    $providerEdgeQueryText = (& python -c $providerEdgeQueryCode $localProviderEdgeDbSnapshot $providerFallbackChannel $providerLongChannel 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Provider-edge SQLite evidence query failed: $providerEdgeQueryText" }
    $providerEdgeQuery = $providerEdgeQueryText | ConvertFrom-Json
    if (@($providerEdgeQuery.fallback).Count -ne 1 -or @($providerEdgeQuery.longName).Count -ne 1) {
        throw "Good attachments after provider failures were not committed exactly once: $providerEdgeQueryText"
    }
    if ([string] $providerEdgeQuery.fallback[0][0] -ne $providerFallbackBaseName) {
        throw "Query-failure URI did not fall back to its path filename: $providerEdgeQueryText"
    }
    $longProviderName = [string] $providerEdgeQuery.longName[0][0]
    $longProviderNameBytes = [Text.Encoding]::UTF8.GetByteCount($longProviderName)
    if (-not $longProviderName.StartsWith($providerLongExpectedPrefix) -or
        -not $longProviderName.EndsWith('😀') -or
        $longProviderName.Contains([char] 0x0001) -or
        $longProviderName.Contains([char] 0xfffd) -or
        $longProviderNameBytes -lt 170 -or
        ($longProviderNameBytes + [Text.Encoding]::UTF8.GetByteCount('.m3u')) -gt 180) {
        throw "Long shared display name was not safely sanitized and UTF-8 bounded: name='$longProviderName', bytes=$longProviderNameBytes"
    }
    $result.providerEdgeShare.databaseEvidence = $providerEdgeQuery
    $result.providerEdgeShare.safeProviderName = $longProviderName
    $result.providerEdgeShare.safeProviderNameUtf8Bytes = $longProviderNameBytes
    $result.checks.providerFailureDidNotSuppressLaterAttachments = $true
    $result.checks.queryFailureUsedUriFilename = $true
    $result.checks.longUnicodeDisplayNameSanitizedAndBounded = $true

    $combinedLog = $processLogs -join "`n"
    $fatalPattern = '(?im)FATAL EXCEPTION|ANR in com\.mystyle\.purelive|EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS) LIBRARY|Shared media intake failed|Shared IPTV Import Process Crash|IPTV Import Error:'
    if ($combinedLog -match $fatalPattern) { throw "Fatal or intake failure evidence was found in the app process log: $($Matches[0])" }
    $result.checks.noFatalOrAnr = $true
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
    foreach ($remote in @(
        $deviceFixture,
        $stagedDeviceFixture,
        $stagedMultiplePlaylist,
        $stagedMultipleEpg,
        $stagedProviderFallback,
        $stagedProviderLong,
        $remoteSettingsBackup,
        $remoteSettingsRestore,
        $remoteCacheBackup,
        $remoteCacheRestore,
        $remoteDbSnapshot,
        $remoteMixedDbSnapshot,
        $remoteMultipleDbSnapshot,
        $remoteProviderEdgeDbSnapshot
    )) {
        try { Invoke-Adb @('shell', "su -c `"rm -f '$remote'`"") | Out-Null } catch {}
    }
    try {
        $guardedProbeRoot = "/data/user/0/$Package/cache/share_probe"
        if ($probeRoot -ne $guardedProbeRoot) { throw 'Share probe cleanup target guard rejected the path.' }
        Invoke-Adb @('shell', "su -c `"rm -rf '$probeRoot'`"") | Out-Null
    } catch {
        if (-not $failure) { $failure = $_ } else { Write-Warning "Share probe cleanup also failed: $($_.Exception.Message)" }
    }
    try { Invoke-Adb @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    try { Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null } catch {}
    try {
        $result.finalTopPackage = Get-TopPackage
        $result.checks.appStoppedAndHomeVisible = $result.finalTopPackage -ne $Package
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
