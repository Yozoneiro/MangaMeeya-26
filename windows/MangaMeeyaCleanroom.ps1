param(
    [Parameter(Position = 0)]
    [string]$OpenPath,

    [switch]$SelfTest,

    [string]$SmokeTestPath,

    [string]$SmokeOut,

    [switch]$SmokeThumbnails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    Add-Type -AssemblyName Microsoft.VisualBasic
} catch {
}

$script:WicAvailable = $false
try {
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName PresentationCore
    $script:WicAvailable = $true
} catch {
    $script:WicAvailable = $false
}

$script:SupportedImageExtensions = @(
    '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff', '.webp'
)
$script:ZipArchiveExtensions = @('.zip', '.cbz')
$script:TarArchiveExtensions = @('.tar', '.cbt')
$script:SevenZipArchiveExtensions = @('.7z', '.cb7', '.rar', '.cbr')

$script:Pages = @()
$script:CurrentIndex = 0
$script:FitMode = 'Window'
$script:DoublePage = $false
$script:RightToLeft = $true
$script:Fullscreen = $false
$script:Zoom = 1.0
$script:LastWindowBounds = $null
$script:LoadedImage = $null
$script:Form = $null
$script:Panel = $null
$script:Picture = $null
$script:Status = $null
$script:OpenLabel = $null
$script:Split = $null
$script:PageList = $null
$script:RecentMenu = $null
$script:BookmarkMenu = $null
$script:SlideshowTimer = $null
$script:SlideshowMenuItem = $null
$script:CurrentSourcePath = $null
$script:WindowWidth = 1200
$script:WindowHeight = 850
$script:PageListVisible = $true
$script:ThumbnailListMode = $false
$script:SlideshowRunning = $false
$script:SlideshowIntervalSeconds = 5
$script:SuppressPageListEvent = $false
$script:MouseDown = $false
$script:MousePanning = $false
$script:MouseDownPoint = $null
$script:MouseDownScroll = $null
$script:MouseDownButton = $null
$script:AppRoot = Split-Path -Parent $PSScriptRoot
$script:SettingsDir = Join-Path $script:AppRoot 'portable-data'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:ExternalArchiveCacheDir = Join-Path $script:SettingsDir 'archive-cache'
$script:RecentPaths = @()
$script:LastPositions = @{}
$script:Bookmarks = @{}
$script:PageCache = @{}
$script:CacheOrder = New-Object 'System.Collections.Generic.List[string]'
$script:CacheRadius = 3
$script:CacheLimit = 10
$script:ThumbnailCache = @{}

function Get-DebugLogPath {
    return (Join-Path $script:SettingsDir 'debug.log')
}

function Get-AppVersion {
    $versionPath = Join-Path $script:AppRoot 'VERSION'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        return ((Get-Content -LiteralPath $versionPath -Raw).Trim())
    }
    return 'dev'
}

function Write-AppLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [object]$ErrorRecord = $null
    )

    try {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add(('[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK'), $Message))

        if ($null -ne $ErrorRecord) {
            if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
                if ($ErrorRecord.Exception) {
                    $lines.Add(('  Exception: {0}: {1}' -f $ErrorRecord.Exception.GetType().FullName, $ErrorRecord.Exception.Message))
                }
                if ($ErrorRecord.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.InvocationInfo.PositionMessage)) {
                    $lines.Add(('  Position: {0}' -f ($ErrorRecord.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')))
                }
                if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
                    $lines.Add(('  ScriptStackTrace: {0}' -f ($ErrorRecord.ScriptStackTrace -replace "`r?`n", ' | ')))
                }
            } elseif ($ErrorRecord -is [System.Exception]) {
                $lines.Add(('  Exception: {0}: {1}' -f $ErrorRecord.GetType().FullName, $ErrorRecord.Message))
                if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.StackTrace)) {
                    $lines.Add(('  StackTrace: {0}' -f ($ErrorRecord.StackTrace -replace "`r?`n", ' | ')))
                }
            } else {
                $lines.Add(('  Detail: {0}' -f ([string]$ErrorRecord)))
            }
        }

        Add-Content -LiteralPath (Get-DebugLogPath) -Value ($lines.ToArray()) -Encoding UTF8
    } catch {
        # Logging must never interrupt the reader.
    }
}

function Get-AppErrorMessage {
    param([Parameter(Mandatory)][object]$ErrorRecord)

    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord] -and $ErrorRecord.Exception) {
        return $ErrorRecord.Exception.Message
    }
    if ($ErrorRecord -is [System.Exception]) {
        return $ErrorRecord.Message
    }
    return ([string]$ErrorRecord)
}

function Show-AppError {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object]$ErrorRecord
    )

    Write-AppLog -Message $Title -ErrorRecord $ErrorRecord
    $message = Get-AppErrorMessage $ErrorRecord
    $body = "{0}`n`nDetails were written to:`n{1}" -f $message, (Get-DebugLogPath)
    if ($script:Form) {
        [System.Windows.Forms.MessageBox]::Show($script:Form, $body, $Title) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show($body, $Title) | Out-Null
    }
}

function Invoke-AppAction {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    try {
        & $Action
    } catch {
        Show-AppError -Title $Title -ErrorRecord $_
    }
}

function Get-NaturalSortKey {
    param([Parameter(Mandatory)][string]$Text)

    $lower = $Text.ToLowerInvariant()
    return [regex]::Replace($lower, '\d+', {
        param($Match)

        $raw = $Match.Value
        $trimmed = $raw.TrimStart('0')
        if ([string]::IsNullOrEmpty($trimmed)) {
            $trimmed = '0'
        }

        return ('#{0:D8}:{1}:{2:D8}#' -f $trimmed.Length, $trimmed, $raw.Length)
    })
}

function Test-SupportedImageName {
    param([Parameter(Mandatory)][string]$Name)

    $extension = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
    return $script:SupportedImageExtensions -contains $extension
}

function Get-ObjectProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Load-AppSettings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return
    }

    try {
        $settings = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json

        $fit = [string](Get-ObjectProperty $settings 'FitMode' $script:FitMode)
        if ($fit -in @('Window', 'Width', 'Height', 'Original')) {
            $script:FitMode = $fit
        }

        $script:DoublePage = [bool](Get-ObjectProperty $settings 'DoublePage' $script:DoublePage)
        $script:RightToLeft = [bool](Get-ObjectProperty $settings 'RightToLeft' $script:RightToLeft)
        $script:PageListVisible = [bool](Get-ObjectProperty $settings 'PageListVisible' $script:PageListVisible)
        $script:ThumbnailListMode = [bool](Get-ObjectProperty $settings 'ThumbnailListMode' $script:ThumbnailListMode)
        $script:SlideshowIntervalSeconds = [int](Get-ObjectProperty $settings 'SlideshowIntervalSeconds' $script:SlideshowIntervalSeconds)
        $script:SlideshowIntervalSeconds = [Math]::Max(1, [Math]::Min(60, $script:SlideshowIntervalSeconds))
        $script:WindowWidth = [int](Get-ObjectProperty $settings 'WindowWidth' $script:WindowWidth)
        $script:WindowHeight = [int](Get-ObjectProperty $settings 'WindowHeight' $script:WindowHeight)

        $recent = Get-ObjectProperty $settings 'RecentPaths' @()
        $script:RecentPaths = @(
            @($recent) |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Select-Object -First 10
        )

        $script:LastPositions = @{}
        $positions = Get-ObjectProperty $settings 'LastPositions' $null
        if ($positions) {
            foreach ($property in $positions.PSObject.Properties) {
                $script:LastPositions[[string]$property.Name] = [int]$property.Value
            }
        }

        $script:Bookmarks = @{}
        $bookmarks = Get-ObjectProperty $settings 'Bookmarks' $null
        if ($bookmarks) {
            foreach ($property in $bookmarks.PSObject.Properties) {
                $script:Bookmarks[[string]$property.Name] = @($property.Value | ForEach-Object { [int]$_ })
            }
        }
    } catch {
        Write-AppLog -Message "Could not load settings from: $script:SettingsPath" -ErrorRecord $_
        $script:RecentPaths = @()
        $script:LastPositions = @{}
        $script:Bookmarks = @{}
    }
}

function Save-AppSettings {
    try {
        Save-CurrentProgress
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null

        $width = $script:WindowWidth
        $height = $script:WindowHeight
        if ($script:Form -and -not $script:Fullscreen) {
            $width = $script:Form.Width
            $height = $script:Form.Height
        }

        $settings = [pscustomobject]@{
            Version = 1
            FitMode = $script:FitMode
            DoublePage = $script:DoublePage
            RightToLeft = $script:RightToLeft
            PageListVisible = $script:PageListVisible
            ThumbnailListMode = $script:ThumbnailListMode
            SlideshowIntervalSeconds = $script:SlideshowIntervalSeconds
            WindowWidth = $width
            WindowHeight = $height
            RecentPaths = @($script:RecentPaths)
            LastPositions = $script:LastPositions
            Bookmarks = $script:Bookmarks
        }

        $settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    } catch {
        Write-AppLog -Message "Could not save settings to: $script:SettingsPath" -ErrorRecord $_
        # Settings persistence should never interrupt reading.
    }
}

