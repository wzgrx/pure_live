Set-StrictMode -Version Latest

function Get-AndroidNamedInteger {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $match = [regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Name) + ':\s*(\d+)')
    if (-not $match.Success) { return $null }
    [long] $match.Groups[1].Value
}

function Get-AndroidInlineInteger {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $match = [regex]::Match($Text, '(?m)(?:^|\s)' + [regex]::Escape($Name) + ':\s*(\d+)')
    if (-not $match.Success) { return $null }
    [long] $match.Groups[1].Value
}

function New-AndroidThreadSnapshotShellCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $ProcessId)

    if ($ProcessId -notmatch '^\d+$') {
        throw "Android process id must contain digits only: $ProcessId"
    }

    # A task can exit between glob expansion and reading its comm file. Treat
    # that single disappearing task as a skipped sample instead of failing the
    # whole resource run; errors from adb/su and the loop itself remain visible.
    'su -c ''for t in /proc/' + $ProcessId +
        '/task/*; do n=${t##*/}; c=$(cat "$t/comm" 2>/dev/null) || continue; printf "%s %s\n" "$n" "$c"; done'''
}

function ConvertFrom-AndroidProcessResourceText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]] $ProcStatusLines,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]] $MeminfoLines,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]] $FdLines,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]] $ThreadLines,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]] $SurfaceLayerLines,
        [Parameter(Mandatory = $true)][string] $Package,
        [int] $Cycle = 0,
        [string] $Phase = ''
    )

    $status = $ProcStatusLines -join "`n"
    $meminfo = $MeminfoLines -join "`n"
    $fdTargets = @(
        $FdLines | ForEach-Object {
            $match = [regex]::Match([string] $_, '\s->\s(.+)$')
            if ($match.Success) { $match.Groups[1].Value.Trim() }
        }
    )
    $threads = @(
        $ThreadLines | ForEach-Object {
            $match = [regex]::Match(([string] $_).Trim(), '^(\d+)\s+(.+)$')
            if ($match.Success) {
                [pscustomobject]@{ Tid = [long] $match.Groups[1].Value; Name = $match.Groups[2].Value.Trim() }
            }
        }
    )
    $packagePattern = [regex]::Escape($Package)
    $packageLayers = @($SurfaceLayerLines | Where-Object { [string] $_ -match $packagePattern })

    [pscustomobject][ordered]@{
        cycle = $Cycle
        phase = $Phase
        capturedAt = (Get-Date).ToString('o')
        vmSizeKb = Get-AndroidNamedInteger -Text $status -Name 'VmSize'
        vmRssKb = Get-AndroidNamedInteger -Text $status -Name 'VmRSS'
        rssAnonKb = Get-AndroidNamedInteger -Text $status -Name 'RssAnon'
        rssFileKb = Get-AndroidNamedInteger -Text $status -Name 'RssFile'
        vmDataKb = Get-AndroidNamedInteger -Text $status -Name 'VmData'
        vmSwapKb = Get-AndroidNamedInteger -Text $status -Name 'VmSwap'
        procThreads = Get-AndroidNamedInteger -Text $status -Name 'Threads'
        fdTableSize = Get-AndroidNamedInteger -Text $status -Name 'FDSize'
        totalPssKb = Get-AndroidInlineInteger -Text $meminfo -Name 'TOTAL PSS'
        totalRssKb = Get-AndroidInlineInteger -Text $meminfo -Name 'TOTAL RSS'
        totalSwapPssKb = Get-AndroidInlineInteger -Text $meminfo -Name 'TOTAL SWAP PSS'
        javaHeapKb = Get-AndroidInlineInteger -Text $meminfo -Name 'Java Heap'
        nativeHeapKb = Get-AndroidInlineInteger -Text $meminfo -Name 'Native Heap'
        graphicsKb = Get-AndroidInlineInteger -Text $meminfo -Name 'Graphics'
        views = Get-AndroidInlineInteger -Text $meminfo -Name 'Views'
        viewRoots = Get-AndroidInlineInteger -Text $meminfo -Name 'ViewRootImpl'
        activities = Get-AndroidInlineInteger -Text $meminfo -Name 'Activities'
        appContexts = Get-AndroidInlineInteger -Text $meminfo -Name 'AppContexts'
        assets = Get-AndroidInlineInteger -Text $meminfo -Name 'Assets'
        assetManagers = Get-AndroidInlineInteger -Text $meminfo -Name 'AssetManagers'
        localBinders = Get-AndroidInlineInteger -Text $meminfo -Name 'Local Binders'
        proxyBinders = Get-AndroidInlineInteger -Text $meminfo -Name 'Proxy Binders'
        parcelMemoryKb = Get-AndroidInlineInteger -Text $meminfo -Name 'Parcel memory'
        parcelCount = Get-AndroidInlineInteger -Text $meminfo -Name 'Parcel count'
        webViews = Get-AndroidInlineInteger -Text $meminfo -Name 'WebViews'
        fdCount = [long] $fdTargets.Count
        socketFds = [long] @($fdTargets | Where-Object { $_ -match '^socket:\[' }).Count
        pipeFds = [long] @($fdTargets | Where-Object { $_ -match '^pipe:\[' }).Count
        anonInodeFds = [long] @($fdTargets | Where-Object { $_ -match '^anon_inode:' }).Count
        dmaBufferFds = [long] @($fdTargets | Where-Object { $_ -match '(?i)dmabuf|dma_heap|/dev/ion' }).Count
        gpuDeviceFds = [long] @($fdTargets | Where-Object { $_ -match '(?i)/dev/(?:kgsl|dri)|mali' }).Count
        threadCount = [long] $threads.Count
        nativePlayerThreads = [long] @($threads | Where-Object {
            $_.Name -match '(?i)mpv|ffmpeg|media[_ -]?kit|fijk|ijk|vo/gpu|ao/'
        }).Count
        codecThreads = [long] @($threads | Where-Object { $_.Name -match '(?i)codec|omx|mediaextract|c2@' }).Count
        flutterThreads = [long] @($threads | Where-Object { $_.Name -match '(?i)flutter|dart|\.ui$|\.raster$|\.io$' }).Count
        packageLayers = [long] $packageLayers.Count
        packageBlastLayers = [long] @($packageLayers | Where-Object { $_ -match '(?i)BLAST' }).Count
    }
}

