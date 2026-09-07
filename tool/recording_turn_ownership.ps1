# Read-only ownership gates shared by the recording smoke and proxy wrapper.
function Test-RecordingRuntimeIdle {
    param([AllowEmptyString()][string] $ServiceDump, [switch] $AllowPlaybackServices,
        [string] $Package = 'com.mystyle.purelive')
    if ($ServiceDump -notmatch '(?m)^\s*ACTIVITY MANAGER SERVICES\b') { return $false }
    if ($ServiceDump -match 'RecorderForegroundService') { return $false }
    $records = [regex]::Matches($ServiceDump, '(?m)^\s*\* ServiceRecord\{[^\r\n]+\}')
    if ($records.Count -eq 0) {
        return $ServiceDump -notmatch 'ServiceRecord|Active services|Pending services|Restarting services|Destroying services' -and
            $ServiceDump -match '(?m)^\s*\(nothing\)\s*$'
    }
    # Only the known playback service is eligible, not arbitrary background work.
    if (-not $AllowPlaybackServices.IsPresent) { return $false }
    $known = '\bu0 ' + [regex]::Escape($Package) + '/com\.ryanheise\.audioservice\.AudioService\}'
    return @($records | Where-Object { $_.Value -notmatch $known }).Count -eq 0
}

function Assert-AndroidRecordingRuntimeIdle {
    param([Parameter(Mandatory)] $Adb, [string] $Serial,
        [string] $Package = 'com.mystyle.purelive')
    if ([string]::IsNullOrWhiteSpace($Serial)) { throw 'An explicit ADB serial is required.' }
    $model = & $Adb -s $Serial shell getprop ro.product.model 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Device identity observation failed.' }
    $device = & $Adb -s $Serial shell getprop ro.product.device 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Device identity observation failed.' }
    if (($model -join '').Trim() -cne '25102RKBEC' -or ($device -join '').Trim() -cne 'myron') {
        throw 'Device identity mismatch; existing runtime preserved.'
    }
    $services = & $Adb -s $Serial shell dumpsys activity services $Package 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-RecordingRuntimeIdle -ServiceDump ($services -join "`n"))) {
        throw 'Existing or uncertain app services; preserve runtime and defer this recording turn.'
    }
}

function Assert-RecordingStartAvailable {
    param([Parameter(Mandatory)][string] $Xml)
    [xml] $document = $Xml
    foreach ($semantic in @('立即启动录制', '停止录制', '取消监控')) {
        $nodes = @($document.SelectNodes('//node') | Where-Object {
            $_.GetAttribute('content-desc') -ceq $semantic -or $_.GetAttribute('text') -ceq $semantic
        })
        if ($nodes.Count -ne 1) { throw "Ambiguous recording ownership control: $semantic" }
        $expected = if ($semantic -ceq '立即启动录制') { 'true' } else { 'false' }
        if ($nodes[0].GetAttribute('enabled') -cne $expected -or
            $nodes[0].GetAttribute('clickable') -cne $expected) {
            throw 'Existing monitor or uncertain recording state; preserve it and defer this turn.'
        }
    }
}

function Stop-OwnedRecordingTurnProcess {
    param([bool] $StartOwned, [bool] $MonitorRemoved, [Parameter(Mandatory)][scriptblock] $Invoke,
        [string] $Package = 'com.mystyle.purelive')
    # Neither a failed preflight nor an unfinished/other recording grants a stop.
    if (-not $StartOwned) { return 'preserved-unowned' }
    if (-not $MonitorRemoved) { return 'preserved-monitor-cleanup-pending' }
    try {
        $services = (& $Invoke @('shell', 'dumpsys', 'activity', 'services', $Package)) -join "`n"
    } catch { return 'preserved-service-observation-failed' }
    if (-not (Test-RecordingRuntimeIdle -ServiceDump $services -AllowPlaybackServices -Package $Package)) {
        return 'preserved-active-or-uncertain-services'
    }
    try {
        & $Invoke @('shell', 'am', 'force-stop', $Package) | Out-Null
        return 'stop-sent'
    } catch { return 'stop-result-uncertain' }
}
