[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_room_tag_assignment_smoke.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $errors)
if ($errors.Count) { throw ($errors | Out-String) }

foreach ($name in @('Serial', 'ApkPath', 'ExpectedApkSha256')) {
    $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }
    $attribute = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' }
    if ($null -eq $parameter -or $null -eq $attribute -or $attribute.Extent.Text -notmatch '(?i)Mandatory\s*=\s*\$true') {
        throw "Room-tag smoke must require an explicit $name parameter."
    }
}
Write-Output 'PASS room-tag smoke requires an explicit target, candidate and hash'

foreach ($name in @(
    'Invoke-Adb',
    'Get-Identity',
    'Get-PackageState',
    'Get-DeviceFileHash',
    'Assert-TargetForeground',
    'Save-UiState',
    'Find-LabeledNode',
    'Assert-VisibleBounds',
    'Open-PopularBilibili',
    'Get-RoomTarget',
    'Open-RoomDialog',
    'Set-EditorText'
)) {
    $function = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw "Room-tag smoke function is missing: $name" }
}
Write-Output 'PASS room-tag smoke exposes identity, UI, input and assertion stages'

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
    "'install', '-r', '-t', `$apk",
    'firstInstallTime',
    "stat -c '%u:%g:%a'",
    "cp '`$settingsPath' '`$remoteBackup'",
    "cat '`$remoteRestore' > '`$settingsPath'",
    'restorecon',
    'settingsFileRestoredExactly',
    'installedApkMatchesCandidate',
    'longPressDialogControlsReachable',
    'tagSelectorControlsReachable',
    'newTagAutoSelected',
    'assignmentRetainedOnReopen',
    "logcat', '--pid'",
    'noFatalOrAnr',
    "input', 'keyevent', 'KEYCODE_HOME'",
    "am', 'force-stop', `$Package",
    'bottomMost = $true'
)) {
    if (-not $source.Contains($required)) { throw "Required room-tag guard is missing: $required" }
}
foreach ($forbidden in @('adb devices', 'kill-server', 'start-server', 'reboot', 'tcpip 5555', 'settings put', 'ime set')) {
    if ($source -match [regex]::Escape($forbidden)) { throw "Forbidden device operation found: $forbidden" }
}
if ($source -match "logcat', '-c") { throw 'Room-tag smoke must preserve the process-global logcat buffer.' }
Write-Output 'PASS candidate identity, semantic route, exact restoration and cleanup guards are present'
