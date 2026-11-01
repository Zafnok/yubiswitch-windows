# Regenerates assets\locked.ico and assets\unlocked.ico. Run with Windows PowerShell.
Add-Type -AssemblyName System.Drawing

function Draw-Key([int]$size, [Drawing.Color]$color) {
    $bitmap = New-Object Drawing.Bitmap $size, $size
    $g = [Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.ScaleTransform($size / 32, $size / 32)
    $brush = New-Object Drawing.SolidBrush $color

    # USB connector
    $g.FillRectangle($brush, 0, 10, 10, 12)

    # Fob body
    $body = New-Object Drawing.Drawing2D.GraphicsPath
    $body.AddArc(8, 6, 8, 8, 180, 90)
    $body.AddArc(24, 6, 8, 8, 270, 90)
    $body.AddArc(24, 18, 8, 8, 0, 90)
    $body.AddArc(8, 18, 8, 8, 90, 90)
    $body.CloseFigure()
    $g.FillPath($brush, $body)

    # Cut out the touch contact, and add finer details where there is room
    $g.CompositingMode = 'SourceCopy'
    $clear = New-Object Drawing.SolidBrush ([Drawing.Color]::Transparent)
    $g.FillEllipse($clear, 12, 10, 12, 12)
    if ($size -ge 24) {
        $g.CompositingMode = 'SourceOver'
        $g.FillEllipse($brush, 15, 13, 6, 6)
        $g.CompositingMode = 'SourceCopy'
        $g.FillEllipse($clear, 26, 14, 4, 4)
    }
    if ($size -ge 32) {
        $g.FillRectangle($clear, 2, 12, 4, 2)
        $g.FillRectangle($clear, 2, 18, 4, 2)
    }

    $g.Dispose()
    return $bitmap
}

function Write-Ico([string]$path, [Drawing.Color]$color) {
    $sizes = 16, 20, 24, 32, 40, 48, 64, 256
    $images = foreach ($size in $sizes) {
        $bitmap = Draw-Key $size $color
        $stream = New-Object IO.MemoryStream
        if ($size -ge 256) {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        } else {
            # System.Drawing.Icon can't read PNG frames at these sizes, so write a classic DIB frame.
            $dib = New-Object IO.BinaryWriter $stream
            $maskStride = [int][Math]::Ceiling($size / 32) * 4
            $dib.Write([uint32]40)
            $dib.Write([int32]$size)
            $dib.Write([int32]($size * 2))
            $dib.Write([uint16]1)
            $dib.Write([uint16]32)
            $dib.Write([uint32]0)
            $dib.Write([uint32]($size * $size * 4 + $maskStride * $size))
            $dib.Write([byte[]](New-Object byte[] 16))
            for ($y = $size - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $size; $x++) { $dib.Write([int32]$bitmap.GetPixel($x, $y).ToArgb()) }
            }
            $dib.Write([byte[]](New-Object byte[] ($maskStride * $size)))
            $dib.Flush()
        }
        $bitmap.Dispose()
        , $stream.ToArray()
    }

    $out = New-Object IO.BinaryWriter ([IO.File]::Create($path))
    $out.Write([uint16]0)
    $out.Write([uint16]1)
    $out.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dimension = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $out.Write([byte]$dimension)
        $out.Write([byte]$dimension)
        $out.Write([uint16]0)
        $out.Write([uint16]1)
        $out.Write([uint16]32)
        $out.Write([uint32]$images[$i].Length)
        $out.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($image in $images) { $out.Write([byte[]]$image) }
    $out.Dispose()
}

$assets = Join-Path $PSScriptRoot '..\assets'
New-Item -ItemType Directory -Force $assets | Out-Null
$assets = (Resolve-Path $assets).Path
Write-Ico (Join-Path $assets 'locked.ico') ([Drawing.Color]::FromArgb(142, 142, 142))
Write-Ico (Join-Path $assets 'unlocked.ico') ([Drawing.Color]::FromArgb(50, 205, 50))
