[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApkPath,
    [string] $Serial,
    [string] $EvidenceDirectory,
    [string] $Package = 'com.mystyle.purelive'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apk = (Resolve-Path $ApkPath).Path
$evidence = if ($EvidenceDirectory) {
    [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $repo $EvidenceDirectory }))
} else {
    Join-Path $repo ("local-artifacts\diagnostics\android-color-picker-{0}" -f (Get-Date -Format 'yyyyMMddTHHmmssfff'))
}
[IO.Directory]::CreateDirectory($evidence) | Out-Null

$adb = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'adb.exe'
) | Where-Object {
    if ([IO.Path]::IsPathRooted($_)) { Test-Path -LiteralPath $_ }
    else { [bool](Get-Command $_ -ErrorAction SilentlyContinue) }
} | Select-Object -First 1
if (-not $adb) { throw 'ADB executable was not found.' }

function Invoke-Adb {
    param([Parameter(Mandatory = $true)][string[]] $AdbArguments)
    $result = & $adb -s $Serial @AdbArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed ($LASTEXITCODE): $($AdbArguments -join ' ')`n$($result -join "`n")"
    }
    $result
}

$deviceRows = & $adb devices -l
if (-not $Serial) {
    $devices = @($deviceRows | ForEach-Object { if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] } })
    $network = @($devices | Where-Object { $_ -match '^(?:\d{1,3}\.){3}\d{1,3}:\d+$' })
    if ($network.Count -eq 1) { $Serial = $network[0] }
    elseif ($devices.Count -eq 1) { $Serial = $devices[0] }
    else { throw "Specify -Serial; devices=$($devices.Count), network=$($network.Count)." }
}

function Ensure-Awake {
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'wm', 'dismiss-keyguard') | Out-Null
}

function Save-UiDump {
    param([Parameter(Mandatory = $true)][string] $Name)
    Ensure-Awake
    $remote = "/sdcard/purelive-$PID-$Name.xml"
    $local = Join-Path $evidence "$Name.xml"
    try {
        Invoke-Adb -AdbArguments @('shell', 'timeout', '12', 'uiautomator', 'dump', '--compressed', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, $local) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
    [xml](Get-Content -LiteralPath $local -Raw -Encoding UTF8)
}

function Save-Screenshot {
    param([Parameter(Mandatory = $true)][string] $Name)
    Ensure-Awake
    $remote = "/sdcard/purelive-$PID-$Name.png"
    try {
        Invoke-Adb -AdbArguments @('shell', 'screencap', '-p', $remote) | Out-Null
        Invoke-Adb -AdbArguments @('pull', $remote, (Join-Path $evidence "$Name.png")) | Out-Null
    } finally {
        try { Invoke-Adb -AdbArguments @('shell', 'rm', '-f', $remote) | Out-Null } catch {}
    }
}

function Find-UiNode {
    param(
        [Parameter(Mandatory = $true)][xml] $Document,
        [Parameter(Mandatory = $true)][string] $Text,
        [switch] $Editable
    )
    $nodes = @($Document.SelectNodes('//node') | Where-Object {
        $label = "{0}`n{1}" -f ([string]$_.text), ([string]$_.'content-desc')
        $classMatches = -not $Editable.IsPresent -or ([string]$_.class -match 'EditText')
        $classMatches -and $label.Contains($Text)
    })
    $nodes | Sort-Object {
        if ([string]$_.clickable -eq 'true') { 0 } else { 1 }
    } | Select-Object -First 1
}

function Tap-UiNode {
    param([Parameter(Mandatory = $true)] $Node)
    $bounds = [string]$Node.bounds
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        throw "Unexpected UI bounds: $bounds"
    }
    $x = [math]::Floor(([int]$Matches[1] + [int]$Matches[3]) / 2)
    $y = [math]::Floor(([int]$Matches[2] + [int]$Matches[4]) / 2)
    Invoke-Adb -AdbArguments @('shell', 'input', 'tap', $x, $y) | Out-Null
}

function Tap-Text {
    param([Parameter(Mandatory = $true)][string] $Text, [Parameter(Mandatory = $true)][string] $EvidenceName)
    $document = Save-UiDump $EvidenceName
    $node = Find-UiNode -Document $document -Text $Text
    if (-not $node) { throw "UI text not found: $Text" }
    Tap-UiNode $node
    Start-Sleep -Milliseconds 900
}

function Dismiss-DebugCompatibilityDialog {
    $document = Save-UiDump 'debug-compatibility'
    $button = Find-UiNode -Document $document -Text '确定'
    if ($button) {
        Tap-UiNode $button
        Start-Sleep -Milliseconds 700
    }
}

