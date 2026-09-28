# Draws app_icon.ico: the preview (.next) icon of principles §3.1, a white
# TV with antennas and a negative-space play triangle on the brand night
# blue, from the geometry of android/app/src/main/res/drawable/
# ic_launcher_foreground.xml (108-unit canvas). Sizes 16-256 as PNG
# entries; 16 and 20 drop the antennas and fill more of the square.
#
#   pwsh -File make_icon.ps1 [-Out app_icon.ico]
param([string]$Out = (Join-Path $PSScriptRoot 'app_icon.ico'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$night = [System.Drawing.Color]::FromArgb(255, 0x0B, 0x1B, 0x3F)
$white = [System.Drawing.Color]::White

function RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Render([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)
  $small = $size -le 20
  # The part of the 108-unit canvas shown: the art with a margin; tighter
  # when small so the screen stays readable.
  $from = if ($small) { 24.0 } else { 18.0 }
  $span = 108.0 - 2 * $from
  $k = $size / $span
  function X([double]$u) { [float](($u - $from) * $k) }

  $bg = RoundedRect 0 0 $size $size ([float]($size * 0.22))
  $g.FillPath((New-Object System.Drawing.SolidBrush $night), $bg)

  if (-not $small) {
    $pen = New-Object System.Drawing.Pen $white, ([float](3.2 * $k))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawLine($pen, (X 47), (X 37), (X 40), (X 29))
    $g.DrawLine($pen, (X 61), (X 37), (X 68), (X 29))
  }
  $screen = RoundedRect (X 30) (X 38) ([float](48 * $k)) ([float](37 * $k)) ([float](6 * $k))
  $g.FillPath((New-Object System.Drawing.SolidBrush $white), $screen)
  $play = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF (X 49), (X 48.5)),
    (New-Object System.Drawing.PointF (X 63), (X 56.5)),
    (New-Object System.Drawing.PointF (X 49), (X 64.5))
  )
  $g.FillPolygon((New-Object System.Drawing.SolidBrush $night), $play)
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return , $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$images = foreach ($s in $sizes) { , (Render $s) }
$fs = [System.IO.File]::Create($Out)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $data = $images[$i]
  $dim = if ($s -ge 256) { 0 } else { $s }
  $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32)
  $w.Write([uint32]$data.Length); $w.Write([uint32]$offset)
  $offset += $data.Length
}
foreach ($data in $images) { $w.Write($data) }
$w.Close()
"wrote $Out ($((Get-Item $Out).Length) bytes, sizes $($sizes -join ' '))"
