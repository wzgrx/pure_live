[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'recording_turn_ownership.ps1')
$script:caseCount = 0
function Check($Actual, $Expected, [string] $Name) {
    if ($Actual -cne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'" }
    $script:caseCount++
}
function Throws([scriptblock] $Body, [string] $Pattern) {
    $message = ''
    try { & $Body | Out-Null } catch { $message = $_.Exception.Message }
    if ($message -notmatch $Pattern) { throw "Expected '$Pattern', got '$message'" }
    $script:caseCount++
}
$idle = "ACTIVITY MANAGER SERVICES (dumpsys activity services)`n  (nothing)`n"
$recorder = "ACTIVITY MANAGER SERVICES`n  * ServiceRecord{123 u0 com.mystyle.purelive/.RecorderForegroundService}`n    isForeground=false"
$playback = "ACTIVITY MANAGER SERVICES`n  * ServiceRecord{456 u0 com.mystyle.purelive/com.ryanheise.audioservice.AudioService}`n    isForeground=true"
foreach ($case in @(
    @{Dump=$idle; Entry=$true; Cleanup=$true},
    @{Dump=$recorder; Entry=$false; Cleanup=$false},
    @{Dump=$recorder.Replace('false','true'); Entry=$false; Cleanup=$false},
    @{Dump=$playback; Entry=$false; Cleanup=$true},
    @{Dump=$playback.Replace('com.ryanheise.audioservice.AudioService','example.OtherService'); Entry=$false; Cleanup=$false},
    @{Dump=$playback.Replace('u0','u10'); Entry=$false; Cleanup=$false},
    @{Dump=''; Entry=$false; Cleanup=$false},
    @{Dump='error: device offline'; Entry=$false; Cleanup=$false},
    @{Dump='(nothing)'; Entry=$false; Cleanup=$false},
    @{Dump="ACTIVITY MANAGER SERVICES`n * ServiceRecord invalid`n(nothing)"; Entry=$false; Cleanup=$false},
    @{Dump="ACTIVITY MANAGER SERVICES`n Pending services:`n(nothing)"; Entry=$false; Cleanup=$false}
)) {
    Check (Test-RecordingRuntimeIdle $case.Dump) $case.Entry 'entry services gate'
    Check (Test-RecordingRuntimeIdle $case.Dump -AllowPlaybackServices) $case.Cleanup 'cleanup services gate'
}

$new = '<hierarchy><node text="立即启动录制" enabled="true" clickable="true"/><node content-desc="停止录制" enabled="false" clickable="false"/><node text="取消监控" enabled="false" clickable="false"/></hierarchy>'
Assert-RecordingStartAvailable $new
Check $true $true 'new monitor permits one start'
foreach ($xml in @(
    $new.Replace('enabled="false"','enabled="true"'),
    $new.Replace('取消监控" enabled="false" clickable="false"','取消监控" enabled="true" clickable="true"'),
    $new.Replace('停止录制','missing'),
    $new.Replace('</hierarchy>','<node text="取消监控" enabled="false" clickable="false"/></hierarchy>'),
    $new.Replace('clickable="false"','clickable=""'),
    $new.Replace('enabled="false"','enabled="False"'),
    $new.Replace('enabled="true"','enabled="false"')
)) { Throws { Assert-RecordingStartAvailable $xml } 'Existing|Ambiguous' }

$script:calls = [Collections.Generic.List[string]]::new()
$script:dump = $idle
$script:fail = $false
$invoke = {
    param([string[]] $Arguments)
    $command = $Arguments -join ' '
    $script:calls.Add($command)
    if ($script:fail) { throw 'observation failed' }
    if ($command -eq 'shell dumpsys activity services com.mystyle.purelive') { $script:dump }
    elseif ($command -ne 'shell am force-stop com.mystyle.purelive') { throw "Unexpected command: $command" }
}
Check (Stop-OwnedRecordingTurnProcess -StartOwned $false -MonitorRemoved $true -Invoke $invoke) 'preserved-unowned' 'failed preflight keeps user process'
Check $script:calls.Count 0 'unowned cleanup has zero commands'
Check (Stop-OwnedRecordingTurnProcess -StartOwned $true -MonitorRemoved $false -Invoke $invoke) 'preserved-monitor-cleanup-pending' 'unfinished own monitor retained'
Check $script:calls.Count 0 'unfinished cleanup has zero commands'
foreach ($dump in @($idle, $playback)) {
    $script:dump = $dump; $script:calls.Clear()
    Check (Stop-OwnedRecordingTurnProcess -StartOwned $true -MonitorRemoved $true -Invoke $invoke) 'stop-sent' 'completed own turn cleanup'
    Check $script:calls.Count 2 'observe then stop only'
    Check $script:calls[1] 'shell am force-stop com.mystyle.purelive' 'exact package stop'
}
foreach ($dump in @($recorder, '', 'error: closed', $playback.Replace('com.ryanheise.audioservice.AudioService','example.OtherService'))) {
    $script:dump = $dump; $script:calls.Clear()
    Check (Stop-OwnedRecordingTurnProcess -StartOwned $true -MonitorRemoved $true -Invoke $invoke) 'preserved-active-or-uncertain-services' 'another recording or unknown runtime retained'
    Check $script:calls.Count 1 'no stop after uncertain observation'
}
$script:fail = $true; $script:calls.Clear()
Check (Stop-OwnedRecordingTurnProcess -StartOwned $true -MonitorRemoved $true -Invoke $invoke) 'preserved-service-observation-failed' 'transport failure retained'
Check $script:calls.Count 1 'failed observation not replayed'
$script:calls.Clear()
$failedStop = {
    param([string[]] $Arguments)
    $script:calls.Add(($Arguments -join ' '))
    if ($Arguments[1] -eq 'dumpsys') { $idle } else { throw 'stop result lost' }
}
Check (Stop-OwnedRecordingTurnProcess -StartOwned $true -MonitorRemoved $true -Invoke $failedStop) 'stop-result-uncertain' 'failed stop may have reached Android'
Check $script:calls.Count 2 'uncertain stop is neither replayed nor reported as preserved'

$script:fakeModel = '25102RKBEC'; $script:fakeDevice = 'myron'
$script:dump = $idle; $script:failedProperty = ''
$fakeAdb = {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]] $Arguments)
    $script:calls.Add(($Arguments -join ' ')); $global:LASTEXITCODE = 0
    if ($Arguments[0] -cne '-s' -or $Arguments[1] -cne '192.0.2.10:5555') { throw 'Wrong transport' }
    switch ($Arguments[4]) {
        'ro.product.model' { $script:fakeModel }
        'ro.product.device' { $script:fakeDevice }
        'activity' { $script:dump }
        default { throw 'Unexpected ADB command' }
    }
    if ($Arguments[4] -eq $script:failedProperty) { $global:LASTEXITCODE = 1 }
}
$script:calls.Clear()
Throws { Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '' } 'explicit ADB serial'
Check $script:calls.Count 0 'no target discovery'
Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '192.0.2.10:5555'
Check $script:calls.Count 3 'verified identity and idle services only'
foreach ($field in @('model','device')) {
    $script:fakeModel = '25102RKBEC'; $script:fakeDevice = 'myron'; $script:calls.Clear()
    if ($field -eq 'model') { $script:fakeModel = 'other' } else { $script:fakeDevice = 'other' }
    Throws { Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '192.0.2.10:5555' } 'identity mismatch'
    Check $script:calls.Count 2 'mismatch does not query services or mutate'
}
$script:fakeModel = '25102RKBEC'; $script:fakeDevice = 'myron'
foreach ($dump in @($recorder, $playback, '')) {
    $script:dump = $dump; $script:calls.Clear()
    Throws { Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '192.0.2.10:5555' } 'Existing or uncertain'
    Check $script:calls.Count 3 'busy wrapper never configures proxy'
}
$script:dump = $idle; $script:failedProperty = 'activity'
Throws { Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '192.0.2.10:5555' } 'Existing or uncertain'
foreach ($field in @('ro.product.model', 'ro.product.device')) {
    $script:failedProperty = $field
    Throws { Assert-AndroidRecordingRuntimeIdle -Adb $fakeAdb -Serial '192.0.2.10:5555' } 'identity observation failed'
}

