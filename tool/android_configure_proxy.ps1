[CmdletBinding()]
param(
    [string]$Serial,
    [ValidateSet('Disabled', 'LocalClash')]
    [string]$Mode = 'Disabled',
    [ValidateRange(1, 65535)]
    [int]$Port = 7897,
    [string]$EvidenceDirectory,
    [switch]$KeepAppOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'ADB executable was not found.' }

$ready = @(& $adb devices | Select-String '^(.+?)\s+device\s*$' | ForEach-Object {
    $_.Matches[0].Groups[1].Value.Trim()
})
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $network = @($ready | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}:\d+$' })
    if ($network.Count -eq 1) { $Serial = $network[0] }
    elseif ($ready.Count -eq 1) { $Serial = $ready[0] }
    else { throw "Expected one ready Android target, found $($ready.Count)." }
}
if ($Serial -notin $ready) { throw "Android target is not ready: $Serial" }

$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo ('local-artifacts\diagnostics\android-proxy-{0}-{1}' -f $Mode.ToLowerInvariant(), [DateTime]::Now.ToString('yyyyMMddTHHmmssfff'))
} elseif ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    $EvidenceDirectory
} else {
    Join-Path $repo $EvidenceDirectory
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

function Invoke-Adb([string[]]$Arguments) {
    $output = & $adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    @($output)
}

function Keep-DeviceInteractive {
    # K90 Pro locks after ten minutes. Network ADB/UIAutomator can make a
    # semantic fallback last longer than that, so every UI boundary refreshes
    # the no-password keyguard before reading or touching coordinates.
    Invoke-Adb @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

function Get-DeviceUiProfile {
    $size = (Invoke-Adb @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { return }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    $mapPath = Join-Path $PSScriptRoot 'device_ui_map.json'
    $map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $match = @($map.profiles.PSObject.Properties | Where-Object {
        [int]$_.Value.width -eq $width -and [int]$_.Value.height -eq $height
    } | Select-Object -First 1)
    if ($match.Count -eq 0) { return }
    $match[0].Value
}

function Invoke-ProfilePoint($Profile, [string]$Name) {
    $property = $Profile.points.PSObject.Properties[$Name]
    if (-not $property) { throw "Device UI profile is missing point: $Name" }
    Keep-DeviceInteractive
    Invoke-Adb @('shell', 'input', 'tap', [string]$property.Value.x, [string]$property.Value.y) | Out-Null
}

function Invoke-ProfileGesture($Profile, [string]$Name) {
    $property = $Profile.gestures.PSObject.Properties[$Name]
    if (-not $property) { throw "Device UI profile is missing gesture: $Name" }
    $g = $property.Value
    Keep-DeviceInteractive
    Invoke-Adb @(
        'shell', 'input', 'swipe',
        [string]$g.x1, [string]$g.y1,
        [string]$g.x2, [string]$g.y2,
        [string]$g.durationMs
    ) | Out-Null
}

function Get-UiDocument([string]$Name) {
    Keep-DeviceInteractive
    $remote = "/sdcard/purelive-proxy-$PID.xml"
    $local = Join-Path $evidence "$Name.xml"
    Invoke-Adb @('shell', 'uiautomator', 'dump', '--compressed', $remote) | Out-Null
    Invoke-Adb @('pull', $remote, $local) | Out-Null
    Invoke-Adb @('shell', 'rm', '-f', $remote) | Out-Null
    [xml](Get-Content -LiteralPath $local -Raw -Encoding UTF8)
}

function Find-UiNode([xml]$Document, [string]$Title) {
    $match = @($Document.SelectNodes('//node') | Where-Object {
        $_.GetAttribute('text') -eq $Title -or
        $_.GetAttribute('content-desc') -eq $Title -or
        $_.GetAttribute('text') -like "$Title`n*" -or
        $_.GetAttribute('content-desc') -like "$Title`n*"
    } | Select-Object -First 1)
    if ($match.Count -eq 0) { return }
    [pscustomobject]@{
        Checked = $match[0].GetAttribute('checked')
        Bounds = $match[0].GetAttribute('bounds')
    }
}

function Tap-Node($Node) {
    $bounds = $Node.Bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "Unexpected UI bounds: $bounds" }
    $x = [math]::Round(([int]$Matches[1] + [int]$Matches[3]) / 2)
    $y = [math]::Round(([int]$Matches[2] + [int]$Matches[4]) / 2)
    Keep-DeviceInteractive
    Invoke-Adb @('shell', 'input', 'tap', $x, $y) | Out-Null
    Start-Sleep -Milliseconds 700
}

function Find-ScrollableNode([string]$Title, [string]$Prefix, [int]$Attempts = 8) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $document = Get-UiDocument "$Prefix-$attempt"
        $nodes = @(Find-UiNode $document $Title)
        if ($nodes.Count -eq 1) { return $nodes[0] }
        Invoke-Adb @('shell', 'input', 'swipe', '600', '2050', '600', '1250', '320') | Out-Null
        Start-Sleep -Milliseconds 450
    }
    throw "UI item was not found after bounded scrolling: $Title"
}