function Shorten-MenuPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.Length -le 86) {
        return $Path
    }

    return '...' + $Path.Substring($Path.Length - 83)
}

function Add-RecentPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = try {
        (Resolve-Path -LiteralPath $Path).ProviderPath
    } catch {
        $Path
    }

    $script:RecentPaths = @(
        $resolved
        @($script:RecentPaths | Where-Object { $_.ToLowerInvariant() -ne $resolved.ToLowerInvariant() })
    ) | Select-Object -First 10

    Refresh-RecentMenu
    Save-AppSettings
}

function Get-SourceProgressKey {
    param([Parameter(Mandatory)][string]$Path)

    return $Path.ToLowerInvariant()
}

function Save-CurrentProgress {
    if ([string]::IsNullOrWhiteSpace($script:CurrentSourcePath) -or $script:Pages.Count -eq 0) {
        return
    }

    $key = Get-SourceProgressKey $script:CurrentSourcePath
    $script:LastPositions[$key] = $script:CurrentIndex
}

function Get-CurrentSourceKey {
    if ([string]::IsNullOrWhiteSpace($script:CurrentSourcePath)) {
        return $null
    }
    return (Get-SourceProgressKey $script:CurrentSourcePath)
}

function Get-CurrentBookmarks {
    $key = Get-CurrentSourceKey
    if ($null -eq $key -or -not $script:Bookmarks.ContainsKey($key)) {
        return @()
    }
    return @($script:Bookmarks[$key] | Sort-Object -Unique)
}

function Toggle-Bookmark {
    if ($script:Pages.Count -eq 0) {
        return
    }

    $key = Get-CurrentSourceKey
    if ($null -eq $key) {
        return
    }

    $bookmarks = @(Get-CurrentBookmarks)
    if ($bookmarks -contains $script:CurrentIndex) {
        $bookmarks = @($bookmarks | Where-Object { $_ -ne $script:CurrentIndex })
    } else {
        $bookmarks = @($bookmarks + $script:CurrentIndex | Sort-Object -Unique)
    }

    if ($bookmarks.Count -eq 0) {
        [void]$script:Bookmarks.Remove($key)
    } else {
        $script:Bookmarks[$key] = @($bookmarks)
    }

    Refresh-BookmarkMenu
    Update-Status
    Save-AppSettings
}

function Clear-CurrentBookmarks {
    $key = Get-CurrentSourceKey
    if ($null -eq $key) {
        return
    }

    [void]$script:Bookmarks.Remove($key)
    Refresh-BookmarkMenu
    Update-Status
    Save-AppSettings
}

function Go-ToBookmark {
    param([Parameter(Mandatory)][int]$Index)

    Go-ToPage ($Index + 1)
}

function Refresh-BookmarkMenu {
    if ($null -eq $script:BookmarkMenu) {
        return
    }

    $script:BookmarkMenu.DropDownItems.Clear()

    if ($script:Pages.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ToolStripMenuItem '(No open comic)'
        $empty.Enabled = $false
        [void]$script:BookmarkMenu.DropDownItems.Add($empty)
        return
    }

    [void](Add-MenuItem $script:BookmarkMenu 'Toggle Current Page (M)' { Toggle-Bookmark })
    [void]$script:BookmarkMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $bookmarks = @(Get-CurrentBookmarks)
    if ($bookmarks.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ToolStripMenuItem '(No bookmarks for this comic)'
        $empty.Enabled = $false
        [void]$script:BookmarkMenu.DropDownItems.Add($empty)
    } else {
        foreach ($bookmark in $bookmarks) {
            if ($bookmark -ge 0 -and $bookmark -lt $script:Pages.Count) {
                $indexCopy = [int]$bookmark
                $page = $script:Pages[$bookmark]
                $label = 'Page {0}: {1}' -f ($bookmark + 1), $page.DisplayName
                $item = New-Object System.Windows.Forms.ToolStripMenuItem (Shorten-MenuPath $label)
                $item.ToolTipText = $label
                $item.Add_Click({
                    Invoke-AppAction -Title 'Open bookmark failed' -Action { Go-ToBookmark $indexCopy }
                }.GetNewClosure())
                [void]$script:BookmarkMenu.DropDownItems.Add($item)
            }
        }
    }

    [void]$script:BookmarkMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $script:BookmarkMenu 'Clear Bookmarks For This Comic' { Clear-CurrentBookmarks })
}

function Remove-RecentPath {
    param([Parameter(Mandatory)][string]$Path)

    $script:RecentPaths = @($script:RecentPaths | Where-Object { $_.ToLowerInvariant() -ne $Path.ToLowerInvariant() })
    Refresh-RecentMenu
    Save-AppSettings
}

function Open-RecentPath {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            Open-ComicSource $Path
            if ($script:OpenLabel) {
                $script:OpenLabel.Visible = $false
            }
        } catch {
            Show-AppError -Title 'Open recent failed' -ErrorRecord $_
        }
    } else {
        Remove-RecentPath $Path
        [System.Windows.Forms.MessageBox]::Show($script:Form, "Recent item no longer exists:`n$Path", 'Recent item missing') | Out-Null
    }
}

function Refresh-RecentMenu {
    if ($null -eq $script:RecentMenu) {
        return
    }

    $script:RecentMenu.DropDownItems.Clear()

    if ($script:RecentPaths.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ToolStripMenuItem '(No recent comics)'
        $empty.Enabled = $false
        [void]$script:RecentMenu.DropDownItems.Add($empty)
        return
    }

    foreach ($recent in $script:RecentPaths) {
        $pathCopy = [string]$recent
        $item = New-Object System.Windows.Forms.ToolStripMenuItem (Shorten-MenuPath $pathCopy)
        $item.ToolTipText = $pathCopy
        $item.Add_Click({
            Invoke-AppAction -Title 'Open recent failed' -Action { Open-RecentPath $pathCopy }
        }.GetNewClosure())
        [void]$script:RecentMenu.DropDownItems.Add($item)
    }

    [void]$script:RecentMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $clear = New-Object System.Windows.Forms.ToolStripMenuItem 'Clear Recent'
    $clear.Add_Click({
        Invoke-AppAction -Title 'Clear recent failed' -Action {
            $script:RecentPaths = @()
            Refresh-RecentMenu
            Save-AppSettings
        }
    })
    [void]$script:RecentMenu.DropDownItems.Add($clear)
}

function Clear-ArchiveCache {
    try {
        if (Test-Path -LiteralPath $script:ExternalArchiveCacheDir) {
            Remove-Item -LiteralPath $script:ExternalArchiveCacheDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:ExternalArchiveCacheDir -Force | Out-Null
    } catch {
        Write-AppLog -Message "Could not clear archive cache: $script:ExternalArchiveCacheDir" -ErrorRecord $_
        if ($script:Form) {
            Show-AppError -Title 'Could not clear archive cache' -ErrorRecord $_
        }
    }
}

function Get-FolderPages {
    param([Parameter(Mandatory)][string]$Root)

    $rootItem = Get-Item -LiteralPath $Root
    $files = if ($rootItem.PSIsContainer) {
        Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -File
    } else {
        Get-ChildItem -LiteralPath $rootItem.DirectoryName -File
    }

    $index = 0
    return @(
        $files |
            Where-Object { Test-SupportedImageName $_.Name } |
            Sort-Object -Property @{ Expression = { Get-NaturalSortKey $_.FullName } } |
            ForEach-Object {
                [pscustomobject]@{
                    Index = $index++
                    Source = 'Folder'
                    Path = $_.FullName
                    ZipPath = $null
                    EntryName = $null
                    DisplayName = $_.Name
                    SortName = $_.FullName
                }
            }
    )
}

function Get-ZipPages {
    param([Parameter(Mandatory)][string]$ZipPath)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $index = 0
        return @(
            $archive.Entries |
                Where-Object {
                    -not [string]::IsNullOrEmpty($_.Name) -and
                    (Test-SupportedImageName $_.FullName)
                } |
                Sort-Object -Property @{ Expression = { Get-NaturalSortKey $_.FullName } } |
                ForEach-Object {
                    [pscustomobject]@{
                        Index = $index++
                        Source = 'Zip'
                        Path = $null
                        ZipPath = $ZipPath
                        EntryName = $_.FullName
                        DisplayName = $_.FullName
                        SortName = $_.FullName
                    }
                }
        )
    } finally {
        $archive.Dispose()
    }
}

function Get-FirstCommandPath {
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }
    return $null
}

function Get-ArchiveCacheKey {
    param([Parameter(Mandatory)][string]$ArchivePath)

    $item = Get-Item -LiteralPath $ArchivePath
    $identity = '{0}|{1}|{2}' -f $item.FullName.ToLowerInvariant(), $item.Length, $item.LastWriteTimeUtc.Ticks
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($identity)
        $hash = $sha1.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha1.Dispose()
    }
}

