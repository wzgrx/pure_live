[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_audio_output_settings_smoke.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $errors)
if ($errors.Count) { throw ($errors | Out-String) }

function Find-Assignment {
    param([Parameter(Mandatory = $true)][string] $Name)
    $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq $Name
    }, $true)
}

$serialParameter = $ast.ParamBlock.Parameters | Where-Object {
    $_.Name.VariablePath.UserPath -eq 'Serial'
}
if ($null -eq $serialParameter -or
    -not ($serialParameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' })) {
    throw 'Audio-output smoke must require an explicit Serial parameter.'
}

$driversParameter = $ast.ParamBlock.Parameters | Where-Object {
    $_.Name.VariablePath.UserPath -eq 'Drivers'
}
$validateSet = $driversParameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
$acceptedDrivers = @($validateSet.PositionalArguments | ForEach-Object Value)
$expectedDrivers = @('auto', 'audiotrack', 'aaudio', 'opensles', 'null')
if (@(Compare-Object ($acceptedDrivers | Sort-Object) ($expectedDrivers | Sort-Object)).Count) {
    throw 'Audio-output smoke driver set differs from the Android product contract.'
}

$playbackProbeParameter = $ast.ParamBlock.Parameters | Where-Object {
    $_.Name.VariablePath.UserPath -eq 'PlaybackProbe'
}
if ($null -eq $playbackProbeParameter -or
    -not ($playbackProbeParameter.Attributes | Where-Object { $_.TypeName.Name -eq 'switch' })) {
    throw 'Audio-output smoke must expose an opt-in PlaybackProbe switch.'
}

$labelTable = (Find-Assignment 'expectedLabels').Right.Find({
    param($node) $node -is [Management.Automation.Language.HashtableAst]
}, $true).SafeGetValue()
$expectedLabels = [ordered]@{
    auto = 'auto (Automatic fallback)'
    audiotrack = 'audiotrack (Android AudioTrack)'
    aaudio = 'aaudio (Android 8.0+)'
    opensles = 'opensles (Legacy fallback)'
    null = 'null (No audio output)'
}
foreach ($driver in $expectedDrivers) {
    if ($labelTable[$driver] -cne $expectedLabels[$driver]) {
        throw "Audio-output smoke label differs for '$driver'."
    }
}
Write-Output 'PASS Android audio-output smoke covers the exact five product options'

foreach ($name in @(
    'Invoke-TargetAdb',
    'Get-DeviceFileHash',
    'Assert-TargetForeground',
    'Open-PlayerKernelSettings',
    'Enable-CustomOutput',
    'Assert-CustomOutputEnabled',
    'Open-AudioOutputDialog',
    'Assert-AudioOutputDialog',
    'Select-AudioOutput',
    'Save-Screenshot',
    'Invoke-AudioPlaybackProbe'
)) {
    $function = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw "Audio-output smoke function is missing: $name" }
}
Write-Output 'PASS Android audio-output smoke exposes route, selection and assertion stages'

$adbCommands = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.CommandElements.Count -gt 0 -and
    $node.CommandElements[0].Extent.Text -eq '$adb'
}, $true))
if ($adbCommands.Count -lt 2) { throw 'Expected target-bound ADB entrypoints were not found.' }
foreach ($command in $adbCommands) {
    if ($command.Extent.Text -notmatch '(?s)\$adb\s+-s\s+\$Serial\b') {
        throw "ADB command is not explicitly target-bound: $($command.Extent.Text)"
    }
}
Write-Output 'PASS every native ADB entrypoint explicitly binds the requested serial'

$source = Get-Content -LiteralPath $path -Raw -Encoding utf8
foreach ($required in @(
    'getprop ro.product.model; getprop ro.product.device; su -c id',
    '-Sequence open_player_kernel_settings -Serial $Serial',
    "stat -c '%u:%g:%a'",
    'Settings backup hash differs from device file.',
    'cat ''$remoteRestore'' > ''$dataFile''',
    'settingsRestoredExactly',
    '--pid=$appProcessId',
    'MediaCodec',
    'screenFramesChanged',
    'mediaKitLoaded',
    'fijkLoaded',
    'fijkAudioDisableOptionCount',
    'fijkAudioRenderCount',
    'activeAudioFlingerTrackCount',
    'audioTrackStartCount',
    'aaudioLineCount',
    'openSlesLineCount',
    'noFatalOrAnr',
    "input', 'keyevent', 'KEYCODE_HOME'",
    'am'', ''force-stop'', $Package'
)) {
    if (-not $source.Contains($required)) { throw "Required guard is missing: $required" }
}
foreach ($forbidden in @('adb devices', 'kill-server', 'reboot', 'tcpip 5555')) {
    if ($source -match [regex]::Escape($forbidden)) { throw "Forbidden device operation found: $forbidden" }
}
if ($source -match "logcat', '-c") { throw 'Playback probe must not clear the process-global logcat buffer.' }
Write-Output 'PASS identity, semantic route, exact backup restoration and cleanup guards are present'