function Measure-AndroidResourceSeries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]] $Samples,
        [Parameter(Mandatory = $true)][string] $Property
    )

    $points = @(
        $Samples | ForEach-Object {
            $metric = $_.PSObject.Properties[$Property]
            $cycle = $_.PSObject.Properties['cycle']
            if ($null -ne $metric -and $null -ne $metric.Value -and $null -ne $cycle -and $null -ne $cycle.Value) {
                [pscustomobject]@{ X = [double] $cycle.Value; Y = [double] $metric.Value }
            }
        }
    )
    if ($points.Count -eq 0) {
        return [pscustomobject][ordered]@{ count = 0; first = $null; last = $null; minimum = $null; maximum = $null; delta = $null; slopePerCycle = $null }
    }

    $sumX = 0.0
    $sumY = 0.0
    $sumXY = 0.0
    $sumXX = 0.0
    foreach ($point in $points) {
        $sumX += $point.X
        $sumY += $point.Y
        $sumXY += $point.X * $point.Y
        $sumXX += $point.X * $point.X
    }
    $denominator = $points.Count * $sumXX - $sumX * $sumX
    $slope = if ($points.Count -gt 1 -and [math]::Abs($denominator) -gt 0.0000001) {
        ($points.Count * $sumXY - $sumX * $sumY) / $denominator
    } else {
        0.0
    }
    $values = @($points | ForEach-Object Y)
    [pscustomobject][ordered]@{
        count = $points.Count
        first = [long] $values[0]
        last = [long] $values[-1]
        minimum = [long] (($values | Measure-Object -Minimum).Minimum)
        maximum = [long] (($values | Measure-Object -Maximum).Maximum)
        delta = [long] ($values[-1] - $values[0])
        slopePerCycle = [math]::Round($slope, 3)
    }
}