function Ensure-ExternalArchiveExtracted {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Kind
    )

    $cacheKey = Get-ArchiveCacheKey $ArchivePath
    $target = Join-Path $script:ExternalArchiveCacheDir $cacheKey
    $marker = Join-Path $target '.complete'

    if (Test-Path -LiteralPath $marker) {
        return $target
    }

    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null

    if ($Kind -eq 'Tar') {
        $tar = Get-FirstCommandPath @('tar.exe', 'tar')
        if (-not $tar) {
            throw 'tar.exe was not found. Windows 10/11 usually includes it.'
        }

        Write-AppLog -Message "Extracting tar archive: $ArchivePath"
        $output = & $tar -xf $ArchivePath -C $target 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-AppLog -Message "tar.exe failed extracting: $ArchivePath" -ErrorRecord $output
            throw "tar.exe could not extract archive:`n$ArchivePath`n`n$output"
        }
    } elseif ($Kind -eq 'SevenZip') {
        $sevenZip = Get-FirstCommandPath @('7z.exe', '7za.exe', '7zr.exe', '7z', '7za', '7zr')
        if (-not $sevenZip) {
            throw "This archive needs 7-Zip support. Install 7-Zip and make 7z.exe available in PATH, then reopen:`n$ArchivePath"
        }

        Write-AppLog -Message "Extracting 7-Zip archive: $ArchivePath"
        $output = & $sevenZip x "-o$target" -y $ArchivePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-AppLog -Message "7-Zip failed extracting: $ArchivePath" -ErrorRecord $output
            throw "7-Zip could not extract archive:`n$ArchivePath`n`n$output"
        }
    } else {
        throw "Unknown external archive kind: $Kind"
    }

    New-Item -ItemType File -Path $marker -Force | Out-Null
    Write-AppLog -Message "Extracted archive cache: $ArchivePath -> $target"
    return $target
}

function Get-ExternalArchivePages {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Kind
    )

    $folder = Ensure-ExternalArchiveExtracted -ArchivePath $ArchivePath -Kind $Kind
    $pages = Get-FolderPages $folder
    return $pages
}

function Convert-WicStreamToBitmap {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    if (-not $script:WicAvailable) {
        throw 'Windows Imaging Component is not available in this PowerShell session.'
    }

    $Stream.Position = 0
    $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
        $Stream,
        [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
        [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    )

    if ($decoder.Frames.Count -eq 0) {
        throw 'WIC decoder returned no frames.'
    }

    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($decoder.Frames[0]))

    $pngStream = New-Object System.IO.MemoryStream
    try {
        $encoder.Save($pngStream)
        $pngStream.Position = 0
        $image = [System.Drawing.Image]::FromStream($pngStream)
        try {
            return New-Object System.Drawing.Bitmap -ArgumentList $image
        } finally {
            $image.Dispose()
        }
    } finally {
        $pngStream.Dispose()
    }
}

function New-BitmapFromImageStream {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][string]$Label
    )

    $gdiError = $null
    try {
        if ($Stream.CanSeek) {
            $Stream.Position = 0
        }
        $image = [System.Drawing.Image]::FromStream($Stream)
        try {
            return New-Object System.Drawing.Bitmap -ArgumentList $image
        } finally {
            $image.Dispose()
        }
    } catch {
        $gdiError = $_.Exception.Message
        Write-AppLog -Message "GDI+ decode failed; trying fallback if available: $Label" -ErrorRecord $_
    }

    if ($script:WicAvailable -and $Stream.CanSeek) {
        try {
            return Convert-WicStreamToBitmap $Stream
        } catch {
            throw "Could not decode $Label with GDI+ or WIC. GDI+: $gdiError; WIC: $($_.Exception.Message)"
        }
    }

    throw "Could not decode $Label with GDI+. $gdiError"
}

function Clear-PageCache {
    foreach ($key in @($script:PageCache.Keys)) {
        $bitmap = $script:PageCache[$key]
        if ($bitmap) {
            $bitmap.Dispose()
        }
    }
    $script:PageCache.Clear()
    $script:CacheOrder.Clear()
}

function Clear-ThumbnailCache {
    foreach ($key in @($script:ThumbnailCache.Keys)) {
        $bitmap = $script:ThumbnailCache[$key]
        if ($bitmap) {
            $bitmap.Dispose()
        }
    }
    $script:ThumbnailCache.Clear()
}

function Get-PageCacheKey {
    param([Parameter(Mandatory)]$Page)

    if ($Page.Source -eq 'Folder') {
        return "F|$($Page.Path)"
    }

    return "Z|$($Page.ZipPath)|$($Page.EntryName)"
}

function Touch-CacheKey {
    param([Parameter(Mandatory)][string]$Key)

    [void]$script:CacheOrder.Remove($Key)
    $script:CacheOrder.Add($Key)
}

function Get-PageBitmapCached {
    param([Parameter(Mandatory)]$Page)

    $key = Get-PageCacheKey $Page
    if ($script:PageCache.ContainsKey($key)) {
        Touch-CacheKey $key
        return $script:PageCache[$key]
    }

    $bitmap = Load-PageBitmap $Page
    $script:PageCache[$key] = $bitmap
    Touch-CacheKey $key
    Trim-PageCache
    return $bitmap
}

function Get-PageThumbnail {
    param(
        [Parameter(Mandatory)][int]$Index,
        [int]$Width = 72,
        [int]$Height = 88
    )

    if ($Index -lt 0 -or $Index -ge $script:Pages.Count) {
        return $null
    }

    $page = $script:Pages[$Index]
    $key = '{0}|{1}x{2}' -f (Get-PageCacheKey $page), $Width, $Height
    if ($script:ThumbnailCache.ContainsKey($key)) {
        return $script:ThumbnailCache[$key]
    }

    $source = Get-PageBitmapCached $page
    $thumb = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($thumb)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(18, 18, 18))
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $scale = [Math]::Min($Width / $source.Width, $Height / $source.Height)
        $drawWidth = [Math]::Max(1, [int]($source.Width * $scale))
        $drawHeight = [Math]::Max(1, [int]($source.Height * $scale))
        $x = [int](($Width - $drawWidth) / 2)
        $y = [int](($Height - $drawHeight) / 2)
        $graphics.DrawImage($source, $x, $y, $drawWidth, $drawHeight)
    } finally {
        $graphics.Dispose()
    }

    $script:ThumbnailCache[$key] = $thumb
    return $thumb
}

function Trim-PageCache {
    while ($script:PageCache.Count -gt $script:CacheLimit -and $script:CacheOrder.Count -gt 0) {
        $oldest = $script:CacheOrder[0]
        $script:CacheOrder.RemoveAt(0)
        if ($script:PageCache.ContainsKey($oldest)) {
            $bitmap = $script:PageCache[$oldest]
            [void]$script:PageCache.Remove($oldest)
            if ($bitmap) {
                $bitmap.Dispose()
            }
        }
    }
}

function Preload-NearbyPages {
    if ($script:Pages.Count -eq 0) {
        return
    }

    $step = if ($script:DoublePage) { 2 } else { 1 }
    $targets = New-Object 'System.Collections.Generic.List[int]'
    for ($offset = -$script:CacheRadius; $offset -le $script:CacheRadius; $offset++) {
        $index = $script:CurrentIndex + ($offset * $step)
        if ($index -ge 0 -and $index -lt $script:Pages.Count) {
            $targets.Add($index)
            if ($script:DoublePage -and ($index + 1) -lt $script:Pages.Count) {
                $targets.Add($index + 1)
            }
        }
    }

    foreach ($index in ($targets | Select-Object -Unique)) {
        [void](Get-PageBitmapCached $script:Pages[$index])
    }
    Trim-PageCache
}

function Open-ComicSource {
    param([Parameter(Mandatory)][string]$Path)

    Write-AppLog -Message "Opening source: $Path"
    try {
        $resolvedSource = Resolve-ComicSource $Path
        Clear-PageCache
        Clear-ThumbnailCache
        $script:Pages = $resolvedSource.Pages
        $script:CurrentIndex = $resolvedSource.InitialIndex
        $script:CurrentSourcePath = $resolvedSource.SourcePath

        Refresh-PageList
        Refresh-BookmarkMenu
        Show-CurrentPage
        Add-RecentPath $script:CurrentSourcePath
        Write-AppLog -Message "Opened source: $script:CurrentSourcePath ($($script:Pages.Count) page(s))"
    } catch {
        Write-AppLog -Message "Open source failed: $Path" -ErrorRecord $_
        throw
    }
}