$result = [ordered]@{
    schemaVersion = 1
    startedAt = (Get-Date).ToString('o')
    serial = $Serial
    apk = $apk
    checks = [ordered]@{}
}
$failure = $null
try {
    $install = Invoke-Adb -AdbArguments @('install', '-r', '-t', $apk)
    $result.checks.install = ($install -join "`n").Trim()
    Ensure-Awake
    Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$Package/.MainActivity") | Out-Null
    Start-Sleep -Seconds 6
    Dismiss-DebugCompatibilityDialog

    & (Join-Path $repo 'tool\android_ui.ps1') -Sequence open_settings -Serial $Serial -CaptureOnFailure
    if ($LASTEXITCODE -ne 0) { throw 'Opening settings failed.' }
    Start-Sleep -Milliseconds 700
    Tap-Text -Text '主题定制' -EvidenceName 'settings'

    Tap-Text -Text '主题颜色' -EvidenceName 'theme-settings'
    $themeDialog = Save-UiDump 'theme-color-dialog'
    $themeXml = $themeDialog.OuterXml
    $result.checks.themeUsesShadeLabel = $themeXml.Contains('选择色阶')
    $result.checks.themeUsesRgbField = $themeXml.Contains('RGB 颜色代码')
    $result.checks.themeDoesNotClaimOpacity = -not $themeXml.Contains('选择透明度')
    Save-Screenshot 'theme-color-dialog'
    if (-not $result.checks.themeUsesShadeLabel -or -not $result.checks.themeUsesRgbField -or -not $result.checks.themeDoesNotClaimOpacity) {
        throw 'Opaque theme picker labels do not match the actual controls.'
    }
    Tap-Text -Text '取消' -EvidenceName 'theme-color-cancel'

    Tap-Text -Text '修改加载动画' -EvidenceName 'theme-settings-after-cancel'
    Tap-Text -Text '修改加载颜色' -EvidenceName 'loading-settings'
    $loadingDialog = Save-UiDump 'loading-color-dialog'
    $loadingXml = $loadingDialog.OuterXml
    $result.checks.loadingHasOpacity = $loadingXml.Contains('选择透明度')
    $result.checks.loadingHasArgbField = $loadingXml.Contains('ARGB 颜色代码')
    $edit = @($loadingDialog.SelectNodes('//node') | Where-Object { [string]$_.class -match 'EditText' }) | Select-Object -First 1
    if (-not $edit) { throw 'ARGB color code field was not exposed by UIAutomator.' }
    $originalCode = [string]$edit.text
    $result.checks.originalCode = $originalCode
    if (-not $result.checks.loadingHasOpacity -or -not $result.checks.loadingHasArgbField) {
        throw 'Transparent loading-color picker is missing opacity or ARGB controls.'
    }

    Tap-UiNode $edit
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_MOVE_END') | Out-Null
    1..14 | ForEach-Object { Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_DEL') | Out-Null }
    Invoke-Adb -AdbArguments @('shell', 'input', 'text', '0x800080DD') | Out-Null
    Start-Sleep -Milliseconds 700
    $editedDialog = Save-UiDump 'loading-color-edited'
    $editedField = @($editedDialog.SelectNodes('//node') | Where-Object { [string]$_.class -match 'EditText' }) | Select-Object -First 1
    $result.checks.editedCode = [string]$editedField.text
    $result.checks.fullArgbEntryAccepted = ([string]$editedField.text).ToUpperInvariant().Contains('800080DD')
    Save-Screenshot 'loading-color-edited'
    if (-not $result.checks.fullArgbEntryAccepted) { throw 'The full ARGB code did not remain in the edit field.' }

    # UIAutomator may close the software keyboard while producing the dump. In
    # that state KEYCODE_BACK dismisses the dialog itself instead of only the
    # IME. Accept both correct cancel paths, but fail if neither the dialog nor
    # its parent page remains visible.
    Invoke-Adb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_BACK') | Out-Null
    Start-Sleep -Milliseconds 350
    $afterBack = Save-UiDump 'loading-color-cancel'
    $cancelAfterBack = Find-UiNode -Document $afterBack -Text '取消'
    if ($cancelAfterBack) {
        Tap-UiNode $cancelAfterBack
        $result.checks.cancelPath = 'explicit-button'
        Start-Sleep -Milliseconds 900
    } elseif ((Find-UiNode -Document $afterBack -Text '修改加载颜色')) {
        $result.checks.cancelPath = 'system-back'
    } else {
        throw 'Neither the loading color dialog nor its parent settings page remained after back.'
    }
    Tap-Text -Text '修改加载颜色' -EvidenceName 'loading-settings-after-cancel'
    $restoredDialog = Save-UiDump 'loading-color-restored'
    $restoredField = @($restoredDialog.SelectNodes('//node') | Where-Object { [string]$_.class -match 'EditText' }) | Select-Object -First 1
    $result.checks.restoredCode = [string]$restoredField.text
    $result.checks.cancelRestoredOriginal = ([string]$restoredField.text) -eq $originalCode
    Save-Screenshot 'loading-color-restored'
    if (-not $result.checks.cancelRestoredOriginal) { throw 'Cancel did not restore the original loading color.' }
    Tap-Text -Text '取消' -EvidenceName 'loading-color-final-cancel'

    $result.checks.passed = $true
} catch {
    $failure = $_
    $result.error = $_.Exception.Message
    $result.checks.passed = $false
} finally {
    try { Invoke-Adb -AdbArguments @('shell', 'am', 'force-stop', $Package) | Out-Null } catch {}
    $result.completedAt = (Get-Date).ToString('o')
    $summary = Join-Path $evidence 'summary.json'
    $result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $summary -Encoding utf8
}

Write-Output (Join-Path $evidence 'summary.json')
if ($failure) { throw $failure }
