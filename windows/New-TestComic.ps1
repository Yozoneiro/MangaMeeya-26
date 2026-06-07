param(
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'test-output')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$folder = Join-Path $OutputDir 'sample-folder'
$zipPath = Join-Path $OutputDir 'sample.cbz'
$tarPath = Join-Path $OutputDir 'sample.cbt'

if (Test-Path -LiteralPath $folder) {
    Remove-Item -LiteralPath $folder -Recurse -Force
}
New-Item -ItemType Directory -Path $folder | Out-Null
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $tarPath) {
    Remove-Item -LiteralPath $tarPath -Force
}

function New-SamplePage {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Drawing.Color]$BackColor,
        [Parameter(Mandatory)][System.Drawing.Color]$AccentColor
    )

    $bitmap = New-Object System.Drawing.Bitmap 900, 1300
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear($BackColor)

        $accentBrush = New-Object System.Drawing.SolidBrush $AccentColor
        $whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $fontTitle = New-Object System.Drawing.Font 'Segoe UI', 64, ([System.Drawing.FontStyle]::Bold)
        $fontSmall = New-Object System.Drawing.Font 'Segoe UI', 22
        try {
            $graphics.FillRectangle($accentBrush, 0, 0, 900, 180)
            $graphics.DrawString($Title, $fontTitle, $whiteBrush, 48, 42)
            $graphics.DrawString('MangaMeeya Cleanroom test page', $fontSmall, $whiteBrush, 52, 220)

            for ($i = 0; $i -lt 9; $i++) {
                $x = 70 + (($i % 3) * 260)
                $y = 340 + ([Math]::Floor($i / 3) * 240)
                $pen = New-Object System.Drawing.Pen $AccentColor, 8
                try {
                    $graphics.DrawRectangle($pen, $x, $y, 190, 150)
                    $graphics.DrawString(('{0:D2}' -f ($i + 1)), $fontSmall, $accentBrush, ($x + 58), ($y + 48))
                } finally {
                    $pen.Dispose()
                }
            }
        } finally {
            $fontSmall.Dispose()
            $fontTitle.Dispose()
            $whiteBrush.Dispose()
            $accentBrush.Dispose()
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$pages = @(
    @{ Name = 'page_10.png'; Title = 'Page 10'; Back = [System.Drawing.Color]::FromArgb(38, 44, 52); Accent = [System.Drawing.Color]::FromArgb(220, 88, 72) },
    @{ Name = 'page_2.png'; Title = 'Page 2'; Back = [System.Drawing.Color]::FromArgb(34, 48, 45); Accent = [System.Drawing.Color]::FromArgb(54, 179, 126) },
    @{ Name = 'page_1.png'; Title = 'Page 1'; Back = [System.Drawing.Color]::FromArgb(35, 39, 56); Accent = [System.Drawing.Color]::FromArgb(93, 146, 230) },
    @{ Name = 'page_11.png'; Title = 'Page 11'; Back = [System.Drawing.Color]::FromArgb(48, 39, 37); Accent = [System.Drawing.Color]::FromArgb(227, 170, 65) }
)

foreach ($page in $pages) {
    New-SamplePage `
        -Path (Join-Path $folder $page.Name) `
        -Title $page.Title `
        -BackColor $page.Back `
        -AccentColor $page.Accent
}

[System.IO.Compression.ZipFile]::CreateFromDirectory($folder, $zipPath)
$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tar) {
    & $tar.Source -cf $tarPath -C $folder .
    if ($LASTEXITCODE -ne 0) {
        throw 'tar.exe failed while creating sample.cbt'
    }
}

Write-Host "Created sample folder: $folder"
Write-Host "Created sample cbz:    $zipPath"
if (Test-Path -LiteralPath $tarPath) {
    Write-Host "Created sample cbt:    $tarPath"
}
