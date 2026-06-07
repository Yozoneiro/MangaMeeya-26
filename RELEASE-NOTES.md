# MangaMeeya Cleanroom Windows Test Build

Version: `0.1.0-windows-test`

This is a clean-room Windows-only test build of MangaMeeya Cleanroom.

## Included

- Portable Windows runner.
- No-console `.vbs` launcher and console `.bat` launcher.
- Folder image reading.
- `.zip/.cbz` reading.
- `.tar/.cbt` reading through Windows `tar.exe`.
- Optional `.rar/.cbr/.7z/.cb7` reading through external `7z.exe`.
- Natural manga page sorting.
- Single and double page modes.
- Right-to-left and left-to-right spread order.
- Fit window, fit width, fit height, original size, and zoom.
- Drag panning and mouse wheel scrolling.
- Page list and thumbnail page list.
- Recent items and last-read position.
- Per-comic bookmarks.
- Slideshow mode.
- Portable settings and archive cache under `portable-data`.
- Debug logging to `portable-data/debug.log`, plus Help menu entries for the
  log path and log folder.

## Known Limits

- RAR/7z formats require 7-Zip in `PATH`; this machine did not have 7-Zip for local validation.
- WebP depends on the Windows Imaging Component codec available on the machine.
- PDF, AVIF, JPEG XL, animated GIF playback, and advanced filters are not included yet.
- This build uses PowerShell/WinForms as the Windows test shell.

## Clean-room Statement

No original MangaMeeya source code, binary code, reverse-engineered code, icons,
or assets are included.
