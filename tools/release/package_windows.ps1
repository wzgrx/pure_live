# Builds the Windows release and packs it as 3.x did (X01.3):
#   PureLive-<version>-<build>-windows-x64-portable.zip  (data in UserData beside the exe)
#   PureLive-<version>-<build>-windows-x64-setup.exe     (Inno Setup 6, same AppId as 3.x)
# Run on the Windows host from the repository root: pwsh tools\release\package_windows.ps1 [outDir]
param([string]$Out = "$PSScriptRoot\..\..\build\release")
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$flutter = if ($env:FLUTTER) { $env:FLUTTER } else { 'flutter' }
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$pubspec = Get-Content "$root\apps\pure_live\pubspec.yaml" | Select-String '^version: ([0-9.]+)\+([0-9]+)$'
$version = $pubspec.Matches[0].Groups[1].Value; $build = $pubspec.Matches[0].Groups[2].Value
$name = "PureLive-$version-$build-windows-x64"
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = Resolve-Path $Out
& pwsh -NoProfile -File "$root\tools\ffmpeg_kit\fetch.ps1" windows | Out-Null
Push-Location "$root\apps\pure_live"
& $flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
Pop-Location
$release = "$root\apps\pure_live\build\windows\x64\runner\Release"
# A clean copy: no UserData or logs from a test run.
$stage = Join-Path ([IO.Path]::GetTempPath()) "$name-portable"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $release $stage
Remove-Item -Recurse -Force "$stage\UserData" -ErrorAction SilentlyContinue
Compress-Archive -Path "$stage\*" -DestinationPath "$Out\$name-portable.zip" -Force
if ($iscc) {
  & $iscc "/DSourceDir=$stage" "/DAppVersion=$version" "/DArtifactVersion=$version-$build" "/DOutputDir=$Out" "$root\apps\pure_live\windows\packaging\exe\pure_live.iss" | Select-Object -Last 3
} else {
  Write-Warning 'Inno Setup 6 not found: no setup.exe'
}
Get-ChildItem $Out -Filter "$name*" | ForEach-Object { "$($_.Name) $($_.Length)" }