# Parse the production entrypoints without invoking either device script.
function Parse([string] $Name) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $Name), [ref]$null, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    return $ast
}
$smoke = Parse 'android_recording_smoke.ps1'
$foreign = Parse 'android_foreign_recording_smoke.ps1'
$mainTry = @($smoke.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })[-1]
$main = $mainTry.Body.Extent.Text
$start = $main.IndexOf('Assert-RecordingStartAvailable')
$tap = $main.IndexOf("Invoke-Ui -Action TapSemantic -Value '立即启动录制'")
Check ($start -ge 0 -and $tap -gt $start) $true 'ownership gate before start'
Check ($main.Substring(0,$tap) -match "TapSemantic -Value '(停止录制|取消监控)'") $false 'no preflight monitor stop or cancellation'
Check ($main.IndexOf('Test-RecordingRuntimeIdle') -lt $main.IndexOf('Wake-AndDismissKeyguard')) $true 'idle gate before wake/navigation'
Check ($main.IndexOf('$script:recordingStartOwned = $true') -gt $start -and $main.IndexOf('$script:recordingStartOwned = $true') -lt $tap) $true 'start ownership set before uncertain input result'
Check ($mainTry.Finally.Extent.Text -match 'Stop-OwnedRecordingTurnProcess') $true 'final cleanup uses ownership gate'
Check ($smoke.Extent.Text -match "'force-stop'") $false 'no direct unguarded stop in smoke'
$outerTry = @($foreign.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })[-1]
Check ($outerTry.Body.Extent.Text.IndexOf('Assert-AndroidRecordingRuntimeIdle') -lt $outerTry.Body.Extent.Text.IndexOf('& $configure')) $true 'outer idle gate before proxy writes'
$restore = $outerTry.Finally.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.CommandElements[0].Extent.Text -eq '$restore'}, $true)
Check (@($restore.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'KeepAppOpen' }).Count) 1 'outer restore never force-stops retained process'
Write-Output "PASS $script:caseCount recording turn ownership assertions; fake ADB only, no phone operations."
