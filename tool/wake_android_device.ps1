[CmdletBinding()]
param(
    [string]$Serial,
    [string]$PairEndpoint = $env:PURELIVE_ADB_PAIR_ENDPOINT,
    [string]$PairCode = $env:PURELIVE_ADB_PAIR_CODE,
    [string]$ConnectEndpoint = $env:PURELIVE_ADB_CONNECT_ENDPOINT,
    [switch]$StayAwake,
    [switch]$ReleaseStayAwake
)

$ErrorActionPreference = 'Stop'
$adbCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
)
$adb = $adbCandidates | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ -PathType Leaf }
    else { [bool](Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

function Get-AdbDeviceRows {
    @(& $adb devices | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+(device|offline|unauthorized)\b') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    })
}

function Invoke-AdbTransportCommand([string[]]$Arguments) {
    $output = & $adb @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb transport command failed ($LASTEXITCODE): $($Arguments[0])`n$($output -join "`n")"
    }
    @($output)
}

$rows = @(Get-AdbDeviceRows)
if (-not ($rows | Where-Object State -eq 'device')) {
    if (-not [string]::IsNullOrWhiteSpace($PairEndpoint) -and
        -not [string]::IsNullOrWhiteSpace($PairCode)) {
        $pairOutput = Invoke-AdbTransportCommand -Arguments @('pair', $PairEndpoint, $PairCode)
        if (-not (($pairOutput -join "`n") -match '(?i)successfully paired|already paired')) {
            throw "Android wireless pairing did not report success: $($pairOutput -join "`n")"
        }
    }

    $connectCandidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ConnectEndpoint)) {
        $connectCandidates.Add($ConnectEndpoint)
    }

    $pairHost = if ($PairEndpoint -match '^([^:]+):\d+$') { $Matches[1] } else { $null }
    $mdnsOutput = @(& $adb mdns services 2>&1)
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in $mdnsOutput) {
            if ($line -notmatch '_adb-tls-connect\._tcp') { continue }
            $matches = [regex]::Matches($line, '(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3}:\d+)')
            foreach ($match in $matches) {
                $candidate = $match.Groups[1].Value
                if ($pairHost -and -not $candidate.StartsWith("${pairHost}:")) { continue }
                if (-not $connectCandidates.Contains($candidate)) {
                    $connectCandidates.Add($candidate)
                }
            }
        }
    }

    foreach ($candidate in $connectCandidates) {
        $connectOutput = @(& $adb connect $candidate 2>&1)
        if ($LASTEXITCODE -eq 0 -and
            (($connectOutput -join "`n") -match '(?i)connected to|already connected')) {
            Start-Sleep -Milliseconds 300
            $rows = @(Get-AdbDeviceRows)
            if ($rows | Where-Object State -eq 'device') { break }
        }
    }
    if (-not ($rows | Where-Object State -eq 'device')) {
        Start-Sleep -Milliseconds 500
        $rows = @(Get-AdbDeviceRows)
    }
}
if ([string]::IsNullOrWhiteSpace($Serial)) {
    $ready = @($rows | Where-Object State -eq 'device')
    $ipv4 = @($ready | Where-Object Serial -Match '^\d{1,3}(?:\.\d{1,3}){3}:\d+$')
    if ($ipv4.Count -eq 1) { $Serial = $ipv4[0].Serial }
    elseif ($ready.Count -eq 1) { $Serial = $ready[0].Serial }
    else { throw "Expected one ready Android target (prefer one IPv4 target), found $($ready.Count)." }
}
if (-not ($rows | Where-Object { $_.Serial -eq $Serial -and $_.State -eq 'device' })) {
    throw "Android target is not ready: $Serial"
}

function Invoke-TargetAdb([string[]]$Arguments) {
    $output = & $adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    @($output)
}

if ($StayAwake -and $ReleaseStayAwake) {
    throw 'StayAwake and ReleaseStayAwake are mutually exclusive.'
}
if ($ReleaseStayAwake) {
    Invoke-TargetAdb -Arguments @('shell', 'svc', 'power', 'stayon', 'false') | Out-Null
    [pscustomobject]@{
        Serial = $Serial
        Awake = $null
        KeyguardDismissed = $null
        StayAwake = $false
    } | ConvertTo-Json -Compress
    exit 0
}

Invoke-TargetAdb -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
Invoke-TargetAdb -Arguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
Start-Sleep -Milliseconds 250
$policy = (Invoke-TargetAdb -Arguments @('shell', 'dumpsys', 'window', 'policy')) -join "`n"
$locked = $policy -match '(?im)(?:mShowingLockscreen|mKeyguardShowing|isKeyguardShowing|keyguardShowing|mDreamingLockscreen|isStatusBarKeyguard)\s*=\s*true'
if ($locked) {
    $size = (Invoke-TargetAdb -Arguments @('shell', 'wm', 'size')) -join "`n"
    if ($size -notmatch '(\d+)x(\d+)') { throw "Unexpected device size output: $size" }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    Invoke-TargetAdb -Arguments @(
        'shell', 'input', 'swipe',
        [math]::Round($width * 0.5), [math]::Round($height * 0.84),
        [math]::Round($width * 0.5), [math]::Round($height * 0.24), '350'
    ) | Out-Null
    Start-Sleep -Milliseconds 350
    Invoke-TargetAdb -Arguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

$finalPolicy = (Invoke-TargetAdb -Arguments @('shell', 'dumpsys', 'window', 'policy')) -join "`n"
$stillLocked = $finalPolicy -match '(?im)(?:mShowingLockscreen|mKeyguardShowing|isKeyguardShowing|keyguardShowing|mDreamingLockscreen|isStatusBarKeyguard)\s*=\s*true'
if ($stillLocked) { throw "Android target remained keyguard-locked after wake: $Serial" }

if ($StayAwake) {
    # `true` maps to AC/USB/wireless power sources. The device-test wrapper
    # always releases it in finally, preserving the user's 10-minute policy.
    Invoke-TargetAdb -Arguments @('shell', 'svc', 'power', 'stayon', 'true') | Out-Null
}

[pscustomobject]@{
    Serial = $Serial
    Awake = $true
    KeyguardDismissed = $true
    StayAwake = [bool]$StayAwake
} | ConvertTo-Json -Compress
