# Roadmap

## Phase 0: Foundation

- Workspace, license, clean-room policy.
- Core model types.
- Folder source discovery.
- Natural sort.
- CLI harness.

Exit: `cargo test` passes and CLI can list pages in manga order.

## Phase 1: Local Reader Core

- Zip/cbz source.
- Image decode abstraction.
- Decode queue and prefetch plan.
- Memory budget model.
- Configurable actions and keymap model.

Exit: core can load a folder or cbz, decode nearby pages, and report layout
commands without a GUI.

## Phase 2: Desktop Spike

- Native window.
- Image presentation.
- Keyboard page navigation.
- Fit modes.
- GPU and software renderer comparison.

Exit: one person can read a full folder manga without touching the mouse.

## Phase 3: Desktop MVP

- File/folder open.
- Recent list.
- Basic settings file.
- Double-page mode.
- RTL/LTR mode.
- Thumbnail strip or quick page jump.
- Portable build layout.

Exit: usable Windows/macOS/Linux preview releases.

## Phase 4: Format and Filter Expansion

- RAR/7z/PDF story.
- WebP animation policy.
- Lanczos/Mitchell resize options.
- Color/sharpen filters.
- Optional plugin boundary.

Exit: enough compatibility to replace classic desktop readers for daily use.

## Phase 5: Mobile Shell Feasibility

- Rust core FFI boundary.
- Android file access spike.
- iOS document picker spike.
- Shared reading state format.

Exit: realistic decision on native mobile shells versus server/client support.