function Resolve-ComicSource {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $item = Get-Item -LiteralPath $resolved
    $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    $initialPath = $null

    if ($item.PSIsContainer) {
        $pages = @(Get-FolderPages $resolved)
    } elseif ($extension -in $script:ZipArchiveExtensions) {
        $pages = @(Get-ZipPages $resolved)
    } elseif ($extension -in $script:TarArchiveExtensions) {
        $pages = @(Get-ExternalArchivePages -ArchivePath $resolved -Kind 'Tar')
    } elseif ($extension -in $script:SevenZipArchiveExtensions) {
        $pages = @(Get-ExternalArchivePages -ArchivePath $resolved -Kind 'SevenZip')
    } elseif (Test-SupportedImageName $resolved) {
        $pages = @(Get-FolderPages $resolved)
        $initialPath = $resolved
    } else {
        throw "Unsupported source: $resolved"
    }

    if ($pages.Count -eq 0) {
        throw "No supported image pages found in: $resolved"
    }

    $initialIndex = 0
    if ($initialPath) {
        for ($i = 0; $i -lt $pages.Count; $i++) {
            if ($pages[$i].Path -eq $initialPath) {
                $initialIndex = $i
                break
            }
        }
    } else {
        $progressKey = Get-SourceProgressKey $resolved
        if ($script:LastPositions.ContainsKey($progressKey)) {
            $initialIndex = [Math]::Max(0, [Math]::Min($pages.Count - 1, [int]$script:LastPositions[$progressKey]))
        }
    }

    return [pscustomobject]@{
        Pages = $pages
        InitialIndex = $initialIndex
        SourcePath = $resolved
    }
}

function Load-PageBitmap {
    param([Parameter(Mandatory)]$Page)

    try {
        if ($Page.Source -eq 'Folder') {
            $stream = [System.IO.File]::OpenRead($Page.Path)
            try {
                return New-BitmapFromImageStream -Stream $stream -Label $Page.Path
            } finally {
                $stream.Dispose()
            }
        }

        $archive = [System.IO.Compression.ZipFile]::OpenRead($Page.ZipPath)
        try {
            $entry = $archive.GetEntry($Page.EntryName)
            if ($null -eq $entry) {
                throw "Missing zip entry: $($Page.EntryName)"
            }

            $stream = $entry.Open()
            $memory = New-Object System.IO.MemoryStream
            try {
                $stream.CopyTo($memory)
                return New-BitmapFromImageStream -Stream $memory -Label $Page.EntryName
            } finally {
                $memory.Dispose()
                $stream.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
    } catch {
        Write-AppLog -Message "Could not load page bitmap: $($Page.DisplayName)" -ErrorRecord $_
        return New-PlaceholderBitmap "Could not load:`n$($Page.DisplayName)`n`n$($_.Exception.Message)"
    }
}

function New-PlaceholderBitmap {
    param([Parameter(Mandatory)][string]$Message)

    $bitmap = New-Object System.Drawing.Bitmap 900, 1200
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(24, 24, 24))
        $font = New-Object System.Drawing.Font 'Segoe UI', 18
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Gainsboro)
        try {
            $rect = New-Object System.Drawing.RectangleF 40, 40, 820, 1120
            $graphics.DrawString($Message, $font, $brush, $rect)
        } finally {
            $brush.Dispose()
            $font.Dispose()
        }
    } finally {
        $graphics.Dispose()
    }

    return $bitmap
}

function New-SpreadBitmap {
    param([Parameter(Mandatory)][System.Drawing.Bitmap[]]$Bitmaps)

    if ($Bitmaps.Count -eq 1) {
        return New-Object System.Drawing.Bitmap -ArgumentList $Bitmaps[0]
    }

    $ordered = if ($script:RightToLeft) {
        @($Bitmaps[1], $Bitmaps[0])
    } else {
        @($Bitmaps[0], $Bitmaps[1])
    }

    $width = $ordered[0].Width + $ordered[1].Width
    $height = [Math]::Max($ordered[0].Height, $ordered[1].Height)
    $combined = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($combined)
    try {
        $graphics.Clear([System.Drawing.Color]::Black)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $x = 0
        foreach ($bitmap in $ordered) {
            $y = [int](($height - $bitmap.Height) / 2)
            $graphics.DrawImage($bitmap, $x, $y, $bitmap.Width, $bitmap.Height)
            $x += $bitmap.Width
        }
    } finally {
        $graphics.Dispose()
    }

    return $combined
}

function Show-CurrentPage {
    if ($script:Pages.Count -eq 0) {
        return
    }

    $bitmaps = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
    $bitmaps.Add((Get-PageBitmapCached $script:Pages[$script:CurrentIndex]))
    if ($script:DoublePage -and ($script:CurrentIndex + 1) -lt $script:Pages.Count) {
        $bitmaps.Add((Get-PageBitmapCached $script:Pages[$script:CurrentIndex + 1]))
    }

    $display = New-SpreadBitmap $bitmaps.ToArray()

    if ($script:LoadedImage) {
        $script:LoadedImage.Dispose()
    }

    $script:LoadedImage = $display
    $script:Picture.Image = $display
    Update-PictureLayout
    if ($script:Panel) {
        $script:Panel.AutoScrollPosition = New-Object System.Drawing.Point 0, 0
    }
    Update-Status
    Update-PageListSelection
    Preload-NearbyPages
}

function Update-PictureLayout {
    if ($null -eq $script:Picture -or $null -eq $script:Picture.Image) {
        return
    }

    $image = $script:Picture.Image
    $client = $script:Panel.ClientSize
    $availableWidth = [Math]::Max(1, $client.Width - 24)
    $availableHeight = [Math]::Max(1, $client.Height - 24)

    $scale = switch ($script:FitMode) {
        'Original' { $script:Zoom }
        'Width' { ($availableWidth / $image.Width) * $script:Zoom }
        'Height' { ($availableHeight / $image.Height) * $script:Zoom }
        default { [Math]::Min($availableWidth / $image.Width, $availableHeight / $image.Height) * $script:Zoom }
    }
    $scale = [Math]::Max(0.05, [Math]::Min(8.0, $scale))

    $width = [Math]::Max(1, [int]($image.Width * $scale))
    $height = [Math]::Max(1, [int]($image.Height * $scale))
    $script:Picture.Size = New-Object System.Drawing.Size $width, $height

    $x = if ($width -lt $client.Width) { [int](($client.Width - $width) / 2) } else { 0 }
    $y = if ($height -lt $client.Height) { [int](($client.Height - $height) / 2) } else { 0 }
    $script:Picture.Location = New-Object System.Drawing.Point $x, $y
}

function Update-Status {
    if ($null -eq $script:Status) {
        return
    }

    if ($script:Pages.Count -eq 0) {
        $script:Status.Text = 'Open a folder, zip, cbz, or image file.'
        return
    }

    $page = $script:Pages[$script:CurrentIndex]
    $range = if ($script:DoublePage -and ($script:CurrentIndex + 1) -lt $script:Pages.Count) {
        '{0}-{1}' -f ($script:CurrentIndex + 1), ($script:CurrentIndex + 2)
    } else {
        '{0}' -f ($script:CurrentIndex + 1)
    }
    $direction = if ($script:RightToLeft) { 'RTL' } else { 'LTR' }
    $spread = if ($script:DoublePage) { 'Double' } else { 'Single' }
    $bookmark = if (@(Get-CurrentBookmarks) -contains $script:CurrentIndex) { ' | Bookmark' } else { '' }
    $slideshow = if ($script:SlideshowRunning) {
        ' | Slideshow: On/{0}s' -f $script:SlideshowIntervalSeconds
    } else {
        ''
    }

    $script:Status.Text = "Page $range / $($script:Pages.Count) | $spread | $direction | Fit: $($script:FitMode)$bookmark$slideshow | $($page.DisplayName)"
}

function Format-PageListItem {
    param([Parameter(Mandatory)]$Page)

    return ('{0,5}. {1}' -f ($Page.Index + 1), $Page.DisplayName)
}

function Refresh-PageList {
    if ($null -eq $script:PageList) {
        return
    }

    Update-PageListStyle
    $script:SuppressPageListEvent = $true
    try {
        $script:PageList.BeginUpdate()
        try {
            $script:PageList.Items.Clear()
            foreach ($page in $script:Pages) {
                [void]$script:PageList.Items.Add((Format-PageListItem $page))
            }
        } finally {
            $script:PageList.EndUpdate()
        }
        Update-PageListSelection
    } finally {
        $script:SuppressPageListEvent = $false
    }
}

function Update-PageListStyle {
    if ($null -eq $script:PageList) {
        return
    }

    if ($script:ThumbnailListMode) {
        $script:PageList.ItemHeight = 104
    } else {
        $script:PageList.ItemHeight = 22
    }
    $script:PageList.Invalidate()
}

function Toggle-ThumbnailListMode {
    $script:ThumbnailListMode = -not $script:ThumbnailListMode
    Update-PageListStyle
    Update-PageListSelection
    Save-AppSettings
}

function Update-SlideshowTimer {
    if ($null -eq $script:SlideshowTimer) {
        return
    }

    $script:SlideshowTimer.Interval = [Math]::Max(1000, $script:SlideshowIntervalSeconds * 1000)
    if ($script:SlideshowRunning) {
        $script:SlideshowTimer.Stop()
        $script:SlideshowTimer.Start()
    }

    if ($script:SlideshowMenuItem) {
        $script:SlideshowMenuItem.Checked = $script:SlideshowRunning
    }
    Update-Status
}

