$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_surfaceflinger_timestats.ps1')

$fixture = @'
statsStart = 1
statsEnd = 2
layerName = old SurfaceView[com.mystyle.purelive/MainActivity](BLAST)#1
packageName =
totalFrames = 2
droppedFrames = 1
frameRate = 60.00
averageFPS = 30.000
present2present histogram is as below:
16ms=1 33ms=1

displayRefreshRate = 120 fps
renderRate = 120 fps
layerName = current SurfaceView[com.mystyle.purelive/com.mystyle.purelive.MainActivity](BLAST)#2
packageName =
totalFrames = 100
droppedFrames = 0
lateAcquireFrames = 1
badDesiredPresentFrames = 2
Jank payload for this layer:
totalTimelineFrames = 100
jankyFrames = 3
sfLongCpuJankyFrames = 1
sfLongGpuJankyFrames = 0
sfSchedulingJankyFrames = 1
appUnattributedJankyFrames = 1
appBufferStuffingJankyFrames = 0
SetFrameRate vote for this layer:
frameRate = 120.00
averageFPS = 112.500
present2present histogram is as below:
8ms=80 16ms=15 24ms=4 33ms=1 1000ms=0
latch2present histogram is as below:
10ms=100

layerName = VRI-StatusBar#3
totalFrames = 300
frameRate = 120.00
averageFPS = 120.000
present2present histogram is as below:
8ms=300
'@ -split "`n"

$parsed = ConvertFrom-AndroidSurfaceFlingerTimeStats -Lines $fixture -Package 'com.mystyle.purelive'
if ($parsed.layerName -notmatch '#2$') { throw 'The largest current app BLAST layer was not selected.' }
if ($parsed.totalFrames -ne 100 -or $parsed.histogramIntervals -ne 100) { throw 'Frame totals were not parsed.' }
if ($parsed.droppedFrames -ne 0 -or $parsed.lateAcquireFrames -ne 1 -or $parsed.badDesiredPresentFrames -ne 2) {
    throw 'Layer counters were not parsed.'
}
if ($parsed.displayRefreshRate -ne 120 -or $parsed.renderRate -ne 120 -or $parsed.frameRate -ne 120) {
    throw 'Refresh-rate counters were not parsed.'
}
if ($parsed.p50GapMs -ne 8 -or $parsed.p90GapMs -ne 16 -or $parsed.p95GapMs -ne 16 -or $parsed.p99GapMs -ne 24) {
    throw 'Histogram percentiles were not calculated.'
}
if ($parsed.longGapThresholdMs -ne 16 -or $parsed.longGapFrames -ne 20 -or $parsed.longGapPercent -ne 20) {
    throw 'Two-vsync gap totals were not calculated.'
}
if ($parsed.severeGapThresholdMs -ne 33 -or $parsed.severeGapFrames -ne 1 -or $parsed.maximumObservedGapMs -ne 33) {
    throw 'Severe gap totals were not calculated.'
}

$sched = ConvertFrom-AndroidMainThreadSchedStat -Before '1000000 2000000 10' -After '6000000 9000000 25'
if ($sched.runtimeMs -ne 5 -or $sched.runQueueDelayMs -ne 7 -or $sched.slices -ne 15) {
    throw 'Main-thread schedstat deltas were not calculated.'
}

$missingFailed = $false
try {
    ConvertFrom-AndroidSurfaceFlingerTimeStats -Lines @('layerName = VRI-StatusBar#1', 'totalFrames = 1') -Package 'com.mystyle.purelive' | Out-Null
} catch {
    $missingFailed = $_.Exception.Message -match 'no BLAST layer'
}
if (-not $missingFailed) { throw 'Missing target layers must stop the parser.' }

$emptyFailed = $false
try {
    ConvertFrom-AndroidSurfaceFlingerTimeStats -Lines @(
        'layerName = SurfaceView[com.mystyle.purelive/Main](BLAST)#1',
        'totalFrames = 1',
        'present2present histogram is as below:',
        '8ms=0'
    ) -Package 'com.mystyle.purelive' | Out-Null
} catch {
    $emptyFailed = $_.Exception.Message -match 'empty present2present histogram'
}
if (-not $emptyFailed) { throw 'Empty target histograms must stop the parser.' }

Write-Output 'PASS SurfaceFlinger timestats layer selection, counters, percentiles, gap thresholds and schedstat deltas'
