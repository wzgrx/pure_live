$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android_process_resource_metrics.ps1')

function Assert-Equal {
    param([Parameter(Mandatory = $true)] $Actual, [Parameter(Mandatory = $true)] $Expected, [string] $Label)
    if ($Actual -ne $Expected) { throw "$Label expected '$Expected' but received '$Actual'." }
}

$snapshot = ConvertFrom-AndroidProcessResourceText `
    -ProcStatusLines @(
        'Name: pure_live',
        'FDSize: 512',
        'VmSize: 123456 kB',
        'VmRSS: 654321 kB',
        'RssAnon: 600000 kB',
        'RssFile: 54321 kB',
        'VmData: 777777 kB',
        'VmSwap: 42 kB',
        'Threads: 137'
    ) `
    -MeminfoLines @(
        'TOTAL PSS: 500000 TOTAL RSS: 700000 TOTAL SWAP PSS: 123',
        ' Java Heap: 10000',
        ' Native Heap: 20000',
        ' Graphics: 30000',
        ' Views: 88 ViewRootImpl: 2',
        ' AppContexts: 4 Activities: 1',
        ' Assets: 9 AssetManagers: 3',
        ' Local Binders: 22 Proxy Binders: 17',
        ' Parcel memory: 12 Parcel count: 44',
        ' WebViews: 0'
    ) `
    -FdLines @(
        'lrwx------ 1 u0_a1 u0_a1 64 0 -> socket:[10]',
        'lrwx------ 1 u0_a1 u0_a1 64 1 -> pipe:[11]',
        'lrwx------ 1 u0_a1 u0_a1 64 2 -> anon_inode:[eventpoll]',
        'lrwx------ 1 u0_a1 u0_a1 64 3 -> /dev/dma_heap/system',
        'lrwx------ 1 u0_a1 u0_a1 64 4 -> /dev/kgsl-3d0',
        'lr-x------ 1 u0_a1 u0_a1 64 5 -> /data/app/base.apk'
    ) `
    -ThreadLines @('100 pure_live', '101 1.ui', '102 mpv/vo', '103 CCodecLooper') `
    -SurfaceLayerLines @(
        'com.mystyle.purelive/com.mystyle.purelive.MainActivity#12',
        'SurfaceView[com.mystyle.purelive] BLAST#13',
        'other.package BLAST#14'
    ) `
    -Package 'com.mystyle.purelive' -Cycle 10 -Phase 'fixture'

Assert-Equal $snapshot.cycle 10 'cycle'
Assert-Equal $snapshot.vmRssKb 654321 'VmRSS'
Assert-Equal $snapshot.totalPssKb 500000 'TOTAL PSS'
Assert-Equal $snapshot.totalRssKb 700000 'TOTAL RSS'
Assert-Equal $snapshot.viewRoots 2 'ViewRootImpl'
Assert-Equal $snapshot.activities 1 'Activities'
Assert-Equal $snapshot.fdCount 6 'FD count'
Assert-Equal $snapshot.socketFds 1 'socket count'
Assert-Equal $snapshot.dmaBufferFds 1 'dma buffer count'
Assert-Equal $snapshot.gpuDeviceFds 1 'GPU device count'
Assert-Equal $snapshot.threadCount 4 'thread count'
Assert-Equal $snapshot.nativePlayerThreads 1 'native player thread count'
Assert-Equal $snapshot.codecThreads 1 'codec thread count'
Assert-Equal $snapshot.packageLayers 2 'package layer count'
Assert-Equal $snapshot.packageBlastLayers 1 'package BLAST layer count'

$series = Measure-AndroidResourceSeries -Samples @(
    [pscustomobject]@{ cycle = 0; fdCount = 10 },
    [pscustomobject]@{ cycle = 5; fdCount = 15 },
    [pscustomobject]@{ cycle = 10; fdCount = 20 }
) -Property 'fdCount'
Assert-Equal $series.count 3 'series count'
Assert-Equal $series.first 10 'series first'
Assert-Equal $series.last 20 'series last'
Assert-Equal $series.delta 10 'series delta'
Assert-Equal $series.slopePerCycle 1 'series slope'

$empty = Measure-AndroidResourceSeries -Samples @([pscustomobject]@{ cycle = 1 }) -Property 'missing'
Assert-Equal $empty.count 0 'empty series count'
if ($null -ne $empty.last) { throw 'Empty series must keep last null.' }

Write-Output 'PASS Android process, meminfo, FD, thread, SurfaceFlinger and trend parsers'
