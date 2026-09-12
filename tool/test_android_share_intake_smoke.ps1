[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_share_intake_smoke.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $errors)
if ($errors.Count) { throw ($errors | Out-String) }

foreach ($name in @('Serial', 'ApkPath', 'ExpectedApkSha256')) {
    $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }
    $attribute = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' }
    if ($null -eq $parameter -or $null -eq $attribute -or $attribute.Extent.Text -notmatch '(?i)Mandatory\s*=\s*\$true') {
        throw "Share-intake smoke must require an explicit $name parameter."
    }
}
Write-Output 'PASS share-intake smoke requires an explicit target, candidate and hash'

foreach ($name in @(
    'Invoke-Adb',
    'Get-Identity',
    'Get-DeviceFileHash',
    'Get-PackageState',
    'Get-TopPackage',
    'Assert-TargetForeground',
    'Save-UiState',
    'Find-LabeledNode',
    'Test-ShareDialog',
    'Wait-ShareDialog',
    'Wait-ShareDialogClosed',
    'Close-ShareDialog',
    'Assert-DialogBounds',
    'Start-ShareTextIntent',
    'Get-TreeManifest',
    'Assert-TreeManifestEqual',
    'Copy-RootFileToHost',
    'Get-ProcessLog'
)) {
    $function = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw "Share-intake smoke function is missing: $name" }
}
Write-Output 'PASS share-intake smoke exposes identity, state backup, semantic UI and database evidence stages'

$adbCommands = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
    $node.CommandElements.Count -gt 0 -and
    $node.CommandElements[0].Extent.Text -eq '$adb'
}, $true))
if ($adbCommands.Count -lt 1) { throw 'Expected target-bound ADB entrypoints were not found.' }
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
    "tar -C '`$pureLiveRoot' -cpf '`$remoteCacheBackup' IPTV_CACHE",
    'IPTV cache cleanup target guard rejected the path.',
    "rm -rf '`$iptvCachePath'",
    "restorecon -RF '`$iptvCachePath'",
    "cat '`$remoteSettingsRestore' > '`$settingsPath'",
    'iptvCacheRestoredExactly',
    'settingsFileRestoredExactly',
    'installedApkMatchesCandidate',
    'coldShareCommandAcceptedAfterSplash',
    'warmShareCommandAccepted',
    'duplicateWarmShareSuppressed',
    'sharedPlaylistAttachmentImported',
    'sharedMediaStagingCleaned',
    "'android.intent.action.SEND'",
    "'android.intent.extra.TEXT'",
    "'android.intent.extra.STREAM'",
    "'application/x-mpegURL'",
    'content://$Package.fileProvider/cache-path/',
    "logcat', '--pid'",
    'noFatalOrAnr',
    'EXCEPTION CAUGHT BY (?:RENDERING|WIDGETS) LIBRARY',
    "input', 'keyevent', 'KEYCODE_HOME'",
    "am', 'force-stop', `$Package"
)) {
    if (-not $source.Contains($required)) { throw "Required share-intake guard is missing: $required" }
}
foreach ($forbidden in @('adb devices', 'kill-server', 'start-server', 'reboot', 'tcpip 5555', 'settings put', 'ime set')) {
    if ($source -match [regex]::Escape($forbidden)) { throw "Forbidden device operation found: $forbidden" }
}
if ($source -match "logcat', '-c") { throw 'Share-intake smoke must preserve the process-global logcat buffer.' }
Write-Output 'PASS cold/warm/file share coverage, exact restoration and cleanup guards are present'