function Toggle-Slideshow {
    if ($script:Pages.Count -eq 0) {
        return
    }

    $script:SlideshowRunning = -not $script:SlideshowRunning
    if ($script:SlideshowRunning) {
        Update-SlideshowTimer
    } else {
        if ($script:SlideshowTimer) {
            $script:SlideshowTimer.Stop()
        }
        Update-SlideshowTimer
    }
}

function Set-SlideshowInterval {
    param([Parameter(Mandatory)][int]$Seconds)

    $script:SlideshowIntervalSeconds = [Math]::Max(1, [Math]::Min(60, $Seconds))
    Update-SlideshowTimer
}

function Change-SlideshowInterval {
    param([Parameter(Mandatory)][int]$Delta)

    Set-SlideshowInterval ($script:SlideshowIntervalSeconds + $Delta)
    Save-AppSettings
}

function Advance-Slideshow {
    if (-not $script:SlideshowRunning -or $script:Pages.Count -eq 0) {
        return
    }

    $step = if ($script:DoublePage) { 2 } else { 1 }
    if (($script:CurrentIndex + $step) -ge $script:Pages.Count) {
        $script:SlideshowRunning = $false
        Update-SlideshowTimer
        return
    }

    Move-Page 1
}

function Draw-PageListItem {
    param(
        $Sender,
        [System.Windows.Forms.DrawItemEventArgs]$Event
    )

    if ($Event.Index -lt 0 -or $Event.Index -ge $script:Pages.Count) {
        return
    }

    $selected = (($Event.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
    $background = if ($selected) {
        [System.Drawing.Color]::FromArgb(58, 88, 138)
    } else {
        [System.Drawing.Color]::FromArgb(28, 28, 30)
    }
    $foreground = if ($selected) {
        [System.Drawing.Color]::White
    } else {
        [System.Drawing.Color]::Gainsboro
    }

    $backBrush = New-Object System.Drawing.SolidBrush $background
    $textBrush = New-Object System.Drawing.SolidBrush $foreground
    try {
        $Event.Graphics.FillRectangle($backBrush, $Event.Bounds)

        $page = $script:Pages[$Event.Index]
        if ($script:ThumbnailListMode) {
            $thumb = Get-PageThumbnail -Index $Event.Index
            if ($thumb) {
                $thumbRect = New-Object System.Drawing.Rectangle ($Event.Bounds.X + 8), ($Event.Bounds.Y + 8), 72, 88
                $Event.Graphics.DrawImage($thumb, $thumbRect)
            }

            $titleFont = New-Object System.Drawing.Font 'Segoe UI', 9, ([System.Drawing.FontStyle]::Bold)
            $smallFont = New-Object System.Drawing.Font 'Segoe UI', 8
            try {
                $x = $Event.Bounds.X + 90
                $y = $Event.Bounds.Y + 12
                $title = 'Page {0}' -f ($page.Index + 1)
                $Event.Graphics.DrawString($title, $titleFont, $textBrush, $x, $y)

                $nameRect = New-Object System.Drawing.RectangleF $x, ($y + 24), ([Math]::Max(20, $Event.Bounds.Width - 100)), 60
                $format = New-Object System.Drawing.StringFormat
                try {
                    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
                    $format.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit
                    $Event.Graphics.DrawString($page.DisplayName, $smallFont, $textBrush, $nameRect, $format)
                } finally {
                    $format.Dispose()
                }
            } finally {
                $smallFont.Dispose()
                $titleFont.Dispose()
            }
        } else {
            $text = Format-PageListItem $page
            $textY = $Event.Bounds.Y + 3
            $Event.Graphics.DrawString($text, $script:PageList.Font, $textBrush, ($Event.Bounds.X + 6), $textY)
        }
    } finally {
        $textBrush.Dispose()
        $backBrush.Dispose()
    }
}

function Update-PageListSelection {
    if ($null -eq $script:PageList -or $script:PageList.Items.Count -eq 0) {
        return
    }

    $script:SuppressPageListEvent = $true
    try {
        $index = [Math]::Max(0, [Math]::Min($script:PageList.Items.Count - 1, $script:CurrentIndex))
        $script:PageList.SelectedIndex = $index
        $top = [Math]::Max(0, $index - 6)
        if ($top -lt $script:PageList.Items.Count) {
            $script:PageList.TopIndex = $top
        }
    } finally {
        $script:SuppressPageListEvent = $false
    }
}

function Toggle-PageList {
    $script:PageListVisible = -not $script:PageListVisible
    if ($script:Split) {
        $script:Split.Panel1Collapsed = -not $script:PageListVisible
    }
    Save-AppSettings
}

function Scroll-ImageBy {
    param(
        [int]$DeltaX,
        [int]$DeltaY
    )

    if ($null -eq $script:Panel) {
        return
    }

    $currentX = -$script:Panel.AutoScrollPosition.X
    $currentY = -$script:Panel.AutoScrollPosition.Y
    $maxX = if ($script:Picture) { [Math]::Max(0, $script:Picture.Width - $script:Panel.ClientSize.Width + 24) } else { 0 }
    $maxY = if ($script:Picture) { [Math]::Max(0, $script:Picture.Height - $script:Panel.ClientSize.Height + 24) } else { 0 }

    $nextX = [Math]::Max(0, [Math]::Min($maxX, $currentX + $DeltaX))
    $nextY = [Math]::Max(0, [Math]::Min($maxY, $currentY + $DeltaY))
    $script:Panel.AutoScrollPosition = New-Object System.Drawing.Point $nextX, $nextY
}

function Scroll-Or-TurnPage {
    param([Parameter(Mandatory)][int]$DeltaY)

    if ($script:Pages.Count -eq 0 -or $null -eq $script:Picture) {
        return
    }

    $currentY = -$script:Panel.AutoScrollPosition.Y
    $maxY = [Math]::Max(0, $script:Picture.Height - $script:Panel.ClientSize.Height + 24)

    if ($maxY -le 0) {
        if ($DeltaY -gt 0) {
            Move-Page 1
        } elseif ($DeltaY -lt 0) {
            Move-Page -1
        }
        return
    }

    if ($DeltaY -gt 0 -and $currentY -ge ($maxY - 2)) {
        Move-Page 1
        return
    }

    if ($DeltaY -lt 0 -and $currentY -le 2) {
        Move-Page -1
        return
    }

    Scroll-ImageBy 0 $DeltaY
}

function Handle-MouseWheel {
    param($Sender, [System.Windows.Forms.MouseEventArgs]$Event)

    if ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) {
        if ($Event.Delta -gt 0) {
            Change-Zoom 1.15
        } else {
            Change-Zoom 0.87
        }
        return
    }

    Scroll-Or-TurnPage (-$Event.Delta)
}

function Move-Page {
    param([Parameter(Mandatory)][int]$Delta)

    if ($script:Pages.Count -eq 0) {
        return
    }

    $step = if ($script:DoublePage) { 2 } else { 1 }
    $next = $script:CurrentIndex + ($Delta * $step)
    $script:CurrentIndex = [Math]::Max(0, [Math]::Min($script:Pages.Count - 1, $next))
    Show-CurrentPage
    Save-AppSettings
}

function Go-ToPage {
    param([Parameter(Mandatory)][int]$OneBasedPage)

    if ($script:Pages.Count -eq 0) {
        return
    }

    $target = [Math]::Max(1, [Math]::Min($script:Pages.Count, $OneBasedPage))
    $script:CurrentIndex = $target - 1
    Show-CurrentPage
    Save-AppSettings
}

function Show-GoToPageDialog {
    if ($script:Pages.Count -eq 0) {
        return
    }

    $prompt = "Page number (1-$($script:Pages.Count))"
    try {
        $input = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, 'Go To Page', [string]($script:CurrentIndex + 1))
    } catch {
        $input = ''
    }

    if ([string]::IsNullOrWhiteSpace($input)) {
        return
    }

    $target = 0
    if ([int]::TryParse($input, [ref]$target)) {
        Go-ToPage $target
    }
}

function Open-AdjacentSource {
    param([Parameter(Mandatory)][int]$Delta)

    if ([string]::IsNullOrWhiteSpace($script:CurrentSourcePath)) {
        return
    }

    $current = Get-Item -LiteralPath $script:CurrentSourcePath -ErrorAction SilentlyContinue
    if ($null -eq $current) {
        return
    }

    $candidates = @()
    if ($current.PSIsContainer) {
        $parent = $current.Parent.FullName
        $candidates = @(
            Get-ChildItem -LiteralPath $parent -Directory |
                Sort-Object -Property @{ Expression = { Get-NaturalSortKey $_.FullName } }
        )
    } else {
        $parent = $current.DirectoryName
        $candidates = @(
            Get-ChildItem -LiteralPath $parent -File |
                Where-Object {
                    $extension = [System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()
                    $extension -in (@($script:ZipArchiveExtensions) + @($script:TarArchiveExtensions) + @($script:SevenZipArchiveExtensions))
                } |
                Sort-Object -Property @{ Expression = { Get-NaturalSortKey $_.FullName } }
        )
    }

    if ($candidates.Count -eq 0) {
        return
    }

    $currentPathLower = $current.FullName.ToLowerInvariant()
    $currentListIndex = -1
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        if ($candidates[$i].FullName.ToLowerInvariant() -eq $currentPathLower) {
            $currentListIndex = $i
            break
        }
    }

    if ($currentListIndex -lt 0) {
        return
    }

    $nextIndex = $currentListIndex + $Delta
    if ($nextIndex -lt 0 -or $nextIndex -ge $candidates.Count) {
        return
    }

    try {
        Open-ComicSource $candidates[$nextIndex].FullName
        if ($script:OpenLabel) {
            $script:OpenLabel.Visible = $false
        }
    } catch {
        Show-AppError -Title 'Open adjacent source failed' -ErrorRecord $_
    }
}

