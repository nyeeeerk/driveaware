Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 512, 512
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::White)

$navy = [System.Drawing.ColorTranslator]::FromHtml("#110A70")
$white = [System.Drawing.Color]::White
$navyBrush = New-Object System.Drawing.SolidBrush $navy
$whiteBrush = New-Object System.Drawing.SolidBrush $white
$navyPen = New-Object System.Drawing.Pen $navy, 16
$navyPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$navyPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

# Draw Navy Eye shape
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddBezier(
    (New-Object System.Drawing.PointF 100, 256),
    (New-Object System.Drawing.PointF 180, 140),
    (New-Object System.Drawing.PointF 330, 140),
    (New-Object System.Drawing.PointF 412, 256)
)
$path.AddBezier(
    (New-Object System.Drawing.PointF 412, 256),
    (New-Object System.Drawing.PointF 330, 372),
    (New-Object System.Drawing.PointF 180, 372),
    (New-Object System.Drawing.PointF 100, 256)
)
$g.FillPath($navyBrush, $path)

# Iris white circle
$g.FillEllipse($whiteBrush, 206, 206, 100, 100)

# Pupil navy circle
$g.FillEllipse($navyBrush, 231, 231, 50, 50)

# Catchlight white dot
$g.FillEllipse($whiteBrush, 260, 222, 14, 14)

# Outer arrow stroke
$arrowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$arrowPath.AddBezier(
    (New-Object System.Drawing.PointF 240, 460),
    (New-Object System.Drawing.PointF 410, 270),
    (New-Object System.Drawing.PointF 490, 170),
    (New-Object System.Drawing.PointF 390, 60)
)
$arrowPath.AddBezier(
    (New-Object System.Drawing.PointF 390, 60),
    (New-Object System.Drawing.PointF 340, 20),
    (New-Object System.Drawing.PointF 210, 30),
    (New-Object System.Drawing.PointF 160, 40)
)
$g.DrawPath($navyPen, $arrowPath)

# Arrow head lines
$g.DrawLine($navyPen, 200, 16, 160, 40)
$g.DrawLine($navyPen, 160, 40, 192, 80)

$bmp.Save("assets/images/drive_aware_logo.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Host "PNG logo successfully generated!"