function Set-Switch([string]$Title, [bool]$Enabled) {
    $node = Find-ScrollableNode $Title ('switch-' + $Title.GetHashCode()) 6
    $wasEnabled = $node.Checked -eq 'true'
    if ($wasEnabled -ne $Enabled) { Tap-Node $node }

    $document = Get-UiDocument ('verify-' + $Title.GetHashCode())
    $verified = @(Find-UiNode $document $Title)
    if ($verified.Count -ne 1) {
        $verified = @(Find-ScrollableNode $Title ('verify-scroll-' + $Title.GetHashCode()) 4)
    }
    $isEnabled = $verified[0].Checked -eq 'true'
    if ($isEnabled -ne $Enabled) { throw "Proxy switch did not reach requested state: $Title" }
    [pscustomobject]@{ Previous = $wasEnabled; Current = $isEnabled }
}

function Set-SwitchesFromDocument([xml]$Document, [bool]$Enabled) {
    $appNode = @(Find-UiNode $Document '启用应用层代理')
    $playerNode = @(Find-UiNode $Document '启用播放代理')
    if ($appNode.Count -ne 1 -or $playerNode.Count -ne 1) { return }

    $appWasEnabled = $appNode[0].Checked -eq 'true'
    $playerWasEnabled = $playerNode[0].Checked -eq 'true'
    # Toggle the lower/player section first. Changing the app switch expands or
    # collapses its host/port fields and therefore moves the player row; doing
    # the lower row first keeps both coordinates from this one dump valid.
    if ($playerWasEnabled -ne $Enabled) { Tap-Node $playerNode[0] }
    if ($appWasEnabled -ne $Enabled) { Tap-Node $appNode[0] }

    $verified = Get-UiDocument 'proxy-fast-verify'
    $appVerified = @(Find-UiNode $verified '启用应用层代理')
    $playerVerified = @(Find-UiNode $verified '启用播放代理')
    if ($appVerified.Count -ne 1 -or $playerVerified.Count -ne 1) {
        throw 'Proxy switches disappeared while verifying the fast device-profile path.'
    }
    $appEnabled = $appVerified[0].Checked -eq 'true'
    $playerEnabled = $playerVerified[0].Checked -eq 'true'
    if ($appEnabled -ne $Enabled -or $playerEnabled -ne $Enabled) {
        throw 'Proxy switches did not reach the requested state on the fast device-profile path.'
    }
    [pscustomobject]@{
        App = [pscustomobject]@{ Previous = $appWasEnabled; Current = $appEnabled }
        Player = [pscustomobject]@{ Previous = $playerWasEnabled; Current = $playerEnabled }
        Document = $verified
    }
}

function Test-LocalTcpPort([int]$TcpPort) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync('127.0.0.1', $TcpPort)
        if (-not $task.Wait(3000)) { return $false }
        $task.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion
    } catch {
        $false
    } finally {
        $client.Dispose()
    }
}

$enable = $Mode -eq 'LocalClash'
if ($enable -and -not (Test-LocalTcpPort $Port)) {
    throw "Local Clash proxy is not listening on 127.0.0.1:$Port."
}

$reverseRemoved = $false
if ($enable) {
    Invoke-Adb @('reverse', "tcp:$Port", "tcp:$Port") | Out-Null
} else {
    # Remove host routing before UI work so even an unexpected screen/layout
    # failure cannot leave the shared phone connected to the test proxy.
    $reverseOutput = @(& $adb -s $Serial reverse --remove "tcp:$Port" 2>&1)
    $reverseExitCode = $LASTEXITCODE
    $reverseRemoved = $reverseExitCode -eq 0 -or ($reverseOutput -join "`n") -match 'not found'
}

