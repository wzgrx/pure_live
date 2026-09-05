function Get-PureLiveIntervalCpuPercent {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[double]] $CurrentCpuSeconds,
        [AllowNull()][Nullable[double]] $PreviousCpuSeconds,
        [double] $ElapsedSeconds,
        [ValidateRange(1, 4096)][int] $LogicalProcessors
    )

    # The initial observation is a baseline, not a zero-utilization interval.
    # Missing/reset counters must not lower the measured average either.
    if ($null -eq $CurrentCpuSeconds -or $null -eq $PreviousCpuSeconds -or
        $ElapsedSeconds -le 0 -or [double]::IsNaN($ElapsedSeconds) -or [double]::IsInfinity($ElapsedSeconds)) {
        return $null
    }
    $delta = [double]$CurrentCpuSeconds - [double]$PreviousCpuSeconds
    if ($delta -lt 0 -or [double]::IsNaN($delta) -or [double]::IsInfinity($delta)) { return $null }
    return [Math]::Round(($delta / $ElapsedSeconds / $LogicalProcessors) * 100.0, 4)
}
