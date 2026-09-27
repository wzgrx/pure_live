[CmdletBinding()]
param(
    [ValidateSet('DIRECT', 'PROXY')]
    [string] $RouteMode = 'DIRECT',
    [string] $ProxyEndpoint = '127.0.0.1:7897',
    [ValidateRange(1, 10)]
    [int] $Cycles = 10,
    [ValidateRange(5, 90)]
    [int] $ObservationSeconds = 5,
    [string[]] $Platforms = @('bilibili', 'huya', 'douyin'),
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'build_resource_guard.ps1')

$supported = @('bilibili', 'huya', 'douyin')
$normalizedPlatforms = @(
    $Platforms |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -ne '' } |
        Select-Object -Unique
)
if ($normalizedPlatforms.Count -eq 0) {
    throw 'At least one platform is required.'
}
$unsupported = @($normalizedPlatforms | Where-Object { $_ -notin $supported })
if ($unsupported.Count -gt 0) {
    throw "Unsupported probe platform(s): $($unsupported -join ', ')"
}

if ($RouteMode -eq 'PROXY' -and $ProxyEndpoint -notmatch '^[^\s:]+:\d{1,5}$') {
    throw 'ProxyEndpoint must use host:port form.'
}
$route = if ($RouteMode -eq 'PROXY') { "PROXY $ProxyEndpoint" } else { 'DIRECT' }
$outputRoot = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $repoRoot 'local-artifacts\danmaku-probes'
} else {
    [IO.Path]::GetFullPath($OutputDirectory, $repoRoot)
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$slug = ($normalizedPlatforms -join '-')
$resultPath = Join-Path $outputRoot "$stamp-$slug-$($RouteMode.ToLowerInvariant())-$($Cycles)cycle.json"
$logPath = [IO.Path]::ChangeExtension($resultPath, '.log')
$probePath = Join-Path $repoRoot 'tool\probes\danmaku_connection_matrix_probe_test.dart'
$started = [DateTime]::UtcNow
$lease = $null
$monitor = $null
$resources = $null
$activeAfter = $null
$exitCode = 1
$environmentNames = @(
    'PURELIVE_DANMAKU_PROBE',
    'PURELIVE_DANMAKU_ROUTE',
    'PURELIVE_DANMAKU_SECONDS',
    'PURELIVE_DANMAKU_CYCLES',
    'PURELIVE_DANMAKU_PLATFORMS',
    'PURELIVE_DANMAKU_OUTPUT'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

Push-Location $repoRoot
try {
    $lease = Enter-PureLiveHeavyTaskSlot -TaskName 'danmaku-connection-probe'
    $monitor = Start-PureLiveResourceMonitor
    $env:PURELIVE_DANMAKU_PROBE = '1'
    $env:PURELIVE_DANMAKU_ROUTE = $route
    $env:PURELIVE_DANMAKU_SECONDS = $ObservationSeconds.ToString()
    $env:PURELIVE_DANMAKU_CYCLES = $Cycles.ToString()
    $env:PURELIVE_DANMAKU_PLATFORMS = $normalizedPlatforms -join ','
    $env:PURELIVE_DANMAKU_OUTPUT = $resultPath

    & (Join-Path $PSScriptRoot 'flutterw.ps1') test --no-pub --concurrency=1 $probePath 2>&1 |
        Tee-Object -FilePath $logPath
    $exitCode = $LASTEXITCODE
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    if ($monitor) {
        $resources = Stop-PureLiveResourceMonitor -Job $monitor
    }
    if ($lease) {
        $activeAfter = Wait-PureLiveBackgroundCpuSettle
        Exit-PureLiveHeavyTaskSlot -Lease $lease
    }
    Pop-Location
}

$record = [ordered]@{
    schema_version = 1
    task = 'danmaku-connection-probe'
    command = ".\tool\run_danmaku_connection_probe.ps1 -RouteMode $RouteMode -Cycles $Cycles -ObservationSeconds $ObservationSeconds -Platforms $($normalizedPlatforms -join ',')"
    source_commit = (git -C $repoRoot rev-parse HEAD)
    probe_source_sha256 = (Get-FileHash -LiteralPath $probePath -Algorithm SHA256).Hash
    runner_source_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    started_at_utc = $started.ToString('o')
    duration_seconds = [Math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 3)
    status = if ($exitCode -eq 0) { 'succeeded' } else { 'failed' }
    exit_code = $exitCode
    route = $route
    platforms = $normalizedPlatforms
    cycles = $Cycles
    observation_seconds = $ObservationSeconds
    actual_adb_commands = 0
    peak_resources = $resources
    active_heavy_processes_after = $activeAfter
    outputs = @($resultPath, $logPath)
    automatic_follow_up = $false
}
$recordPath = Write-PureLiveTaskRecord -RepoRoot $repoRoot -Record $record
Write-Host "Danmaku probe result: $resultPath"
Write-Host "Danmaku probe record: $recordPath"
exit $exitCode
