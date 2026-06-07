# Architecture

The design keeps the hot path small and portable.

```text
mm_cli / future desktop shells
        |
        v
mm_core model and actions
        |
        +-- source discovery: folder, zip/cbz, later rar/7z/pdf plugins
        +-- ordering: natural manga page sort
        +-- decode queue: image bytes -> decoded surfaces
        +-- cache: current page, nearby pages, thumbnails
        +-- layout: single page, double page, fit modes, reading direction
        +-- render bridge: platform-neutral texture commands
```

## Crate Boundaries

`mm_core` owns:

- Page identity and metadata.
- Folder and archive source traits.
- Natural ordering.
- Viewer actions.
- Future decode/cache/layout traits.

Future `mm_desktop` owns:

- Windowing.
- Menus.
- Native file dialogs.
- Input mapping.
- Rendering backend selection.

Future mobile shells own:

- Platform navigation.
- Sandboxed file access.
- Touch gestures.
- Store-specific packaging.

## Rendering Direction

The preferred desktop path is a Rust-native window with GPU rendering. A
software renderer should remain possible for older machines and remote desktop
sessions.

Candidate stack:

- Core: Rust.
- Window/input: winit.
- GPU: wgpu.
- Thin UI: custom overlay first, Iced/egui/Slint only if they do not hurt input
  latency and CJK behavior.
- Mobile: reuse Rust core through FFI, with Kotlin/Swift shells.

## MVP Boundary

The first real MVP should support:

- Open folder.
- Open zip/cbz.
- JPEG, PNG, WebP, GIF first-frame.
- Natural page order.
- Single and double page.
- Right-to-left and left-to-right reading.
- Fit width, fit height, fit window, original size.
- Keyboard actions close to classic manga readers.
- Recent files.

RAR, 7z, PDF, advanced filters, OPDS, and library management should come after
the local reading loop feels fast.