function Set-FitMode {
    param([Parameter(Mandatory)][string]$Mode)

    $script:FitMode = $Mode
    $script:Zoom = 1.0
    Update-PictureLayout
    Update-Status
    Save-AppSettings
}

function Change-Zoom {
    param([Parameter(Mandatory)][double]$Factor)

    $script:Zoom = [Math]::Max(0.05, [Math]::Min(8.0, $script:Zoom * $Factor))
    Update-PictureLayout
    Update-Status
}

function Toggle-Fullscreen {
    if ($script:Fullscreen) {
        $script:Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
        $script:Form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        if ($script:LastWindowBounds) {
            $script:Form.Bounds = $script:LastWindowBounds
        }
        $script:Fullscreen = $false
    } else {
        $script:LastWindowBounds = $script:Form.Bounds
        $script:Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $script:Form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
        $script:Fullscreen = $true
    }
}

function Show-OpenFolderDialog {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = 'Open manga folder'
        if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Open-ComicSource $dialog.SelectedPath
            } catch {
                Show-AppError -Title 'Open folder failed' -ErrorRecord $_
            }
        }
    } finally {
        $dialog.Dispose()
    }
}

function Show-OpenFileDialog {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Filter = 'Comic archives and images|*.zip;*.cbz;*.tar;*.cbt;*.7z;*.cb7;*.rar;*.cbr;*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff;*.webp|All files|*.*'
        if ($dialog.ShowDialog($script:Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Open-ComicSource $dialog.FileName
            } catch {
                Show-AppError -Title 'Open file failed' -ErrorRecord $_
            }
        }
    } finally {
        $dialog.Dispose()
    }
}

function Show-HelpDialog {
    $message = @'
MangaMeeya Cleanroom Controls

Open:
  Ctrl+O              Open folder
  Ctrl+Shift+O        Open archive or image
  Drag and drop       Open folder/archive/image

Read:
  Space / Right / PgDn  Next page
  Left / PgUp           Previous page
  Up / Down             Scroll long page, turn at edge
  Home / End            First / last page
  Ctrl+G                Go to page
  Ctrl+PgUp/PgDn        Previous / next sibling book or folder

View:
  F                     Fit window
  W                     Fit width
  H                     Fit height
  O                     Original size
  + / -                 Zoom
  Ctrl+Mouse wheel      Zoom
  D                     Toggle double page
  R                     Toggle RTL/LTR spread order
  Enter                 Fullscreen
  Esc                   Exit fullscreen / close

Navigation Panel:
  T                     Show / hide page list
  B                     Text / thumbnail page list

Bookmarks:
  M                     Toggle bookmark on current page

Slideshow:
  F5                    Play / pause
  [ / ]                 Slower / faster

Mouse:
  Left click            Next page
  Right click           Previous page
  Left drag             Pan large page
  Wheel                 Scroll; turns page at edge
'@

    [System.Windows.Forms.MessageBox]::Show($script:Form, $message, 'MangaMeeya Cleanroom Help') | Out-Null
}

function Show-AboutDialog {
    $message = @"
MangaMeeya Cleanroom

Clean-room Windows manga reader.
License: Apache-2.0

No original MangaMeeya source code, binary code, or assets are included.
"@

    [System.Windows.Forms.MessageBox]::Show($script:Form, $message, 'About MangaMeeya Cleanroom') | Out-Null
}

function Show-DebugLogPathDialog {
    New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    $message = "Debug log:`n$(Get-DebugLogPath)`n`nSettings:`n$script:SettingsPath"
    [System.Windows.Forms.MessageBox]::Show($script:Form, $message, 'Debug Log') | Out-Null
}

function Open-DebugLogFolder {
    try {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        Invoke-Item -LiteralPath $script:SettingsDir
    } catch {
        Show-AppError -Title 'Open debug log folder failed' -ErrorRecord $_
    }
}

function Add-MenuItem {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.ToolStripMenuItem]$Parent,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $item = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    $titleCopy = $Text
    $actionCopy = $Action
    $item.Add_Click({
        Invoke-AppAction -Title $titleCopy -Action $actionCopy
    }.GetNewClosure())
    [void]$Parent.DropDownItems.Add($item)
    return $item
}

function Build-MainMenu {
    $menu = New-Object System.Windows.Forms.MenuStrip
    $file = New-Object System.Windows.Forms.ToolStripMenuItem 'File'
    $view = New-Object System.Windows.Forms.ToolStripMenuItem 'View'
    $help = New-Object System.Windows.Forms.ToolStripMenuItem 'Help'
    $script:RecentMenu = New-Object System.Windows.Forms.ToolStripMenuItem 'Recent'
    $script:BookmarkMenu = New-Object System.Windows.Forms.ToolStripMenuItem 'Bookmarks'
    [void]$menu.Items.Add($file)
    [void]$menu.Items.Add($script:RecentMenu)
    [void]$menu.Items.Add($script:BookmarkMenu)
    [void]$menu.Items.Add($view)
    [void]$menu.Items.Add($help)

    [void](Add-MenuItem $file 'Open Folder... (Ctrl+O)' { Show-OpenFolderDialog })
    [void](Add-MenuItem $file 'Open Archive/Image... (Ctrl+Shift+O)' { Show-OpenFileDialog })
    [void]$file.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $file 'Clear Archive Cache' { Clear-ArchiveCache })
    [void]$file.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $file 'Exit' { $script:Form.Close() })

    [void](Add-MenuItem $view 'Fit Window (F)' { Set-FitMode 'Window' })
    [void](Add-MenuItem $view 'Fit Width (W)' { Set-FitMode 'Width' })
    [void](Add-MenuItem $view 'Fit Height (H)' { Set-FitMode 'Height' })
    [void](Add-MenuItem $view 'Original Size (O)' { Set-FitMode 'Original' })
    [void]$view.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $view 'Go To Page... (Ctrl+G)' { Show-GoToPageDialog })
    [void](Add-MenuItem $view 'Previous Book/Folder (Ctrl+PageUp)' { Open-AdjacentSource -1 })
    [void](Add-MenuItem $view 'Next Book/Folder (Ctrl+PageDown)' { Open-AdjacentSource 1 })
    [void]$view.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $script:SlideshowMenuItem = Add-MenuItem $view 'Slideshow Play/Pause (F5)' { Toggle-Slideshow }
    $script:SlideshowMenuItem.CheckOnClick = $false
    [void](Add-MenuItem $view 'Slower Slideshow ([)' { Change-SlideshowInterval 1 })
    [void](Add-MenuItem $view 'Faster Slideshow (])' { Change-SlideshowInterval -1 })
    [void]$view.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $view 'Toggle Page List (T)' { Toggle-PageList })
    [void](Add-MenuItem $view 'Toggle Thumbnails (B)' { Toggle-ThumbnailListMode })
    [void]$view.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $view 'Toggle Double Page (D)' {
        $script:DoublePage = -not $script:DoublePage
        Show-CurrentPage
        Save-AppSettings
    })
    [void](Add-MenuItem $view 'Toggle RTL/LTR (R)' {
        $script:RightToLeft = -not $script:RightToLeft
        Show-CurrentPage
        Save-AppSettings
    })
    [void](Add-MenuItem $view 'Toggle Fullscreen (Enter)' { Toggle-Fullscreen })

    Refresh-RecentMenu
    Refresh-BookmarkMenu
    [void](Add-MenuItem $help 'Controls (F1)' { Show-HelpDialog })
    [void]$help.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $help 'Show Debug Log Path' { Show-DebugLogPathDialog })
    [void](Add-MenuItem $help 'Open Debug Log Folder' { Open-DebugLogFolder })
    [void]$help.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void](Add-MenuItem $help 'About' { Show-AboutDialog })
    return $menu
}

