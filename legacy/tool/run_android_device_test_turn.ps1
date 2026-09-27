[CmdletBinding()]
param(
    [string]$CommandLine,
    [string]$Serial = $env:PURELIVE_ADB_SERIAL,
    [switch]$Pass,
    [switch]$NoRotation,
    [int]$TimeoutMinutes = 180,
    [int]$TurnGraceSeconds = 120,
    [int]$PollSeconds = 3
)

$ErrorActionPreference = 'Stop'
if ($Pass.IsPresent -and -not [string]::IsNullOrWhiteSpace($CommandLine)) {
    throw 'Use either -CommandLine or -Pass, not both.'
}
if (-not $Pass.IsPresent -and [string]::IsNullOrWhiteSpace($CommandLine)) {
    throw 'A complete device-test command is required unless -Pass is used.'
}

$cursor = Get-Item -LiteralPath $PSScriptRoot
$coordinator = $null
while ($null -ne $cursor) {
    $candidate = Join-Path $cursor.FullName 'shared-device-test-rotation\Invoke-DeviceTestTurn.ps1'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $coordinator = $candidate
        break
    }
    $cursor = $cursor.Parent
}
if (-not $coordinator -and -not $NoRotation) {
    throw 'Shared device-test coordinator was not found above the repository.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$rawCommand = if ($Pass.IsPresent) {
    "Write-Host 'Pure Live has no device work in this round; passing the phone.'"
} else {
    $CommandLine
}
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($rawCommand))
$encodedSerial = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Serial))
$effectiveCommand = @"
`$turnFailure = `$null
`$wakeState = `$null
try {
    `$requestedSerial = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedSerial'))
    `$wakeArguments = @{ StayAwake = `$true }
    if (-not [string]::IsNullOrWhiteSpace(`$requestedSerial)) {
        `$wakeArguments.Serial = `$requestedSerial
    }
    `$wakeOutput = @(& '.\tool\wake_android_device.ps1' @wakeArguments)
    if (`$LASTEXITCODE -ne 0) { throw "Device wake guard exited with code `$LASTEXITCODE." }
    `$wakeOutput | Write-Output
    `$wakeState = `$wakeOutput | Select-Object -Last 1 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]`$wakeState.Serial)) {
        throw 'Device wake guard did not return a target serial.'
    }
    `$env:PURELIVE_ADB_SERIAL = [string]`$wakeState.Serial
    `$decodedCommand = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedCommand'))
    & ([scriptblock]::Create(`$decodedCommand))
    if (`$LASTEXITCODE -ne 0) { throw "Device command exited with code `$LASTEXITCODE." }
} catch {
    `$turnFailure = `$_
} finally {
    try {
        # Only release the target whose wake guard actually acquired stay-awake.
        # A failed/ambiguous discovery must not mutate a stale environment target.
        if (`$null -ne `$wakeState -and `$wakeState.StayAwake -and
            -not [string]::IsNullOrWhiteSpace([string]`$wakeState.Serial)) {
            if (`$null -eq `$wakeState.OriginalStayAwakeValue -or `$null -eq `$wakeState.AcquiredStayAwakeValue) {
                throw 'Wake guard did not return stay-awake ownership values; preserving the setting.'
            }
            & '.\tool\wake_android_device.ps1' -ReleaseStayAwake -Serial ([string]`$wakeState.Serial) -RestoreStayAwakeValue ([int]`$wakeState.OriginalStayAwakeValue) -AcquiredStayAwakeValue ([int]`$wakeState.AcquiredStayAwakeValue)
            if (`$LASTEXITCODE -ne 0) { throw "Device wake guard cleanup exited with code `$LASTEXITCODE." }
        }
    } catch {
        if (`$null -eq `$turnFailure) { `$turnFailure = `$_ }
        else { Write-Warning ('Device wake guard cleanup also failed: ' + [string]`$_.Exception.Message) }
    }
}
if (`$null -ne `$turnFailure) { throw `$turnFailure }
"@

if ($NoRotation) {
    # Explicit single-task device work still owns the wake/cleanup guard.
    # Encode the full script to preserve quotes across the native boundary.
    $encodedTurn = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($effectiveCommand))
    Push-Location $repositoryRoot
    try {
        & pwsh -NoProfile -OutputFormat Text -EncodedCommand $encodedTurn
        $turnExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    exit $turnExitCode
}

& $coordinator `
    -Lane purelive `
    -WorkingDirectory $repositoryRoot `
    -CommandLine $effectiveCommand `
    -TimeoutMinutes $TimeoutMinutes `
    -TurnGraceSeconds $TurnGraceSeconds `
    -PollSeconds $PollSeconds
exit $LASTEXITCODE
