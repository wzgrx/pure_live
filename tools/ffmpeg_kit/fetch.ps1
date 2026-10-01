# Windows counterpart of fetch.sh: downloads the recorder's FFmpeg bundles
# (bundles.txt) once into a cache outside the repository, checks their
# SHA-256 and copies them into <repo>\.ffmpeg_kit\ (a copy: symbolic links
# need developer mode on Windows).
#
#   pwsh tools\ffmpeg_kit\fetch.ps1           # every bundle
#   pwsh tools\ffmpeg_kit\fetch.ps1 windows   # only names containing "windows"
#
# Cache: $env:PURE_LIVE_FFMPEG_KIT_CACHE, else %LOCALAPPDATA%\pure_live\ffmpeg_kit.
param([string]$Filter = '')
$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$cache = if ($env:PURE_LIVE_FFMPEG_KIT_CACHE) { $env:PURE_LIVE_FFMPEG_KIT_CACHE } else { Join-Path $env:LOCALAPPDATA 'pure_live\ffmpeg_kit' }
$target = Join-Path $root '.ffmpeg_kit'
New-Item -ItemType Directory -Force -Path $cache, $target | Out-Null

function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant() }

foreach ($line in Get-Content (Join-Path $root 'tools\ffmpeg_kit\bundles.txt')) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $name, $hash, $url = $line -split "`t"
    if ($Filter -and -not $name.Contains($Filter)) { continue }
    $file = Join-Path $cache $name
    if (-not (Test-Path $file) -or (Get-Sha $file) -ne $hash) {
        Write-Host "ffmpeg_kit: downloading $name"
        Invoke-WebRequest -Uri $url -OutFile "$file.part"
        if ((Get-Sha "$file.part") -ne $hash) {
            Remove-Item "$file.part"
            throw "ffmpeg_kit: $name does not match its SHA-256"
        }
        Move-Item -Force "$file.part" $file
    }
    $copy = Join-Path $target $name
    if (-not (Test-Path $copy) -or (Get-Sha $copy) -ne $hash) { Copy-Item -Force $file $copy }
    Write-Host "ffmpeg_kit: $name ready"
}
