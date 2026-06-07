//! Shared reader model types.

use std::path::PathBuf;

/// A page candidate discovered from a source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PageEntry {
    /// Zero-based page index after sorting.
    pub index: usize,
    /// Local path for this first prototype.
    pub path: PathBuf,
    /// UI-friendly name derived from the path.
    pub display_name: String,
    /// Source-specific kind.
    pub kind: PageKind,
}

impl PageEntry {
    /// Create a local image page entry.
    #[must_use]
    pub fn local_image(index: usize, path: PathBuf) -> Self {
        let display_name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| path.to_string_lossy().into_owned());

        Self {
            index,
            path,
            display_name,
            kind: PageKind::LocalImage,
        }
    }
}

/// The source family for a page.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageKind {
    /// A regular image file from the local filesystem.
    LocalImage,
}

/// Reading flow for page advance and double-page pairing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadingDirection {
    /// Western comics and most image sets.
    LeftToRight,
    /// Japanese manga-style reading order.
    RightToLeft,
}

/// How a page should be fitted into the viewport.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FitMode {
    /// Fit the full page inside the viewport.
    Window,
    /// Fit the page width to the viewport.
    Width,
    /// Fit the page height to the viewport.
    Height,
    /// Show pixels at native size.
    Original,
}

/// Single-page or spread display.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewerMode {
    /// Show one page.
    SinglePage,
    /// Show two pages as a spread.
    DoublePage,
}

/// Stable semantic actions. Platform keymaps should bind to these.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewerAction {
    /// Move to the next logical page.
    NextPage,
    /// Move to the previous logical page.
    PreviousPage,
    /// Jump to the first page.
    FirstPage,
    /// Jump to the last page.
    LastPage,
    /// Increase zoom.
    ZoomIn,
    /// Decrease zoom.
    ZoomOut,
    /// Reset zoom to the active fit mode.
    ResetZoom,
    /// Toggle single/double page display.
    ToggleDoublePage,
    /// Toggle left-to-right/right-to-left reading.
    ToggleReadingDirection,
    /// Toggle fullscreen.
    ToggleFullscreen,
}
