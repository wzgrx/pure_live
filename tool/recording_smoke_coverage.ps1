function Get-RecordingSmokeAssertionResults {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Assertions,
        [int] $ScreenOffSeconds = 0,
        [bool] $ExerciseStreamSelection = $false,
        [int] $QualityOptionCount = 0,
        [int] $LineOptionCount = 0
    )
    $results = [ordered]@{}
    foreach ($entry in $Assertions.GetEnumerator()) {
        $results[$entry.Key] = if ([bool]$entry.Value) { 'PASS' } else { 'FAIL' }
    }
    if ($ScreenOffSeconds -eq 0) {
        foreach ($name in @('screenOffConfirmed', 'screenOffRecordingContinued', 'processAliveDuringScreenOff', 'roomRestoredAfterScreenOff')) {
            $results[$name] = 'SKIP'
        }
    }
    if (-not $ExerciseStreamSelection -or $QualityOptionCount -le 1) {
        foreach ($name in @('qualitySwitchCommitted', 'qualitySwitchStable')) { $results[$name] = 'SKIP' }
    }
    if (-not $ExerciseStreamSelection -or $LineOptionCount -le 1) {
        foreach ($name in @('lineSwitchCommitted', 'lineSwitchStable')) { $results[$name] = 'SKIP' }
    }
    return $results
}