function Handle-KeyDown {
    param($Sender, [System.Windows.Forms.KeyEventArgs]$Event)

    if ($Event.Control -and $Event.Shift -and $Event.KeyCode -eq [System.Windows.Forms.Keys]::O) {
        Show-OpenFileDialog
        $Event.Handled = $true
        return
    }
    if ($Event.Control -and $Event.KeyCode -eq [System.Windows.Forms.Keys]::O) {
        Show-OpenFolderDialog
        $Event.Handled = $true
        return
    }
    if ($Event.Control -and $Event.KeyCode -eq [System.Windows.Forms.Keys]::G) {
        Show-GoToPageDialog
        $Event.Handled = $true
        return
    }
    if ($Event.Control -and $Event.KeyCode -eq [System.Windows.Forms.Keys]::PageDown) {
        Open-AdjacentSource 1
        $Event.Handled = $true
        return
    }
    if ($Event.Control -and $Event.KeyCode -eq [System.Windows.Forms.Keys]::PageUp) {
        Open-AdjacentSource -1
        $Event.Handled = $true
        return
    }

    switch ($Event.KeyCode) {
        ([System.Windows.Forms.Keys]::F1) { Show-HelpDialog; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Space) { Move-Page 1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::PageDown) { Move-Page 1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Right) { Move-Page 1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Down) { Scroll-Or-TurnPage 90; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::PageUp) { Move-Page -1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Left) { Move-Page -1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Up) { Scroll-Or-TurnPage -90; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::F5) { Toggle-Slideshow; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::OemOpenBrackets) { Change-SlideshowInterval 1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::OemCloseBrackets) { Change-SlideshowInterval -1; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Home) { $script:CurrentIndex = 0; Show-CurrentPage; Save-AppSettings; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::End) { $script:CurrentIndex = [Math]::Max(0, $script:Pages.Count - 1); Show-CurrentPage; Save-AppSettings; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::F) { Set-FitMode 'Window'; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::W) { Set-FitMode 'Width'; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::H) { Set-FitMode 'Height'; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::O) { Set-FitMode 'Original'; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::M) { Toggle-Bookmark; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::T) { Toggle-PageList; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::B) { Toggle-ThumbnailListMode; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::D) { $script:DoublePage = -not $script:DoublePage; Show-CurrentPage; Save-AppSettings; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::R) { $script:RightToLeft = -not $script:RightToLeft; Show-CurrentPage; Save-AppSettings; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Add) { Change-Zoom 1.15; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Oemplus) { Change-Zoom 1.15; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Subtract) { Change-Zoom 0.87; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::OemMinus) { Change-Zoom 0.87; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Enter) { Toggle-Fullscreen; $Event.Handled = $true }
        ([System.Windows.Forms.Keys]::Escape) {
            if ($script:Fullscreen) {
                Toggle-Fullscreen
            } else {
                $script:Form.Close()
            }
            $Event.Handled = $true
        }
    }
}

