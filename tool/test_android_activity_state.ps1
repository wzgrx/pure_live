[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_activity_state.ps1')

$target = "    * Hist  #0: ActivityRecord{123 u0 com.mystyle.purelive/.MainActivity t42}`n"
$other = "    * Hist #0: ActivityRecord{456 u0 example.other/.MainActivity t43}`n"
$cases = @(
    @{ Name = 'target-entered'; Dump = $target + 'mLastReportedPictureInPictureMode=true'; Expected = $true },
    @{ Name = 'capability-only'; Dump = $target + 'supportsPictureInPicture=true'; Expected = $false },
    @{ Name = 'target-not-entered'; Dump = $target + 'mLastReportedPictureInPictureMode=false'; Expected = $false },
    @{ Name = 'other-app-entered'; Dump = $target + "mLastReportedPictureInPictureMode=false`n" + $other + 'mLastReportedPictureInPictureMode=true'; Expected = $false },
    @{ Name = 'target-after-other'; Dump = $other + "mLastReportedPictureInPictureMode=false`n" + $target + 'mLastReportedPictureInPictureMode=true'; Expected = $true },
    @{ Name = 'package-prefix-is-not-target'; Dump = $target.Replace('com.mystyle.purelive/', 'com.mystyle.purelive.other/') + 'mLastReportedPictureInPictureMode=true'; Expected = $false },
    @{ Name = 'next-task-state-is-not-target'; Dump = $target + "mLastReportedPictureInPictureMode=false`n  * Task{other mode=pinned}`nmLastReportedPictureInPictureMode=true"; Expected = $false },
    @{ Name = 'missing-dump'; Dump = ''; Expected = $false }
)
foreach ($case in $cases) {
    $actual = Test-AndroidTargetPictureInPicture -ActivityDump $case.Dump
    if ($actual -ne $case.Expected) { throw "$($case.Name): expected $($case.Expected), got $actual" }
    Write-Output "PASS $($case.Name)"
}
