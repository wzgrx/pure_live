$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows_runtime_metrics.ps1')

$cases = @(
    @{ Name = 'first observation'; Current = 10.0; Previous = $null; Elapsed = 0.1; Expected = $null },
    @{ Name = 'one busy core'; Current = 13.0; Previous = 10.0; Elapsed = 3.0; Expected = 4.1667 },
    @{ Name = 'genuine idle'; Current = 10.0; Previous = 10.0; Elapsed = 3.0; Expected = 0.0 },
    @{ Name = 'zero interval'; Current = 13.0; Previous = 10.0; Elapsed = 0.0; Expected = $null },
    @{ Name = 'backward interval'; Current = 13.0; Previous = 10.0; Elapsed = -1.0; Expected = $null },
    @{ Name = 'counter reset'; Current = 9.0; Previous = 10.0; Elapsed = 3.0; Expected = $null },
    @{ Name = 'missing current'; Current = $null; Previous = 10.0; Elapsed = 3.0; Expected = $null },
    @{ Name = 'invalid clock'; Current = 13.0; Previous = 10.0; Elapsed = [double]::NaN; Expected = $null },
    @{ Name = 'invalid counter'; Current = [double]::PositiveInfinity; Previous = 10.0; Elapsed = 3.0; Expected = $null }
)
foreach ($case in $cases) {
    $actual = Get-PureLiveIntervalCpuPercent -CurrentCpuSeconds $case.Current `
        -PreviousCpuSeconds $case.Previous -ElapsedSeconds $case.Elapsed -LogicalProcessors 24
    if ($actual -ne $case.Expected) { throw "CPU metric case failed: $($case.Name), actual=$actual" }
}

# Exercise the production summary, not a separately copied averaging formula.
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'sample_windows_runtime.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Get-Percentile', 'Get-LinearSlopePerMinute', 'Get-MetricSummary')) {
    $definition = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($null -eq $definition) { throw "Missing production function: $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
$summary = Get-MetricSummary -Property cpu_percent -Samples @(
    [pscustomobject]@{ elapsed_seconds = 0; cpu_percent = $null },
    [pscustomobject]@{ elapsed_seconds = 3; cpu_percent = 4.0 },
    [pscustomobject]@{ elapsed_seconds = 6; cpu_percent = 4.0 }
)
if ($summary.average -ne 4.0 -or $summary.minimum -ne 4.0) {
    throw 'Invalid baseline diluted the production CPU summary'
}
Write-Output 'Windows runtime CPU metrics: 10/10 passed'