function Start-Reader {
    param([string]$InitialPath)

    Write-AppLog -Message ("Startup | Version={0} | PowerShell={1} | WIC={2} | AppRoot={3} | Settings={4} | OpenPath={5}" -f (Get-AppVersion), $PSVersionTable.PSVersion.ToString(), $script:WicAvailable, $script:AppRoot, $script:SettingsPath, $(if ([string]::IsNullOrWhiteSpace($InitialPath)) { '<none>' } else { $InitialPath }))
    Load-AppSettings

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = 'MangaMeeya Cleanroom'
    $script:Form.BackColor = [System.Drawing.Color]::Black
    $script:Form.Width = [Math]::Max(760, $script:WindowWidth)
    $script:Form.Height = [Math]::Max(520, $script:WindowHeight)
    $script:Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $script:Form.KeyPreview = $true
    $script:Form.AllowDrop = $true

    $menu = Build-MainMenu
    $script:Form.MainMenuStrip = $menu
    $script:Form.Controls.Add($menu)

    $script:SlideshowTimer = New-Object System.Windows.Forms.Timer
    $script:SlideshowTimer.Interval = [Math]::Max(1000, $script:SlideshowIntervalSeconds * 1000)
    $script:SlideshowTimer.Add_Tick({
        try {
            Advance-Slideshow
        } catch {
            Show-AppError -Title 'Slideshow failed' -ErrorRecord $_
        }
    })

    $statusStrip = New-Object System.Windows.Forms.StatusStrip
    $script:Status = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:Status.Spring = $true
    $script:Status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$statusStrip.Items.Add($script:Status)
    $script:Form.Controls.Add($statusStrip)

    $script:Split = New-Object System.Windows.Forms.SplitContainer
    $script:Split.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:Split.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $script:Split.SplitterWidth = 6
    $script:Split.SplitterDistance = 260
    $script:Split.Panel1MinSize = 180
    $script:Split.Panel1Collapsed = -not $script:PageListVisible
    $script:Form.Controls.Add($script:Split)
    $menu.BringToFront()
    $statusStrip.BringToFront()

    $script:PageList = New-Object System.Windows.Forms.ListBox
    $script:PageList.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:PageList.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
    $script:PageList.ForeColor = [System.Drawing.Color]::Gainsboro
    $script:PageList.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $script:PageList.Font = New-Object System.Drawing.Font 'Consolas', 10
    $script:PageList.HorizontalScrollbar = $true
    $script:PageList.IntegralHeight = $false
    $script:PageList.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $script:Split.Panel1.Controls.Add($script:PageList)

    Update-PageListStyle
    $script:PageList.Add_DrawItem({
        param($Sender, $Event)
        try {
            Draw-PageListItem $Sender $Event
        } catch {
            Show-AppError -Title 'Page list draw failed' -ErrorRecord $_
        }
    })
    $script:PageList.Add_SelectedIndexChanged({
        try {
            if (-not $script:SuppressPageListEvent -and $script:PageList.SelectedIndex -ge 0) {
                Go-ToPage ($script:PageList.SelectedIndex + 1)
            }
        } catch {
            Show-AppError -Title 'Page list selection failed' -ErrorRecord $_
        }
    })
    $script:PageList.Add_KeyDown({
        param($Sender, [System.Windows.Forms.KeyEventArgs]$Event)
        try {
            if ($Event.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $script:PageList.SelectedIndex -ge 0) {
                Go-ToPage ($script:PageList.SelectedIndex + 1)
                $Event.Handled = $true
            } else {
                Handle-KeyDown $Sender $Event
            }
        } catch {
            Show-AppError -Title 'Keyboard command failed' -ErrorRecord $_
        }
    })

    $script:Panel = New-Object System.Windows.Forms.Panel
    $script:Panel.BackColor = [System.Drawing.Color]::Black
    $script:Panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:Panel.AutoScroll = $true
    $script:Panel.TabStop = $true
    $script:Split.Panel2.Controls.Add($script:Panel)

    $script:Picture = New-Object System.Windows.Forms.PictureBox
    $script:Picture.BackColor = [System.Drawing.Color]::Black
    $script:Picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
    $script:Panel.Controls.Add($script:Picture)

    $script:OpenLabel = New-Object System.Windows.Forms.Label
    $script:OpenLabel.Text = "Drop a manga folder or archive here`nCtrl+O opens a folder`nSpace / Arrow keys turn pages"
    $script:OpenLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    $script:OpenLabel.BackColor = [System.Drawing.Color]::Transparent
    $script:OpenLabel.Font = New-Object System.Drawing.Font 'Segoe UI', 18
    $script:OpenLabel.AutoSize = $true
    $script:OpenLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:Panel.Controls.Add($script:OpenLabel)

    $script:Panel.Add_Resize({
        try {
            if ($script:OpenLabel) {
                $x = [Math]::Max(20, [int](($script:Panel.ClientSize.Width - $script:OpenLabel.Width) / 2))
                $y = [Math]::Max(20, [int](($script:Panel.ClientSize.Height - $script:OpenLabel.Height) / 2))
                $script:OpenLabel.Location = New-Object System.Drawing.Point $x, $y
            }
            Update-PictureLayout
        } catch {
            Write-AppLog -Message 'Panel resize failed' -ErrorRecord $_
        }
    })

    $script:Panel.Add_MouseWheel({
        param($Sender, $Event)
        try {
            Handle-MouseWheel $Sender $Event
        } catch {
            Show-AppError -Title 'Mouse wheel failed' -ErrorRecord $_
        }
    })
    $script:Picture.Add_MouseWheel({
        param($Sender, $Event)
        try {
            Handle-MouseWheel $Sender $Event
        } catch {
            Show-AppError -Title 'Mouse wheel failed' -ErrorRecord $_
        }
    })
    $script:Picture.Add_MouseDown({
        param($Sender, [System.Windows.Forms.MouseEventArgs]$Event)
        try {
            $script:Panel.Focus()
            $script:MouseDown = $true
            $script:MousePanning = $false
            $script:MouseDownPoint = $Event.Location
            $script:MouseDownScroll = $script:Panel.AutoScrollPosition
            $script:MouseDownButton = $Event.Button
            if ($Event.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                $script:Picture.Cursor = [System.Windows.Forms.Cursors]::SizeAll
            }
        } catch {
            Show-AppError -Title 'Mouse down failed' -ErrorRecord $_
        }
    })
    $script:Picture.Add_MouseMove({
        param($Sender, [System.Windows.Forms.MouseEventArgs]$Event)
        try {
            if (-not $script:MouseDown -or $script:MouseDownButton -ne [System.Windows.Forms.MouseButtons]::Left) {
                return
            }

            $dx = $Event.X - $script:MouseDownPoint.X
            $dy = $Event.Y - $script:MouseDownPoint.Y
            if (-not $script:MousePanning -and ([Math]::Abs($dx) + [Math]::Abs($dy)) -gt 6) {
                $script:MousePanning = $true
            }

            if ($script:MousePanning) {
                $startX = -$script:MouseDownScroll.X
                $startY = -$script:MouseDownScroll.Y
                $nextX = [Math]::Max(0, $startX - $dx)
                $nextY = [Math]::Max(0, $startY - $dy)
                $script:Panel.AutoScrollPosition = New-Object System.Drawing.Point $nextX, $nextY
            }
        } catch {
            Show-AppError -Title 'Mouse drag failed' -ErrorRecord $_
        }
    })
    $script:Picture.Add_MouseUp({
        param($Sender, [System.Windows.Forms.MouseEventArgs]$Event)
        try {
            $script:Picture.Cursor = [System.Windows.Forms.Cursors]::Default
            if ($script:MouseDown -and -not $script:MousePanning) {
                if ($Event.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                    Move-Page -1
                } elseif ($Event.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                    Move-Page 1
                }
            }
        } catch {
            Show-AppError -Title 'Mouse click failed' -ErrorRecord $_
        } finally {
            $script:MouseDown = $false
            $script:MousePanning = $false
            $script:MouseDownPoint = $null
            $script:MouseDownScroll = $null
            $script:MouseDownButton = $null
        }
    })

    $script:Form.Add_KeyDown({
        param($Sender, $Event)
        try {
            Handle-KeyDown $Sender $Event
        } catch {
            Show-AppError -Title 'Keyboard command failed' -ErrorRecord $_
        }
    })
    $script:Form.Add_MouseWheel({
        param($Sender, $Event)
        try {
            Handle-MouseWheel $Sender $Event
        } catch {
            Show-AppError -Title 'Mouse wheel failed' -ErrorRecord $_
        }
    })
    $script:Form.Add_DragEnter({
        param($Sender, [System.Windows.Forms.DragEventArgs]$Event)
        try {
            if ($Event.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
                $Event.Effect = [System.Windows.Forms.DragDropEffects]::Copy
            }
        } catch {
            Write-AppLog -Message 'Drag enter failed' -ErrorRecord $_
        }
    })
    $script:Form.Add_DragDrop({
        param($Sender, [System.Windows.Forms.DragEventArgs]$Event)
        $paths = $Event.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        if ($paths.Count -gt 0) {
            try {
                Open-ComicSource $paths[0]
                $script:OpenLabel.Visible = $false
            } catch {
                Show-AppError -Title 'Open failed' -ErrorRecord $_
            }
        }
    })

    $script:Form.Add_FormClosed({
        try {
            if ($script:SlideshowTimer) {
                $script:SlideshowTimer.Stop()
                $script:SlideshowTimer.Dispose()
                $script:SlideshowTimer = $null
            }
            Save-AppSettings
            if ($script:LoadedImage) {
                $script:LoadedImage.Dispose()
            }
            Clear-ThumbnailCache
            Clear-PageCache
            Write-AppLog -Message 'Shutdown'
        } catch {
            Write-AppLog -Message 'Shutdown cleanup failed' -ErrorRecord $_
        }
    })

    Update-Status

    if (-not [string]::IsNullOrWhiteSpace($InitialPath)) {
        try {
            Open-ComicSource $InitialPath
            $script:OpenLabel.Visible = $false
        } catch {
            Show-AppError -Title 'Open failed' -ErrorRecord $_
        }
    }

    [System.Windows.Forms.Application]::Run($script:Form)
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mm_cleanroom_selftest_{0}_{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    $oldSettingsDir = $script:SettingsDir
    $oldSettingsPath = $script:SettingsPath
    $oldExternalArchiveCacheDir = $script:ExternalArchiveCacheDir
    $script:SettingsDir = Join-Path $root 'portable-data'
    $script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
    $script:ExternalArchiveCacheDir = Join-Path $script:SettingsDir 'archive-cache'
    try {
        New-Item -ItemType File -Path (Join-Path $root 'page_10.jpg') | Out-Null
        New-Item -ItemType File -Path (Join-Path $root 'page_2.jpg') | Out-Null
        New-Item -ItemType File -Path (Join-Path $root 'page_1.jpg') | Out-Null
        New-Item -ItemType File -Path (Join-Path $root 'notes.txt') | Out-Null

        $folderPages = Get-FolderPages $root
        $folderNames = @($folderPages | ForEach-Object { $_.DisplayName })
        $expectedFolder = @('page_1.jpg', 'page_2.jpg', 'page_10.jpg')
        if (($folderNames -join '|') -ne ($expectedFolder -join '|')) {
            throw "Folder order failed: $($folderNames -join ', ')"
        }

        $zipPath = Join-Path $root 'book.cbz'
        $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entryName in @('ch1/page_10.png', 'ch1/page_2.png', 'ch1/page_1.png', 'readme.txt')) {
                $entry = $archive.CreateEntry($entryName)
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('x')
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }

        $zipPages = Get-ZipPages $zipPath
        $zipNames = @($zipPages | ForEach-Object { $_.DisplayName })
        $expectedZip = @('ch1/page_1.png', 'ch1/page_2.png', 'ch1/page_10.png')
        if (($zipNames -join '|') -ne ($expectedZip -join '|')) {
            throw "Zip order failed: $($zipNames -join ', ')"
        }

        $tar = Get-FirstCommandPath @('tar.exe', 'tar')
        if ($tar) {
            $tarSource = Join-Path $root 'tar-source'
            New-Item -ItemType Directory -Path $tarSource | Out-Null
            New-Item -ItemType File -Path (Join-Path $tarSource 'page_10.png') | Out-Null
            New-Item -ItemType File -Path (Join-Path $tarSource 'page_2.png') | Out-Null
            New-Item -ItemType File -Path (Join-Path $tarSource 'page_1.png') | Out-Null

            $tarPath = Join-Path $root 'book.cbt'
            $tarOutput = & $tar -cf $tarPath -C $tarSource . 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed creating self-test cbt: $tarOutput"
            }

            $tarPages = Get-ExternalArchivePages -ArchivePath $tarPath -Kind 'Tar'
            $tarNames = @($tarPages | ForEach-Object { $_.DisplayName })
            $expectedTar = @('page_1.png', 'page_2.png', 'page_10.png')
            if (($tarNames -join '|') -ne ($expectedTar -join '|')) {
                throw "Tar order failed: $($tarNames -join ', ')"
            }
        }

        $script:SlideshowIntervalSeconds = 5
        Set-SlideshowInterval -10
        if ($script:SlideshowIntervalSeconds -ne 1) {
            throw "Slideshow lower bound failed: $script:SlideshowIntervalSeconds"
        }
        Set-SlideshowInterval 100
        if ($script:SlideshowIntervalSeconds -ne 60) {
            throw "Slideshow upper bound failed: $script:SlideshowIntervalSeconds"
        }

        $script:Pages = @(Get-FolderPages $root)
        $script:CurrentSourcePath = $root
        $script:CurrentIndex = 0
        Toggle-Bookmark
        if (-not (@(Get-CurrentBookmarks) -contains 0)) {
            throw 'Bookmark add failed'
        }
        Toggle-Bookmark
        if (@(Get-CurrentBookmarks).Count -ne 0) {
            throw 'Bookmark remove failed'
        }

        Write-Host 'SELFTEST OK'
    } finally {
        $script:SettingsDir = $oldSettingsDir
        $script:SettingsPath = $oldSettingsPath
        $script:ExternalArchiveCacheDir = $oldExternalArchiveCacheDir
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-SmokeTest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OutputPath,
        [switch]$GenerateThumbnails
    )

    $resolvedSource = Resolve-ComicSource $Path
    $script:Pages = $resolvedSource.Pages
    $script:CurrentIndex = $resolvedSource.InitialIndex
    $script:DoublePage = $true

    $bitmaps = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
    $bitmaps.Add((Load-PageBitmap $script:Pages[$script:CurrentIndex]))
    if (($script:CurrentIndex + 1) -lt $script:Pages.Count) {
        $bitmaps.Add((Load-PageBitmap $script:Pages[$script:CurrentIndex + 1]))
    }

    $display = New-SpreadBitmap $bitmaps.ToArray()
    foreach ($bitmap in $bitmaps) {
        $bitmap.Dispose()
    }

    try {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $OutputPath = Join-Path (Get-Location) 'smoke-output.png'
        }
        $parent = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $display.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        if ($GenerateThumbnails) {
            $limit = [Math]::Min(4, $script:Pages.Count)
            for ($i = 0; $i -lt $limit; $i++) {
                [void](Get-PageThumbnail -Index $i)
            }
        }
        Write-Host "SMOKE OK: $($script:Pages.Count) page(s), wrote $OutputPath"
    } finally {
        $display.Dispose()
        Clear-ThumbnailCache
        Clear-PageCache
    }
}

if ($SelfTest) {
    Invoke-SelfTest
} elseif (-not [string]::IsNullOrWhiteSpace($SmokeTestPath)) {
    Invoke-SmokeTest -Path $SmokeTestPath -OutputPath $SmokeOut -GenerateThumbnails:$SmokeThumbnails
} else {
    Start-Reader $OpenPath
}
