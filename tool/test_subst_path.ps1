$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resolve_subst_path.ps1')
$cases = @(
    @{Name='physical';Path='C:\work\pure_live';Mappings=@();Expected='C:\work\pure_live'},
    @{Name='subst';Path='P:\pure_live';Mappings=@('P:\: => C:\long workspace');Expected='C:\long workspace\pure_live'},
    @{Name='nested';Path='Q:\pure_live';Mappings=@('Q:\: => P:\','P:\: => C:\long workspace');Expected='C:\long workspace\pure_live'},
    @{Name='case';Path='p:\pure_live';Mappings=@('P:\: => C:\work');Expected='C:\work\pure_live'},
    @{Name='other-drive';Path='C:\pure_live';Mappings=@('P:\: => C:\work');Expected='C:\pure_live'},
    @{Name='root';Path='P:\';Mappings=@('P:\: => C:\work');Expected='C:\work'},
    @{Name='growing-cycle';Path='P:\pure_live';Mappings=@('P:\: => P:\work');Throws=$true},
    @{Name='cycle';Path='P:\pure_live';Mappings=@('P:\: => Q:\','Q:\: => P:\');Throws=$true}
)
foreach ($case in $cases) {
    $threw = $false
    try { $actual = Resolve-PureLiveSubstPath -Path $case.Path -Mappings $case.Mappings }
    catch { $threw = $true; if (-not $case.Throws) { throw } }
    if ($case.Throws) {
        if (-not $threw) { throw "$($case.Name): expected cycle failure" }
    } elseif ($actual.TrimEnd('\') -cne $case.Expected.TrimEnd('\')) {
        throw "$($case.Name): expected '$($case.Expected)', got '$actual'"
    }
    Write-Host "PASS $($case.Name)"
}
# Validate the changed wrapper without starting Flutter or touching build state.
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'flutterw.ps1'), [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { throw ($errors | Out-String) }
Write-Host 'PASS wrapper syntax'
