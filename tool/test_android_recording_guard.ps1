[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_recording_navigation.ps1')

# Extract production functions only; never execute the script's ADB entrypoint.
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'android_recording_smoke.ps1'), [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Assert-RecordingForeground', 'Invoke-Adb', 'Initialize-RecordingTarget', 'Enter-RecordingHome', 'Get-Foreground', 'Save-UiDump', 'Wake-AndDismissKeyguard', 'Select-PlatformTab')) {
    $function = $ast.Find({ param($n)
        $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true)
    if ($null -eq $function) { throw "Production function is missing: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}

function Assert-Equal($Actual, $Expected, [string] $Name) {
    if ($Actual -cne $Expected) { throw "${Name}: expected '$Expected', got '$Actual'" }
}
function Assert-Throws([scriptblock] $Body, [string] $Pattern) {
    $message = ''
    try { & $Body | Out-Null } catch { $message = $_.Exception.Message }
    if ($message -notmatch $Pattern) { throw "Expected '$Pattern', got '$message'" }
}
function Reset-Fake {
    $script:serial = '192.0.2.10:5555'
    $script:Package = 'com.mystyle.purelive'
    $script:Activity = '.MainActivity'
    $script:homePackage = 'example.launcher'
    $script:foregroundLost = $false
    $script:transportFailed = $false
    $script:foregroundInterferenceCount = 0
    $script:foreground = 'topResumedActivity=ActivityRecord{123 u0 com.mystyle.purelive/.MainActivity t1}'
    $script:failure = ''
    $script:failObservation = $false
    $script:changeAfterDump = $false
    $script:fakeModel = '25102RKBEC'
    $script:fakeDevice = 'myron'
    $script:calls = [Collections.Generic.List[string]]::new()
    $script:adb = {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)
        $command = $Arguments -join ' '
        $script:calls.Add($command)
        $global:LASTEXITCODE = 0
        if ($Arguments[0] -cne '-s' -or $Arguments[1] -cne '192.0.2.10:5555') {
            throw 'Fake executable received an unbound or different device.'
        }
        if ($command -match 'shell getprop ro.product.model$') {
            $script:fakeModel
        } elseif ($command -match 'shell getprop ro.product.device$') {
            $script:fakeDevice
        } elseif ($command -match 'shell cmd package resolve-activity') {
            'example.launcher/.Home'
        } elseif ($command -match 'shell dumpsys activity activities$') {
            if ($script:failObservation) { $global:LASTEXITCODE = 1; 'error: device offline' }
            else { $script:foreground -split '\r?\n' }
        } elseif ($command -match 'shell input' -and $script:failure) {
            $global:LASTEXITCODE = 1; $script:failure
        } elseif ($command -match 'shell uiautomator dump') {
            if ($script:changeAfterDump) { $script:foreground = 'topResumedActivity=ActivityRecord{456 u0 example.other/.Activity t2}' }
            'UI hierarchy dumped'
        } elseif ($Arguments[2] -eq 'pull') {
            '<hierarchy/>' | Set-Content -LiteralPath $Arguments[4]
        }
    }
}

foreach ($case in @(
    @{ Text = 'topResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive/.MainActivity t1}'; Expected = 'com.mystyle.purelive' },
    @{ Text = 'mResumedActivity: ActivityRecord{1 u0 com.mystyle.purelive/.MainActivity t1}'; Expected = 'com.mystyle.purelive' },
    @{ Text = 'topResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive.other/.MainActivity t1}'; Expected = 'com.mystyle.purelive.other' },
    @{ Text = 'topResumedActivity=ActivityRecord{1 u10 com.mystyle.purelive/.MainActivity t1}'; Expected = '' },
    @{ Text = "topResumedActivity=null`nmResumedActivity: ActivityRecord{1 u0 com.mystyle.purelive/.MainActivity t1}"; Expected = '' },
    @{ Text = "topResumedActivity=ActivityRecord{1 u0 example.other/.A t2}`nmResumedActivity: ActivityRecord{1 u0 com.mystyle.purelive/.MainActivity t1}"; Expected = 'example.other' },
    @{ Text = "topResumedActivity=ActivityRecord{1 u0 example.other/.A t2}`ntopResumedActivity=ActivityRecord{2 u0 com.mystyle.purelive/.A t3}"; Expected = '' },
    @{ Text = 'mLastResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive/.MainActivity t1}'; Expected = '' },
    @{ Text = ''; Expected = '' }
)) {
    Assert-Equal (Get-RecordingForegroundPackage $case.Text) $case.Expected 'foreground parser'
}
Write-Output 'PASS exact current foreground parsing, user and multi-window ambiguity (9 cases)'

foreach ($case in @(
    @{ Text = "mResumedActivity: ActivityRecord{1 u0 example.other/.A t1}`ntopResumedActivity=ActivityRecord{2 u0 com.mystyle.purelive/.A t2}"; Expected = 'com.mystyle.purelive' },
    @{ Text = "mResumedActivity: ActivityRecord{1 u0 com.mystyle.purelive/.A t1}`ntopResumedActivity=null"; Expected = '' },
    @{ Text = "topResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive/.A t1}`ntopResumedActivity=ActivityRecord{2 u0 example.other/.A t2}"; Expected = '' }
)) {
    Reset-Fake; $script:foreground = $case.Text
    Assert-Equal (Get-RecordingForegroundPackage -ActivityDump (Get-Foreground)) $case.Expected 'report uses current top-resumed rows'
}
Write-Output 'PASS evidence capture prefers top-resumed and preserves unknown/ambiguous state (3 cases)'

Reset-Fake
Assert-Throws { Initialize-RecordingTarget -RequestedSerial '' } 'explicit -Serial'
Assert-Equal $script:calls.Count 0 'missing explicit target does not discover devices'
foreach ($mismatch in @('model','device')) {
    Reset-Fake
    if ($mismatch -eq 'model') { $script:fakeModel = 'other' } else { $script:fakeDevice = 'other' }
    Assert-Throws { Initialize-RecordingTarget -RequestedSerial '192.0.2.10:5555' } 'identity mismatch'
    Assert-Equal $script:calls.Count 2 'identity mismatch stops after read-only properties'
}
Reset-Fake
$script:foreground = 'topResumedActivity=ActivityRecord{1 u0 example.other/.A t1}'
Assert-Throws { Initialize-RecordingTarget -RequestedSerial '192.0.2.10:5555' } 'foreground changed'
Assert-Equal $script:calls.Count 3 'busy device preflight has no mutation or launcher query'
Reset-Fake
Initialize-RecordingTarget -RequestedSerial '192.0.2.10:5555'
Assert-Equal $script:calls.Count 4 'matching identity and foreground completes read-only preflight'
Assert-Equal $script:homePackage 'example.launcher' 'home resolved on the selected device'
Write-Output 'PASS explicit serial, model/device and foreground preflight (5 cases)'

Reset-Fake
Enter-RecordingHome | Out-Null
Assert-Equal $script:calls.Count 2 'home entry has one foreground read and one ActivityManager command'
Assert-Equal $script:calls[1] '-s 192.0.2.10:5555 shell am start -W -f 0x10008000 -n com.mystyle.purelive/.MainActivity' 'reset only our task'
Assert-Equal @($script:calls | Where-Object { $_ -match 'force-stop' }).Count 0 'no intervening previous-app foreground'
Reset-Fake; $script:foreground = 'topResumedActivity=ActivityRecord{1 u0 bin.mt.plus/.MainLightIcon t1}'
Assert-Throws { Enter-RecordingHome } 'foreground changed'
Assert-Equal $script:calls.Count 1 'home reset does not gain a broad MT/other-app exception'
Write-Output 'PASS atomic target-task entry and unchanged other-app guard (2 cases)'

foreach ($observedForeground in @('', 'topResumedActivity=null',
    'topResumedActivity=ActivityRecord{1 u0 example.other/.A t1}',
    'topResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive.other/.A t1}')) {
    foreach ($arguments in @(
        @('shell', 'input', 'tap', '10', '20'),
        @('shell', 'input', 'swipe', '10', '20', '30', '20', '240'),
        @('shell', 'input', 'keyevent', '4'),
        @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'),
        @('shell', 'wm', 'dismiss-keyguard'),
        @('shell', 'uiautomator', 'dump', '/sdcard/fixture.xml'),
        @('shell', 'screencap', '-p', '/sdcard/fixture.png'),
        @('shell', 'am', 'start', '-n', 'com.mystyle.purelive/.MainActivity')
    )) {
        Reset-Fake
        $script:foreground = $observedForeground
        Assert-Throws { Invoke-Adb -AdbArguments $arguments } 'foreground changed or is unknown'
        Assert-Equal $script:calls.Count 1 'only foreground observation runs'
        Assert-Equal $script:foregroundInterferenceCount 1 'sticky interruption counted once'
        $script:foreground = 'topResumedActivity=ActivityRecord{1 u0 com.mystyle.purelive/.A t1}'
        Assert-Throws { Invoke-Adb -AdbArguments $arguments } 'interrupted'
        Assert-Equal $script:calls.Count 1 'no implicit recovery after interruption'
    }
}
Write-Output 'PASS input/observation guard stops on other/unknown foreground and stays stopped (32 cases)'

foreach ($errorText in @('daemon still not running', 'error: device offline', "device '192.0.2.10:5555' not found", 'transport closed')) {
    Reset-Fake; $script:failure = $errorText
    Assert-Throws { Invoke-Adb -AdbArguments @('shell', 'input', 'tap', '10', '20') } 'adb failed'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input' }).Count 1 'input attempted once'
    Assert-Equal $script:serial '192.0.2.10:5555' 'transport identity remains fixed'
    Assert-Throws { Invoke-Adb -AdbArguments @('shell', 'input', 'tap', '10', '20') } 'Transport failed earlier'
    Assert-Equal $script:calls.Count 2 'no daemon command, discovery, retry or target adoption'
}
Reset-Fake; $script:failObservation = $true
Assert-Throws { Invoke-Adb -AdbArguments @('shell', 'input', 'tap', '10', '20') } 'observation failed'
Assert-Equal $script:calls.Count 1 'failed observation prevents input'
Write-Output 'PASS transport failures never restart, retarget or replay (5 cases)'

Reset-Fake
Invoke-Adb -AdbArguments @('shell', 'input', 'tap', '10', '20') | Out-Null
Assert-Equal $script:calls.Count 2 'target foreground permits one input'
Reset-Fake; $script:foreground = 'topResumedActivity=ActivityRecord{1 u0 example.launcher/.Home t1}'
Invoke-Adb -AdbArguments @('shell', 'am', 'start', '-n', 'com.mystyle.purelive/.MainActivity') -AllowHomeForeground | Out-Null
Assert-Equal $script:calls.Count 2 'explicit app-relaunch phase permits resolved home'
Assert-Throws { Invoke-Adb -AdbArguments @('shell', 'input', 'tap', '10', '20') } 'foreground changed'
Write-Output 'PASS normal target input and scoped launcher re-entry (3 cases)'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('purelive-record-guard-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:evidence = $temporary
try {
    Reset-Fake; $script:changeAfterDump = $true
    Assert-Throws { Save-UiDump 'changed-after-dump' } 'foreground changed'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell uiautomator dump' }).Count 1 'no UI dump retry after loss'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'am start|monkey|start-server' }).Count 0 'no foreground takeover'
    Write-Output 'PASS foreground change during dump stops immediately without relaunch'

    # Fake only the IO seams for navigation; production selection and parsing run.
    function Start-Sleep { param($Milliseconds, $Seconds) }
    function Save-UiDump {
        param([string] $Name)
        $script:observations++
        $frame = $script:frames[[math]::Min($script:frameIndex, $script:frames.Count - 1)]
        $frame | Set-Content -LiteralPath (Join-Path $evidence "$Name.xml") -Encoding utf8
        $script:frameIndex++
    }
    function New-Tab([string]$Label, [int]$Index, [int]$Total, [int]$Left, [bool]$Selected = $false, [int]$Top = 100) {
        '<node content-desc="{0}&#10;第 {1} 个标签，共 {2} 个" enabled="true" clickable="true" selected="{3}" bounds="[{4},{5}][{6},{7}]"/>' -f $Label,$Index,$Total,$Selected.ToString().ToLowerInvariant(),$Left,$Top,($Left+100),($Top+80)
    }
    function Reset-Navigation([string[]] $Frames) {
        Reset-Fake
        $script:frames = $Frames; $script:frameIndex = 0; $script:observations = 0
        $script:platformLabels = @{picarto='Picarto'; huya='虎牙'; twitch='Twitch'; soop='Soop'}
    }
    $visible = '<hierarchy>' + (New-Tab '全部' 1 2 50) + (New-Tab 'Picarto' 2 2 150) + '</hierarchy>'
    $selected = $visible.Replace('selected="false" bounds="[150', 'selected="true" bounds="[150')
    Reset-Navigation @($visible,$selected)
    Select-PlatformTab 'Picarto'
    Assert-Equal $script:observations 2 'selection verified from fresh frame'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input tap 200 140$' }).Count 1 'two-tab hidden-other-sites case'

    $start = '<hierarchy>'+(New-Tab '全部' 1 4 50)+(New-Tab '虎牙' 2 4 150)+'</hierarchy>'
    $end = '<hierarchy>'+(New-Tab 'Twitch' 3 4 50)+(New-Tab 'Picarto' 4 4 150)+'</hierarchy>'
    $endSelected = $end.Replace('selected="false" bounds="[150','selected="true" bounds="[150')
    Reset-Navigation @($start,$end,$endSelected)
    Select-PlatformTab 'Picarto'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input swipe 238 140 62 140 240$' }).Count 1 'swipe stays in observed header'
    Assert-Equal $script:observations 3 'one fresh observation per action'

    $reordered = '<hierarchy>'+(New-Tab 'Picarto' 1 3 50 $true)+(New-Tab '全部' 2 3 150)+'</hierarchy>'
    Reset-Navigation @($reordered)
    Select-PlatformTab 'Picarto'
    Assert-Equal $script:calls.Count 0 'reordered already-selected tab needs no input'

    $missingEnd = '<hierarchy>'+(New-Tab 'Twitch' 3 4 50)+(New-Tab 'Soop' 4 4 150)+'</hierarchy>'
    Reset-Navigation @($start,$missingEnd)
    Assert-Throws { Select-PlatformTab 'Picarto' } 'hidden or absent'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input' }).Count 1 'missing site stops at observed end'

    $middle = '<hierarchy>'+(New-Tab '虎牙' 2 5 50)+(New-Tab 'Twitch' 3 5 150)+'</hierarchy>'
    Reset-Navigation @($middle,$middle,$middle)
    Assert-Throws { Select-PlatformTab 'Picarto' } 'hidden or absent'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input swipe' }).Count 2 'stalled header tries each direction once'

    Reset-Navigation @($visible)
    Assert-Throws { Select-PlatformTab 'Picarto' } 'within 48 observed steps'
    Assert-Equal $script:observations 48 'selection never commits has bounded observations'
    Assert-Equal @($script:calls | Where-Object { $_ -match 'shell input tap' }).Count 47 'last observation sends no unverified tap'

    $english = $visible.Replace('第 1 个标签，共 2 个','Tab 1 of 2').Replace('第 2 个标签，共 2 个','Tab 2 of 2')
    Assert-Equal @(Get-RecordingPlatformTabs -Xml $english -KnownLabels @('全部','Picarto')).Count 2 'English ordinals'
    $ambiguous = '<hierarchy>'+(New-Tab '全部' 1 2 50)+(New-Tab 'Picarto' 2 2 150 $false 300)+'</hierarchy>'
    Assert-Throws { Get-RecordingPlatformTabs -Xml $ambiguous -KnownLabels @('全部','Picarto') } 'ambiguous'
    Assert-Throws { Get-RecordingPlatformTabs -Xml '<hierarchy/>' -KnownLabels @('Picarto') } 'No visible'
    Write-Output 'PASS semantic selection, reordered/hidden sites, bounded stalls and ambiguous rows (9 cases)'
} finally {
    # Validate this one fixture path before recursive cleanup; no computed parent deletion.
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'purelive-record-guard-*') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output 'PASS recording guard and navigation fixtures; real ADB commands: 0'
