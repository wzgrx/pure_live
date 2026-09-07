$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_recording_smoke.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$platformParameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Platform' }
$attribute = $platformParameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
$accepted = @($attribute.PositionalArguments | ForEach-Object Value)
function Find-Assignment([string]$Name) {
 $ast.Find({param($node)
  $node -is [Management.Automation.Language.AssignmentStatementAst] -and
  $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
  $node.Left.VariablePath.UserPath -eq $Name
 }, $true)
}
$labelAssignment = Find-Assignment 'platformLabels'
$table = $labelAssignment.Right.Find({param($n) $n -is [Management.Automation.Language.HashtableAst]}, $true).SafeGetValue()
$capability = (Find-Assignment 'danmakuSupported').Right.Extent.Text
$expected = @('bilibili','douyu','huya','douyin','kuaishou','cc','twitch','soop','yy','acfun','picarto')
if (@(Compare-Object ($accepted | Sort-Object) ($expected | Sort-Object)).Count) { throw 'Accepted platform set differs from the recording matrix' }
if (@(Compare-Object (@($table.Keys) | Sort-Object) ($expected | Sort-Object)).Count) { throw 'Platform labels and accepted input differ' }
foreach ($Platform in $expected) {
 $supported = & ([scriptblock]::Create($capability))
 if ($supported -ne ($Platform -notin @('cc','acfun','picarto'))) { throw "Incorrect remote chat capability for $Platform" }
 if ([string]::IsNullOrWhiteSpace($table[$Platform])) { throw "Missing platform label for $Platform" }
 Write-Host "PASS $Platform label/chat contract"
}
$translations = Get-Content (Join-Path $PSScriptRoot '../assets/translations/zh.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($table['acfun'] -ne $translations.site_acfun) { throw 'AcFun navigation label differs from the actual translation' }
Write-Host 'PASS AcFun localized label'
$qualityPattern = (Find-Assignment 'qualityLabelPattern').Right.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]}, $true).SafeGetValue()
foreach ($label in @('720p 60fps', '1080p 59.94fps', 'HLS Auto', 'HLS 3.7 Mbps', '720p60', '原画')) {
 if ($label -notmatch $qualityPattern) { throw "Missing quality label: $label" }
}
if ('a random 720p 60fps sentence' -match $qualityPattern) { throw 'Quality labels must be anchored' }
Write-Host 'PASS Picarto declared HLS quality labels'

. (Join-Path $PSScriptRoot 'recording_smoke_coverage.ps1')
$checks = [ordered]@{
 runningFileGrowthObserved = $true
 screenOffConfirmed = $true
 screenOffRecordingContinued = $false
 processAliveDuringScreenOff = $true
 roomRestoredAfterScreenOff = $true
 qualitySwitchCommitted = $true
 qualitySwitchStable = $false
 lineSwitchCommitted = $true
 lineSwitchStable = $true
}
$skipped = Get-RecordingSmokeAssertionResults -Assertions $checks
if ($skipped.runningFileGrowthObserved -ne 'PASS' -or $skipped.screenOffConfirmed -ne 'SKIP' -or $skipped.qualitySwitchStable -ne 'SKIP') {
 throw 'Disabled optional scenarios must not be counted as executed passes/failures'
}
$executed = Get-RecordingSmokeAssertionResults -Assertions $checks -ScreenOffSeconds 60 -ExerciseStreamSelection $true -QualityOptionCount 3 -LineOptionCount 2
if ($executed.screenOffRecordingContinued -ne 'FAIL' -or $executed.qualitySwitchStable -ne 'FAIL' -or $executed.lineSwitchStable -ne 'PASS') {
 throw 'Executed scenario results must preserve real assertion failures'
}
$single = Get-RecordingSmokeAssertionResults -Assertions $checks -ExerciseStreamSelection $true -QualityOptionCount 1 -LineOptionCount 1
if ($single.qualitySwitchCommitted -ne 'SKIP' -or $single.lineSwitchCommitted -ne 'SKIP') {
 throw 'Single-option platforms do not prove a stream switch'
}
if ($checks.screenOffRecordingContinued -ne $false) { throw 'Coverage must not mutate legacy assertions' }
Write-Host 'PASS optional recording coverage distinguishes PASS / FAIL / SKIP'

. (Join-Path $PSScriptRoot 'recorder_background_snapshot.ps1')
$services = @'
  * ServiceRecord{111 u0 com.mystyle.purelive/.RecorderForegroundService}
    isForeground=true foregroundId=20260906
  * ServiceRecord{222 u0 com.mystyle.purelive/com.ryanheise.audioservice.AudioService}
    isForeground=false
'@
$power = @'
Wake Locks: size=1
  PARTIAL_WAKE_LOCK 'com.mystyle.purelive:recording' ACQ=+1s
Suspend Blockers: size=1
'@
$actual = Get-RecorderBackgroundSnapshot -Services $services -Power $power
if (-not $actual.recorderForeground -or $actual.audioForeground -or -not $actual.recorderCpuLockHeld) {
 throw 'Independent recorder snapshot must distinguish recording from playback ownership'
}
$missing = Get-RecorderBackgroundSnapshot -Services '' -Power "Wake Locks: size=0`nSuspend Blockers: size=1`nHistorical com.mystyle.purelive:recording"
if ($missing.recorderForeground -or $missing.recorderCpuLockHeld -or $missing.recorderServicePresent) {
 throw 'Missing services or historical wake events must not prove current ownership'
}
$playback = Get-RecorderBackgroundSnapshot -Services "  * ServiceRecord{222 u0 com.mystyle.purelive/com.ryanheise.audioservice.AudioService}`n    isForeground=true`n" -Power ''
if ($playback.recorderForeground -or -not $playback.audioForeground) { throw 'Playback-only foreground must not prove recording protection' }
Write-Host 'PASS independent recording foreground and current lock parser'
