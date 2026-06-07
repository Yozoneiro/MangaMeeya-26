# Windows Test Checklist

Use `MangaMeeyaCleanroom-Windows-Sample` for a quick smoke test, or
`MangaMeeyaCleanroom-Windows` for a clean portable package.

## Launch

- Run `Run Self Test.bat`.
- Run `Create Sample And Run.bat`.
- Run `Start MangaMeeya Cleanroom.vbs`.
- Run `Start MangaMeeya Cleanroom.bat` if console output is needed.
- Confirm the sample comic opens.

## Sources

- Open `sample\sample-folder`.
- Open `sample\sample.cbz`.
- Open `sample\sample.cbt`.
- Drag each source onto the window.

## Reading Controls

- `Space`, `Right`, `PageDown`: next page.
- `Left`, `PageUp`: previous page.
- Mouse wheel scrolls and turns at page edges.
- Left drag pans a large page.
- Left click turns next; right click turns previous.

## View

- `D` toggles double page.
- `R` toggles RTL/LTR spread order.
- `F`, `W`, `H`, `O` switch fit modes.
- `+`, `-`, and `Ctrl+mouse wheel` zoom.
- `Enter` toggles fullscreen.

## Navigation

- `T` toggles the page list.
- `B` toggles thumbnail mode.
- Selecting a page in the list jumps to it.
- `Ctrl+G` jumps to a page number.

## State

- Open a comic, move to a later page, close, reopen, and confirm position is restored.
- Press `M` to bookmark a page, close, reopen, and confirm the bookmark remains.
- Use the `Recent` menu.

## Slideshow

- `F5` starts/stops slideshow.
- `[` and `]` adjust interval.

## Archive Cache

- Open `sample.cbt`.
- Confirm `portable-data/archive-cache` appears.
- Use `File -> Clear Archive Cache`.

## Debug Logs

- Use `Help -> Show Debug Log Path`.
- Confirm `portable-data/debug.log` exists after launch or after an error.
- If an error dialog appears, copy the dialog text or the latest lines from
  `portable-data/debug.log`.
