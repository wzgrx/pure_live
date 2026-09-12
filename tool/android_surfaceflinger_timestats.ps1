# Pure parsing helpers for Android SurfaceFlinger time stats and /proc schedstat.
# Sourcing this file never connects to a device.

Set-StrictMode -Version Latest

function Get-AndroidHistogramPercentile {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Histogram,
        [Parameter(Mandatory = $true)][ValidateRange(0.0, 1.0)][double] $Percentile
    )

    [long] $total = 0
    foreach ($count in $Histogram.Values) { $total += [long] $count }
    if ($total -le 0) { return $null }

    [long] $target = [Math]::Max(1, [Math]::Ceiling($total * $Percentile))
    [long] $seen = 0
    foreach ($bucket in @($Histogram.Keys | ForEach-Object { [int] $_ } | Sort-Object)) {
        $seen += [long] $Histogram[$bucket]
        if ($seen -ge $target) { return $bucket }
    }
    return $null
}

function ConvertFrom-AndroidSurfaceFlingerTimeStats {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory = $true)][string] $Package
    )

    $text = $Lines -join "`n"
    $blocks = [regex]::Matches(
        $text,
        '(?ms)^layerName = (?<name>[^\r\n]+)\r?\n(?<body>.*?)(?=^layerName = |\z)'
    )
    $packagePattern = [regex]::Escape($Package)
    $candidates = @()
    foreach ($block in $blocks) {
        $name = $block.Groups['name'].Value.Trim()
        if ($name -notmatch $packagePattern -or $name -notmatch '\(BLAST\)') { continue }
        $body = $block.Groups['body'].Value
        $totalMatch = [regex]::Match($body, '(?m)^totalFrames = (\d+)\s*$')
        if (-not $totalMatch.Success) { continue }
        $candidates += [pscustomobject]@{
            Name = $name
            Body = $body
            Prelude = $text.Substring([Math]::Max(0, $block.Index - 320), [Math]::Min(320, $block.Index))
            TotalFrames = [long] $totalMatch.Groups[1].Value
        }
    }
    if ($candidates.Count -eq 0) {
        throw "SurfaceFlinger timestats contains no BLAST layer for '$Package'."
    }

    $selected = $candidates | Sort-Object TotalFrames -Descending | Select-Object -First 1
    $body = [string] $selected.Body

    function Read-Long([string] $Name) {
        $match = [regex]::Match($body, "(?m)^$([regex]::Escape($Name)) = (\d+)\s*$")
        if ($match.Success) { return [long] $match.Groups[1].Value }
        return $null
    }
    function Read-Double([string] $Name) {
        $match = [regex]::Match($body, "(?m)^$([regex]::Escape($Name)) = ([\d.]+)(?:\s|$)")
        if ($match.Success) {
            return [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        }
        return $null
    }

    function Read-PreludeDouble([string] $Name) {
        $match = [regex]::Match(
            [string] $selected.Prelude,
            "(?m)^$([regex]::Escape($Name)) = ([\d.]+)(?:\s|$)",
            [Text.RegularExpressions.RegexOptions]::RightToLeft
        )
        if ($match.Success) {
            return [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        }
        return $null
    }

    $histogramMatch = [regex]::Match(
        $body,
        '(?m)^present2present histogram is as below:\s*\r?\n(?<hist>[^\r\n]+)'
    )
    if (-not $histogramMatch.Success) {
        throw "SurfaceFlinger layer '$($selected.Name)' has no present2present histogram."
    }
    $histogram = @{}
    foreach ($entry in [regex]::Matches($histogramMatch.Groups['hist'].Value, '(\d+)ms=(\d+)')) {
        $histogram[[int] $entry.Groups[1].Value] = [long] $entry.Groups[2].Value
    }
    [long] $intervals = 0
    foreach ($count in $histogram.Values) { $intervals += [long] $count }
    if ($intervals -le 0) {
        throw "SurfaceFlinger layer '$($selected.Name)' contains an empty present2present histogram."
    }

    $displayRefreshRate = Read-PreludeDouble 'displayRefreshRate'
    $renderRate = Read-PreludeDouble 'renderRate'
    $frameRate = Read-Double 'frameRate'
    $effectiveRate = if ($renderRate -and $renderRate -gt 0) {
        $renderRate
    } elseif ($displayRefreshRate -and $displayRefreshRate -gt 0) {
        $displayRefreshRate
    } elseif ($frameRate -and $frameRate -gt 0) {
        $frameRate
    } else {
        $null
    }
    $longGapThresholdMs = if ($effectiveRate) { [Math]::Max(2, [Math]::Floor(2000.0 / $effectiveRate)) } else { 33 }
    $severeGapThresholdMs = if ($effectiveRate) { [Math]::Max(4, [Math]::Floor(4000.0 / $effectiveRate)) } else { 66 }
    [long] $longGapFrames = 0
    [long] $severeGapFrames = 0
    [int] $maximumObservedGapMs = 0
    foreach ($bucketKey in $histogram.Keys) {
        $bucket = [int] $bucketKey
        $count = [long] $histogram[$bucketKey]
        if ($count -gt 0 -and $bucket -gt $maximumObservedGapMs) { $maximumObservedGapMs = $bucket }
        if ($bucket -ge $longGapThresholdMs) { $longGapFrames += $count }
        if ($bucket -ge $severeGapThresholdMs) { $severeGapFrames += $count }
    }
    $serializedHistogram = [ordered]@{}
    foreach ($bucket in @($histogram.Keys | ForEach-Object { [int] $_ } | Sort-Object)) {
        $serializedHistogram[[string] $bucket] = [long] $histogram[$bucket]
    }

    [pscustomobject][ordered]@{
        layerName = [string] $selected.Name
        totalFrames = [long] $selected.TotalFrames
        histogramIntervals = $intervals
        droppedFrames = Read-Long 'droppedFrames'
        lateAcquireFrames = Read-Long 'lateAcquireFrames'
        badDesiredPresentFrames = Read-Long 'badDesiredPresentFrames'
        totalTimelineFrames = Read-Long 'totalTimelineFrames'
        jankyFrames = Read-Long 'jankyFrames'
        sfLongCpuJankyFrames = Read-Long 'sfLongCpuJankyFrames'
        sfLongGpuJankyFrames = Read-Long 'sfLongGpuJankyFrames'
        sfSchedulingJankyFrames = Read-Long 'sfSchedulingJankyFrames'
        appUnattributedJankyFrames = Read-Long 'appUnattributedJankyFrames'
        appBufferStuffingJankyFrames = Read-Long 'appBufferStuffingJankyFrames'
        frameRate = $frameRate
        displayRefreshRate = $displayRefreshRate
        renderRate = $renderRate
        averageFps = Read-Double 'averageFPS'
        p50GapMs = Get-AndroidHistogramPercentile -Histogram $histogram -Percentile 0.50
        p90GapMs = Get-AndroidHistogramPercentile -Histogram $histogram -Percentile 0.90
        p95GapMs = Get-AndroidHistogramPercentile -Histogram $histogram -Percentile 0.95
        p99GapMs = Get-AndroidHistogramPercentile -Histogram $histogram -Percentile 0.99
        longGapThresholdMs = $longGapThresholdMs
        longGapFrames = $longGapFrames
        longGapPercent = [Math]::Round(100.0 * $longGapFrames / $intervals, 3)
        severeGapThresholdMs = $severeGapThresholdMs
        severeGapFrames = $severeGapFrames
        severeGapPercent = [Math]::Round(100.0 * $severeGapFrames / $intervals, 3)
        maximumObservedGapMs = $maximumObservedGapMs
        presentToPresentHistogram = $serializedHistogram
    }
}

function ConvertFrom-AndroidMainThreadSchedStat {
    param(
        [Parameter(Mandatory = $true)][string] $Before,
        [Parameter(Mandatory = $true)][string] $After
    )

    function Read-Sched([string] $Value) {
        $match = [regex]::Match($Value.Trim(), '^(\d+)\s+(\d+)\s+(\d+)')
        if (-not $match.Success) { throw "Unexpected /proc schedstat value: '$Value'." }
        [pscustomobject]@{
            runtimeNs = [long] $match.Groups[1].Value
            runQueueDelayNs = [long] $match.Groups[2].Value
            slices = [long] $match.Groups[3].Value
        }
    }

    $start = Read-Sched $Before
    $end = Read-Sched $After
    if ($end.runtimeNs -lt $start.runtimeNs -or
        $end.runQueueDelayNs -lt $start.runQueueDelayNs -or
        $end.slices -lt $start.slices) {
        throw '/proc schedstat counters moved backwards.'
    }

    [pscustomobject][ordered]@{
        runtimeMs = [Math]::Round(($end.runtimeNs - $start.runtimeNs) / 1000000.0, 3)
        runQueueDelayMs = [Math]::Round(($end.runQueueDelayNs - $start.runQueueDelayNs) / 1000000.0, 3)
        slices = [long] ($end.slices - $start.slices)
    }
}
