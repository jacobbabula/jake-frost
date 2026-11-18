param([Parameter(Mandatory=$true)][string]$OutputDirectory,
      [string]$IconPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$dest=[IO.Directory]::CreateDirectory($OutputDirectory).FullName
function Paint-Frostflake([int]$size,[string]$file) {
    $bitmap=New-Object Drawing.Bitmap $size,$size
    $g=[Drawing.Graphics]::FromImage($bitmap)
    try {
        $g.SmoothingMode='AntiAlias'
        $g.ScaleTransform($size/256.0,$size/256.0)
        $g.TranslateTransform(128,128)
        $back=[Drawing.Drawing2D.GraphicsPath]::new()
        foreach($corner in @(@(-120,-120,180),@(60,-120,270),@(60,60,0),@(-120,60,90))) {
            $back.AddArc($corner[0],$corner[1],60,60,$corner[2],90)
        }
        $back.CloseFigure()
        $gradient=[Drawing.Drawing2D.LinearGradientBrush]::new([Drawing.Point]::new(-100,-114),[Drawing.Point]::new(88,130),
            [Drawing.ColorTranslator]::FromHtml('#459BD1'),[Drawing.ColorTranslator]::FromHtml('#125386'))
        $g.FillPath($gradient,$back)
        $stroke=[Drawing.Pen]::new([Drawing.Color]::FromArgb(255,243,254,255),9)
        $stroke.StartCap=$stroke.EndCap='Round'
        for($arm=0;$arm -lt 6;$arm++) {
            $g.DrawLine($stroke,0,0,0,-85)
            $g.DrawLine($stroke,0,-50,-21,-68)
            $g.DrawLine($stroke,0,-50,21,-68)
            if($size -ge 32) {$g.DrawLine($stroke,0,-26,-14,-38);$g.DrawLine($stroke,0,-26,14,-38)}
            $g.RotateTransform(60)
        }
        $g.FillEllipse([Drawing.Brushes]::White,-8,-8,16,16)
        $bitmap.Save($file,[Drawing.Imaging.ImageFormat]::Png)
        $stroke.Dispose();$gradient.Dispose();$back.Dispose()
    } finally {$g.Dispose();$bitmap.Dispose()}
}
foreach ($entry in @(@('StoreLogo',50),@('Square44x44Logo',44),@('Square150x150Logo',150),@('StoreListingLogo',300))) {
    Paint-Frostflake $entry[1] (Join-Path $dest ($entry[0]+'.png'))
}
if($IconPath) {
    $images=@(foreach($size in 16,24,32,48,64,128,256) {
        $file=Join-Path $dest "icon-$size.png";Paint-Frostflake $size $file
        [pscustomobject]@{Size=$size;Bytes=[IO.File]::ReadAllBytes($file)}
    })
    $writer=[IO.BinaryWriter]::new([IO.File]::Create($IconPath))
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
        $offset=6+16*$images.Count
        foreach ($img in $images) {
            $dim=[byte]($img.Size%256);$writer.Write($dim);$writer.Write($dim)
            $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]32)
            $writer.Write([uint32]$img.Bytes.Length);$writer.Write([uint32]$offset);$offset+=$img.Bytes.Length
        }
        foreach($img in $images){$writer.Write([byte[]]$img.Bytes)}
    } finally {$writer.Dispose()}
}
