# MangaMeeya Cleanroom for Windows

This is the first Windows-only runnable test build. It uses Windows PowerShell
and WinForms so it can run without installing Rust, .NET SDK, Electron, or
Python packages.

## Run

Double-click:

```text
Start MangaMeeya Cleanroom.vbs
```

Use `Start MangaMeeya Cleanroom.bat` if you want to see console output while
debugging.

Or run with a comic path:

```powershell
.\MangaMeeyaCleanroom.bat "C:\path\to\manga-folder"
.\MangaMeeyaCleanroom.bat "C:\path\to\book.cbz"
```

## Supported Sources

- Folders with image files.
- `.zip` and `.cbz` archives.
- `.tar` and `.cbt` archives through Windows `tar.exe`.
- `.rar`, `.cbr`, `.7z`, and `.cb7` archives when `7z.exe` is installed and
  available in `PATH`.
- Opening one image file loads its sibling images in the same folder.

## Supported Image Formats

The first Windows build uses GDI+ through WinForms:

- JPEG
- PNG
- BMP
- GIF first frame
- TIFF
- WebP when the Windows Imaging Component codec is available

AVIF, JPEG XL, PDF, animated GIF playback, and advanced filters are not in this
test build yet.

RAR/7z note: this build can open `.rar/.cbr/.7z/.cb7` through external 7-Zip.
If 7-Zip is not installed, it shows a clear error instead of failing silently.

## Debug Logs

Errors are written to:

```text
portable-data/debug.log
```

When an error dialog appears, it includes this path. You can also use
`Help -> Show Debug Log Path` or `Help -> Open Debug Log Folder`.

## Controls

- `Ctrl+O`: open folder.
- `Ctrl+Shift+O`: open zip/cbz/image.
- Drag and drop: open folder, zip, cbz, or image.
- `Space`, `Right`, `PageDown`: next page.
- `Left`, `PageUp`: previous page.
- `Up` / `Down`: scroll long pages; at the edge, turn to previous / next page.
- `Home` / `End`: first / last page.
- `Ctrl+G`: go to page.
- `Ctrl+PageUp` / `Ctrl+PageDown`: previous / next sibling folder or sibling zip/cbz.
- `F5`: slideshow play / pause.
- `[` / `]`: make slideshow slower / faster.
- `M`: toggle bookmark on current page.
- `F1`: show controls.
- `T`: show / hide page list.
- `B`: switch the page list between text and thumbnail mode.
- `F`: fit window.
- `W`: fit width.
- `H`: fit height.
- `O`: original size.
- `+` / `-`: zoom.
- `D`: toggle double-page spread.
- `R`: toggle right-to-left / left-to-right spread order.
- `Enter`: fullscreen.
- `Esc`: exit fullscreen, or close when already windowed.
- Left mouse click: next page.
- Right mouse click: previous page.
- Left mouse drag: pan large pages.
- Mouse wheel: scroll long pages; at the edge, turn page.
- `Ctrl` + mouse wheel: zoom.

## Page List

The left page list can be toggled with `T`. Selecting a page jumps directly to
that page and the list follows the current page while reading. Press `B` to
switch between compact text rows and thumbnail rows.

## Bookmarks

Press `M` to toggle a bookmark on the current page. Use the `Bookmarks` menu to
jump to bookmarked pages or clear bookmarks for the current comic. Bookmarks are
stored per comic path in the portable settings file.

## Stored State

The Windows build is portable. It writes settings next to the app in:

```text
portable-data/settings.json
```

It remembers:

- Fit mode.
- Single/double page mode.
- Right-to-left or left-to-right spread order.
- Window size.
- Page list visibility.
- Page list text/thumbnail mode.
- Slideshow interval.
- Recent paths.
- Last page position per recent path.
- Bookmarks per comic.

It also caches nearby pages in memory while reading to make normal page turns
feel less choppy.

Archives extracted through `tar.exe` or 7-Zip are cached under
`portable-data/archive-cache`. Use `File -> Clear Archive Cache` if you want to
delete that cache.

## Self-test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MangaMeeyaCleanroom.ps1 -SelfTest
```

Headless image smoke test:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MangaMeeyaCleanroom.ps1 -SmokeTestPath ..\test-output\sample-folder -SmokeOut ..\test-output\smoke-folder.png
```

## Generate a Test Comic

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\New-TestComic.ps1
.\MangaMeeyaCleanroom.bat ..\test-output\sample-folder
.\MangaMeeyaCleanroom.bat ..\test-output\sample.cbz
.\MangaMeeyaCleanroom.bat ..\test-output\sample.cbt
```

## Build a Portable Test Package

From the repo root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Build-WindowsPackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Build-WindowsPackage.ps1 -PackageName MangaMeeyaCleanroom-Windows-Sample -IncludeSample
```

The clean output appears in:

```text
dist\MangaMeeyaCleanroom-Windows
dist\MangaMeeyaCleanroom-Windows.zip
```

The sample output appears in:

```text
dist\MangaMeeyaCleanroom-Windows-Sample
dist\MangaMeeyaCleanroom-Windows-Sample.zip
```

Verify packages:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Verify-WindowsPackage.ps1 -PackageDir .\dist\MangaMeeyaCleanroom-Windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Verify-WindowsPackage.ps1 -PackageDir .\dist\MangaMeeyaCleanroom-Windows-Sample -RequireSample -RunSmoke
```