Invoke-Adb @('shell', 'am', 'force-stop', 'com.mystyle.purelive') | Out-Null
Invoke-Adb @('shell', 'monkey', '-p', 'com.mystyle.purelive', '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
Start-Sleep -Seconds 4

$profile = Get-DeviceUiProfile
$fastDocument = $null
if ($null -ne $profile) {
    Invoke-ProfilePoint $profile 'home.menu'
    Start-Sleep -Milliseconds 500
    Invoke-ProfilePoint $profile 'drawer.settings'
    Start-Sleep -Milliseconds 850
    Invoke-ProfileGesture $profile 'settings.scroll_down_short'
    Start-Sleep -Milliseconds 550
    Invoke-ProfilePoint $profile 'settings.network_proxy_after_short_scroll'
    Start-Sleep -Milliseconds 850
    $candidate = Get-UiDocument 'proxy-fast-entry'
    if (@(Find-UiNode $candidate '启用应用层代理').Count -eq 1 -and
        @(Find-UiNode $candidate '启用播放代理').Count -eq 1) {
        $fastDocument = $candidate
    }
}

if ($null -eq $fastDocument) {
    # Unknown display profiles retain a semantic, bounded fallback. Restarting
    # here also recovers cleanly when a saved coordinate no longer matches the
    # current layout after a UI change.
    Invoke-Adb @('shell', 'am', 'force-stop', 'com.mystyle.purelive') | Out-Null
    Invoke-Adb @('shell', 'monkey', '-p', 'com.mystyle.purelive', '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
    Start-Sleep -Seconds 4
    $menu = Find-ScrollableNode '菜单' 'home-menu' 1
    Tap-Node $menu
    $settings = Find-ScrollableNode '设置' 'drawer-settings' 1
    Tap-Node $settings
    $networkProxy = Find-ScrollableNode '自定义网络代理' 'settings-network-proxy' 10
    Tap-Node $networkProxy
}

# These values are deliberately fixed for the shared local test fixture. The
# phone reaches the host loopback through adb reverse, never through LAN DNS.
# The fields can be below the initial viewport, so verify them with the same
# bounded semantic scrolling used for switches instead of inspecting one dump.
if ($null -ne $fastDocument) {
    $fastSwitches = Set-SwitchesFromDocument $fastDocument $enable
    $appProxy = $fastSwitches.App
    $playerProxy = $fastSwitches.Player
} else {
    $appProxy = Set-Switch '启用应用层代理' $enable
    $playerProxy = Set-Switch '启用播放代理' $enable
}

if ($enable) {
    if ($null -ne $fastDocument) {
        $verifiedLabels = @($fastSwitches.Document.SelectNodes('//node') | ForEach-Object {
            @($_.GetAttribute('text'), $_.GetAttribute('content-desc'))
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ('127.0.0.1' -notin $verifiedLabels -or ([string]$Port) -notin $verifiedLabels) {
            throw "The enabled app proxy fields are not configured as 127.0.0.1:$Port."
        }
    } else {
        Find-ScrollableNode '127.0.0.1' 'proxy-host' 6 | Out-Null
        Find-ScrollableNode ([string]$Port) 'proxy-port' 4 | Out-Null
    }
}

if (-not $KeepAppOpen) { Invoke-Adb @('shell', 'am', 'force-stop', 'com.mystyle.purelive') | Out-Null }

$result = [ordered]@{
    serial = $Serial
    mode = $Mode
    proxyHost = '127.0.0.1'
    proxyPort = $Port
    appProxyPreviouslyEnabled = $appProxy.Previous
    playerProxyPreviouslyEnabled = $playerProxy.Previous
    appProxyEnabled = $appProxy.Current
    playerProxyEnabled = $playerProxy.Current
    reverseConfigured = $enable
    reverseRemoved = $reverseRemoved
    completedAt = [DateTime]::Now.ToString('o')
}
$summary = Join-Path $evidence 'summary.json'
$result | ConvertTo-Json | Out-File -LiteralPath $summary -Encoding utf8
Write-Output $summary
