[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$mapPath = Join-Path $PSScriptRoot 'device_ui_map.json'
$runnerPath = Join-Path $PSScriptRoot 'android_ui.ps1'
$map = Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profile = $map.profiles.k90pro_portrait_1200x2608
$sequence = @($profile.sequences.open_pip_danmaku_settings)
$zhMenu = -join ([char[]]@(0x83DC, 0x5355))
$zhSettings = -join ([char[]]@(0x8BBE, 0x7F6E))
$zhPipDanmaku = -join ([char[]]@(0x5C0F, 0x7A97, 0x5F39, 0x5E55))
$zhStylePreview = -join ([char[]]@(0x6837, 0x5F0F, 0x9884, 0x89C8))

$semanticSteps = @($sequence | Where-Object { $_.PSObject.Properties['tapSemantic'] })
if ($semanticSteps.Count -ne 3) {
    throw 'open_pip_danmaku_settings must use live semantics for Menu, Settings, and the PiP settings tile.'
}
$routeAliasGroups = @(
    [pscustomobject]@{ Values = @($zhMenu, 'Menu') },
    [pscustomobject]@{ Values = @($zhSettings, 'Settings') },
    [pscustomobject]@{ Values = @($zhPipDanmaku, 'PiP Danmaku') }
)
for ($index = 0; $index -lt $semanticSteps.Count; $index++) {
    $actualAliases = @($semanticSteps[$index].tapSemantic | ForEach-Object { [string]$_ })
    foreach ($alias in $routeAliasGroups[$index].Values) {
        if ($actualAliases -notcontains $alias) {
            throw "open_pip_danmaku_settings step $index is missing route alias '$alias'."
        }
    }
}
if (@($sequence | Where-Object { $_.PSObject.Properties['tap'] }).Count -ne 0) {
    throw 'open_pip_danmaku_settings still contains a cached-coordinate tap.'
}
Write-Output 'PASS PiP settings route uses live semantics for every tap'

$assertStep = @($sequence | Where-Object { $_.PSObject.Properties['assertSemantic'] }) | Select-Object -Last 1
if ($null -eq $assertStep) {
    throw 'open_pip_danmaku_settings must assert a destination-only semantic after the tap.'
}
$assertAliases = @($assertStep.assertSemantic | ForEach-Object { [string]$_ })
foreach ($alias in @($zhStylePreview, 'Style Preview')) {
    if ($assertAliases -notcontains $alias) {
        throw "open_pip_danmaku_settings is missing destination alias '$alias'."
    }
}
Write-Output 'PASS PiP settings route verifies the destination page'

$point = $profile.points.'settings.pip_danmaku'
if ($point.x -ne 600 -or $point.y -ne 2006 -or (@($point.bounds) -join ',') -ne '48,1874,1152,2138') {
    throw 'K90 PiP settings cache does not match the measured 2026-09-12 accessibility bounds.'
}
Write-Output 'PASS K90 PiP settings cache matches measured bounds'

& $runnerPath -Validate -Profile 'k90pro_portrait_1200x2608'
Write-Output 'PASS android_ui accepts semantic route assertions'

& python (Join-Path $PSScriptRoot 'validate_device_ui_map.py')
if ($LASTEXITCODE -ne 0) {
    throw "validate_device_ui_map.py exited with code $LASTEXITCODE."
}
Write-Output 'PASS device UI map schema accepts semantic route assertions'
