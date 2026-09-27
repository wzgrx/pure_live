[CmdletBinding()]
param(
    [string] $Serial,
    [string] $EvidenceDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$evidence = if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    Join-Path $repo (
        'local-artifacts\diagnostics\android-yy-network-{0}' -f
        [DateTime]::Now.ToString('yyyyMMddTHHmmssfff')
    )
} elseif ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    $EvidenceDirectory
} else {
    Join-Path $repo $EvidenceDirectory
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

$devices = @(
    & $adb devices | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+(device|offline|unauthorized)\b') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
)
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $ready = @($devices | Where-Object State -eq 'device')
    $network = @($ready | Where-Object Serial -Match '^\d{1,3}(?:\.\d{1,3}){3}:\d+$')
    if ($network.Count -eq 1) { $Serial = $network[0].Serial }
    elseif ($ready.Count -eq 1) { $Serial = $ready[0].Serial }
    else { throw "Expected one ready Android device; found $($ready.Count)." }
}
if (-not ($devices | Where-Object { $_.Serial -eq $Serial -and $_.State -eq 'device' })) {
    throw "Android target is not ready: $Serial"
}

function Invoke-AdbText {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    $output = & $adb -s $Serial @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n").Trim()
    }
}

function Invoke-ShellProbe {
    param([Parameter(Mandatory = $true)][string] $Command)
    # Pass the complete expression as one adb-shell argument. Supplying
    # `sh`, `-c`, and the expression as separate adb arguments lets adb rebuild
    # the remote command without the required quoting; only the first token is
    # then treated as the `-c` script and the probe can report a false success.
    Invoke-AdbText -Arguments @('shell', $Command)
}

$hosts = @(
    'h5-sinchl.yy.com',
    'h5chl.yy.com',
    'h5svc.yy.com',
    'h5gw.yy.com',
    'stream-manager.yy.com',
    'www.yy.com'
)

$result = [ordered]@{
    schemaVersion = 1
    capturedAt = [DateTimeOffset]::Now.ToString('o')
    serial = $Serial
    device = [ordered]@{
        model = (Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.product.model')).Output
        sdk = (Invoke-AdbText -Arguments @('shell', 'getprop', 'ro.build.version.sdk')).Output
        privateDnsMode = (Invoke-AdbText -Arguments @('shell', 'settings', 'get', 'global', 'private_dns_mode')).Output
        privateDnsSpecifier = (Invoke-AdbText -Arguments @('shell', 'settings', 'get', 'global', 'private_dns_specifier')).Output
        httpProxy = (Invoke-AdbText -Arguments @('shell', 'settings', 'get', 'global', 'http_proxy')).Output
        proxyEnvironment = (Invoke-ShellProbe -Command 'env | grep -i ''proxy'' || true').Output
        routes = (Invoke-AdbText -Arguments @('shell', 'ip', 'route')).Output
    }
    tools = [ordered]@{
        ncHelp = (Invoke-ShellProbe -Command 'toybox nc --help 2>&1 | head -n 20').Output
        curl = (Invoke-ShellProbe -Command 'command -v curl || true').Output
    }
    hosts = [ordered]@{}
}

foreach ($hostName in $hosts) {
    $dns = Invoke-ShellProbe -Command ("getent hosts {0} 2>&1 || nslookup {0} 2>&1 || true" -f $hostName)
    $ping = Invoke-ShellProbe -Command ("ping -c 1 -W 3 {0} 2>&1; echo __exit=`$?" -f $hostName)
    $tcp = Invoke-ShellProbe -Command ("toybox nc -z -w 8 {0} 443 >/dev/null 2>&1; echo __exit=`$?" -f $hostName)
    $https = Invoke-ShellProbe -Command (
        'if command -v curl >/dev/null 2>&1; then ' +
        ('curl --noproxy "*" -k -sS -I --connect-timeout 8 --max-time 12 ' +
        'https://{0}/websocket 2>&1 | head -n 20; echo __exit=$?; ' -f $hostName) +
        'else echo curl_unavailable; fi'
    )
    $result.hosts[$hostName] = [ordered]@{
        dns = $dns.Output
        ping = $ping.Output
        tcp443 = $tcp.Output
        httpsHead = $https.Output
    }
}

$webSocketUpgrade = Invoke-ShellProbe -Command (
    'curl --noproxy "*" -k -sS -D - --http1.1 --connect-timeout 8 --max-time 12 ' +
    '-H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" ' +
    '-H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Origin: https://www.yy.com" ' +
    '-H "User-Agent: Mozilla/5.0" https://h5-sinchl.yy.com/websocket -o /dev/null 2>&1; ' +
    'echo __exit=$?'
)
$result.webSocketUpgrade = $webSocketUpgrade.Output
$verifiedTls = Invoke-ShellProbe -Command (
    'curl --noproxy "*" -sS -v --http1.1 --connect-timeout 8 --max-time 12 ' +
    'https://h5-sinchl.yy.com/websocket -o /dev/null 2>&1; echo __exit=$?'
)
$result.verifiedTls = $verifiedTls.Output
$verifiedWebSocketUpgrade = Invoke-ShellProbe -Command (
    'curl --noproxy "*" -sS -D - --http1.1 --connect-timeout 8 --max-time 12 ' +
    '-H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" ' +
    '-H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Origin: https://www.yy.com" ' +
    '-H "User-Agent: Mozilla/5.0" https://h5-sinchl.yy.com/websocket -o /dev/null 2>&1; ' +
    'echo __exit=$?'
)
$result.verifiedWebSocketUpgrade = $verifiedWebSocketUpgrade.Output
$result.sinchlEdges = [ordered]@{}
foreach ($edgeAddress in @('36.27.211.128', '150.139.143.33', '183.60.143.13')) {
    $edgeProbe = Invoke-ShellProbe -Command (
        'curl --noproxy "*" -sS -D - --http1.1 --connect-timeout 8 --max-time 12 ' +
        ("--resolve h5-sinchl.yy.com:443:{0} " -f $edgeAddress) +
        '-H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" ' +
        '-H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Origin: https://www.yy.com" ' +
        '-H "User-Agent: Mozilla/5.0" https://h5-sinchl.yy.com/websocket -o /dev/null 2>&1; ' +
        'echo __exit=$?'
    )
    $result.sinchlEdges[$edgeAddress] = $edgeProbe.Output
}

$packageFiles = Invoke-ShellProbe -Command (
    'run-as com.mystyle.purelive sh -c ''find . -maxdepth 4 -type f 2>/dev/null | ' +
    'grep -E "app_settings|hive|proxy" | sort'' 2>&1 || true'
)
$result.pureLiveSettingFiles = $packageFiles.Output
$settingStrings = Invoke-ShellProbe -Command (
    'run-as com.mystyle.purelive sh -c ''for f in ' +
    './app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive ./app_flutter/pure_live/app_settings.hive; do ' +
    'if [ -f "$f" ]; then echo "---$f---"; strings "$f" | ' +
    'grep -i -E "proxy|127\\.0\\.0\\.1|localhost|7897|1080" -A 3 -B 3 || true; fi; done'' 2>&1 || true'
)
$result.pureLiveSettingStrings = $settingStrings.Output

$summaryPath = Join-Path $evidence 'summary.json'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Output $summaryPath
