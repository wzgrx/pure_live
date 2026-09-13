[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot 'android_documentsui_share_smoke.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref] $tokens, [ref] $errors)
if ($errors.Count) { throw ($errors | Out-String) }

foreach ($name in @('Serial', 'ApkPath', 'ExpectedApkSha256', 'BuildMode')) {
    $parameter = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }
    $attribute = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' }
    if ($null -eq $parameter -or $null -eq $attribute -or $attribute.Extent.Text -notmatch '(?i)Mandatory\s*=\s*\$true') {
        throw "DocumentsUI share smoke must require an explicit $name parameter."
    }
}
Write-Output 'PASS DocumentsUI smoke requires an explicit target, Release candidate and hash'

foreach ($name in @(
    'Invoke-Adb',
    'Get-Identity',
    'Get-DeviceFileHash',
    'Get-PackageState',
    'Get-PackageUid',
    'Get-TopPackage',
    'Wait-TopPackage',
    'Save-UiState',
    'Find-LabeledNode',
    'Get-ClickableAncestor',
    'Invoke-TapNode',
    'Invoke-LongPressNode',
    'Wait-SelectionCount',
    'Get-SharedStagingEntries',
    'Wait-SharedStagingEmpty',
    'Get-TreeManifest',
    'Assert-TreeManifestEqual',
    'Copy-RootFileToHost',
    'Get-ProcessLog',
    'Test-ExternalUriGrant'
)) {
    $function = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw "DocumentsUI share smoke function is missing: $name" }
}
Write-Output 'PASS DocumentsUI smoke exposes identity, semantic UI, URI grant, database and restoration stages'

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
    "[ValidateSet('Release')]",
    'getprop ro.product.model; getprop ro.product.device; su -c id',
    "'install', '-r', '-t', `$apk",
    'firstInstallTime',
    'senderUsesIndependentPackageAndUid',
    'com.google.android.documentsui/com.android.documentsui.files.FilesActivity',
    'content://com.android.externalstorage.documents/document/',
    "'android.intent.action.VIEW'",
    'com.google.android.documentsui:id/action_bar_title',
    'com.google.android.documentsui:id/action_menu_share',
    'documentsUiSelectedTwoFiles',
    'documentsUiLaunchedChooser',
    'pureLiveListedInChooser',
    "'dumpsys', 'activity', 'permissions'",
    'content://com\.android\.externalstorage\.documents',
    'android\.intent\.action\.SEND_MULTIPLE',
    'externalDocumentsProviderUrisGranted',
    'sourcePkg=com\.android\.externalstorage',
    'targetPkg=$([regex]::Escape($Package))',
    'playlistToTarget',
    'epgToTarget',
    'uiProducedSendMultipleIntent',
    'uiDrivenMultipleShareImported',
    'SELECT id, name, type FROM providers WHERE name = ?',
    'SELECT id, name FROM epg_sources WHERE name = ?',
    'SELECT source_id, title FROM epg_programmes WHERE title = ?',
    'sharedStagingEntriesAfterImport',
    "tar -C '`$pureLiveRoot' -cpf '`$remoteCacheBackup' IPTV_CACHE",
    'IPTV cache cleanup target guard rejected the path.',
    "rm -rf '`$iptvCachePath'",
    "restorecon -RF '`$iptvCachePath'",
    "cat '`$remoteSettingsRestore' > '`$settingsPath'",
    'iptvCacheRestoredExactly',
    'settingsFileRestoredExactly',
    'External fixture cleanup target guard rejected the path.',
    "'rm', '-f', `$externalPlaylist",
    "'rm', '-f', `$externalEpg",
    "'rmdir', `$externalDirectory",
    'externalFixturesRemovedExactly',
    'releaseDebugProbesExcluded',
    "logcat', '--pid'",
    'noFatalOrAnr',
    "input', 'keyevent', 'KEYCODE_HOME'",
    "am', 'force-stop', `$Package"
)) {
    if (-not $source.Contains($required)) { throw "Required DocumentsUI share guard is missing: $required" }
}
foreach ($forbidden in @('adb devices', 'kill-server', 'start-server', 'reboot', 'tcpip 5555', 'settings put', 'ime set')) {
    if ($source -match [regex]::Escape($forbidden)) { throw "Forbidden device operation found: $forbidden" }
}
if ($source -match "logcat', '-c") { throw 'DocumentsUI share smoke must preserve the process-global logcat buffer.' }
if ($source -match 'rm'', ''-rf'', \$externalDirectory' -or $source -match 'rm -rf ''\$externalDirectory''') {
    throw 'External fixture cleanup must remove exact files followed by nonrecursive rmdir.'
}
Write-Output 'PASS real external sender flow, exact state restoration and guarded fixture cleanup are present'
