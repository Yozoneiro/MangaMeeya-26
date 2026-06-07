# MangaMeeya Cleanroom

A clean-room, Apache-2.0 manga reader project inspired by the speed and
keyboard-first feel of classic desktop comic readers.

This repository intentionally keeps the long-term Rust core small, while the
first runnable Windows build lives in `windows/` so we can test the reading
loop immediately.

## Status

Windows test build available. The long-term Rust core is still early, but the
PowerShell/WinForms reader can already open folders and `.zip/.cbz` archives
for a first local test run.

Implemented now:

- Apache-2.0 project setup.
- Clean-room contribution rules.
- Rust workspace with `mm_core` and `mm_cli`.
- Folder image discovery.
- Manga-friendly natural page sorting.
- Basic reader model types and actions.
- Windows-only runnable reader prototype.

## Goals

- Fast local reading first.
- Windows, macOS, and Linux desktop support first.
- Keep the Rust core portable enough for future Android and iOS shells.
- Keyboard-first controls with configurable actions.
- CJK and Unicode paths as first-class behavior.
- Archive, image decoding, rendering, UI, and plugins kept as separable layers.

## Non-goals

- No original MangaMeeya code or assets.
- No binary patching or derivative distribution of the original program.
- No webtoon/source scraping ecosystem in the core reader.
- No heavy library manager in the MVP.

## Repository Layout

```text
crates/
  mm_core/   Core model, source discovery, sorting, future decode/cache traits.
  mm_cli/    Tiny CLI harness for exercising core behavior.
docs/
  architecture.md
  clean-room.md
  license-strategy.md
  roadmap.md
windows/
  MangaMeeyaCleanroom.ps1
  MangaMeeyaCleanroom.bat
```

## Usage

Windows test build:

```powershell
cd mangameeya-cleanroom
.\windows\MangaMeeyaCleanroom.bat
```

Or open a source directly:

```powershell
.\windows\MangaMeeyaCleanroom.bat "C:\path\to\manga-folder"
.\windows\MangaMeeyaCleanroom.bat "C:\path\to\book.cbz"
```

Details and controls are in `windows/README.md`.

Build clean and sample Windows packages:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Build-WindowsPackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Build-WindowsPackage.ps1 -PackageName MangaMeeyaCleanroom-Windows-Sample -IncludeSample
```

Rust core checks, once Rust is installed:

```powershell
cd mangameeya-cleanroom
cargo test
cargo run -p mm_cli -- "C:\path\to\manga-folder"
```

The CLI currently prints discovered image pages in natural order.

RAR, 7z, PDF, WebP, advanced rendering, and the native compiled UI come later.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
