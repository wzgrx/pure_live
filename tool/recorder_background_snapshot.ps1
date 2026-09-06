# Pure parser: dumpsys records are evidence, not substring matches across services.
function Get-RecorderBackgroundSnapshot {
    param(
        [AllowEmptyString()][string] $Services,
        [AllowEmptyString()][string] $Power,
        [string] $Package = 'com.mystyle.purelive'
    )
    $records = [regex]::Matches($Services, '(?ms)^\s*\* ServiceRecord\{(?<header>[^\r\n]*)\}\s*\r?\n(?<body>.*?)(?=^\s*\* ServiceRecord\{|\z)')
    $recorder = @($records | Where-Object { $_.Groups['header'].Value.Contains($Package) -and $_.Groups['header'].Value.Contains('RecorderForegroundService') })
    $audio = @($records | Where-Object { $_.Groups['header'].Value.Contains($Package) -and $_.Groups['header'].Value.Contains('AudioService') })
    $recorderForeground = @($recorder | Where-Object { $_.Groups['body'].Value -match '\bisForeground=true\b' }).Count -gt 0
    $audioForeground = @($audio | Where-Object { $_.Groups['body'].Value -match '\bisForeground=true\b' }).Count -gt 0
    $wakeSection = [regex]::Match($Power, '(?ms)^Wake Locks:\s*size=\d+\s*\r?\n.*?(?=^Suspend Blockers:|\z)').Value
    [ordered]@{
        recorderServicePresent = $recorder.Count -gt 0
        recorderForeground = $recorderForeground
        audioServicePresent = $audio.Count -gt 0
        audioForeground = $audioForeground
        recorderCpuLockHeld = $wakeSection.Contains("${Package}:recording")
    }
}
