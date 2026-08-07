param(
    [string]$Src = "",
    [string]$Dest = "",
    [int]$Size = 160
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $Src -or -not $Dest) { exit 1 }

$script:player = $null

function Try-FFmpeg {
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ff) { return $false }
    $tmp = "$Dest.tmp"
    & $ff.Source -y -ss 1 -i $Src -vframes 1 -vf ("scale={0}:-2" -f $Size) -f image2 $tmp 2>$null | Out-Null
    if (Test-Path -LiteralPath $tmp) {
        Move-Item -LiteralPath $tmp -Destination $Dest -Force
        return $true
    }
    return $false
}

function Try-WPF {
    $script:player = New-Object System.Windows.Media.MediaPlayer
    $script:player.Volume = 0.0
    $script:player.IsMuted = $true
    $script:player.Open((New-Object Uri($Src)))
    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 150
        if ($script:player.NaturalDuration.HasTimeSpan) { break }
    }
    $script:player.Play()
    Start-Sleep -Milliseconds 500
    $script:player.Position = [TimeSpan]::FromMilliseconds(1000)
    Start-Sleep -Milliseconds 500
    $w = $Size
    $h = [int]($w * 9.0 / 16.0)
    if ($h -lt 1) { $h = 1 }
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawVideo($script:player, (New-Object System.Windows.Rect(0, 0, $w, $h)))
    $dc.Close()
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.JpegBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Dest)
    try { $enc.Save($fs) } finally { $fs.Close() }
    return (Test-Path -LiteralPath $Dest)
}

try {
    if (Try-FFmpeg) { exit 0 }
    Add-Type -AssemblyName PresentationCore, WindowsBase
    if (Try-WPF) { exit 0 }
}
catch {}
finally {
    if ($script:player) {
        try { $script:player.Stop() } catch {}
        try { $script:player.Close() } catch {}
    }
}
exit 1
