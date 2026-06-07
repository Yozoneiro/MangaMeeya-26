//! Local source discovery.

use crate::model::PageEntry;
use crate::order::natural_cmp;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Image extensions accepted by the first local-folder prototype.
pub const SUPPORTED_IMAGE_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "gif", "bmp", "avif", "jxl",
];

/// Return whether a path looks like a supported image file.
#[must_use]
pub fn is_supported_image_path(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .is_some_and(|extension| SUPPORTED_IMAGE_EXTENSIONS.contains(&extension.as_str()))
}

/// Scan a folder or single file into naturally sorted page entries.
///
/// Directories are scanned recursively. Unsupported files are ignored.
pub fn scan_folder(root: &Path) -> io::Result<Vec<PageEntry>> {
    let mut paths = Vec::new();

    if root.is_file() {
        if is_supported_image_path(root) {
            paths.push(root.to_path_buf());
        }
    } else {
        walk_dir(root, &mut paths)?;
    }

    paths.sort_by(|left, right| {
        let left_name = normalized_sort_key(left);
        let right_name = normalized_sort_key(right);
        natural_cmp(&left_name, &right_name)
    });

    Ok(paths
        .into_iter()
        .enumerate()
        .map(|(index, path)| PageEntry::local_image(index, path))
        .collect())
}

fn walk_dir(root: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    let mut entries = fs::read_dir(root)?.collect::<Result<Vec<_>, io::Error>>()?;
    entries.sort_by(|left, right| {
        natural_cmp(
            &left.file_name().to_string_lossy(),
            &right.file_name().to_string_lossy(),
        )
    });

    for entry in entries {
        let file_type = entry.file_type()?;
        let path = entry.path();
        if file_type.is_dir() {
            walk_dir(&path, out)?;
        } else if file_type.is_file() && is_supported_image_path(&path) {
            out.push(path);
        }
    }

    Ok(())
}

fn normalized_sort_key(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::{is_supported_image_path, scan_folder, SUPPORTED_IMAGE_EXTENSIONS};
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn recognizes_supported_images_case_insensitively() {
        assert!(is_supported_image_path(Path::new("page.JPG")));
        assert!(is_supported_image_path(Path::new("cover.webp")));
        assert!(is_supported_image_path(Path::new("spread.JXL")));
        assert!(!is_supported_image_path(Path::new("notes.txt")));
        assert!(!is_supported_image_path(Path::new("no_extension")));
    }

    #[test]
    fn extension_list_stays_small_and_intentional() {
        assert!(SUPPORTED_IMAGE_EXTENSIONS.contains(&"jpg"));
        assert!(SUPPORTED_IMAGE_EXTENSIONS.contains(&"png"));
        assert!(SUPPORTED_IMAGE_EXTENSIONS.contains(&"webp"));
        assert!(SUPPORTED_IMAGE_EXTENSIONS.len() <= 10);
    }

    #[test]
    fn scans_folder_in_natural_order() -> io::Result<()> {
        let root = unique_temp_dir();
        fs::create_dir_all(&root)?;
        fs::write(root.join("page_10.jpg"), [])?;
        fs::write(root.join("page_2.jpg"), [])?;
        fs::write(root.join("page_1.jpg"), [])?;
        fs::write(root.join("notes.txt"), [])?;

        let pages = scan_folder(&root)?;
        let names = pages
            .iter()
            .map(|page| page.display_name.as_str())
            .collect::<Vec<_>>();

        fs::remove_dir_all(&root)?;

        assert_eq!(names, vec!["page_1.jpg", "page_2.jpg", "page_10.jpg"]);
        Ok(())
    }

    fn unique_temp_dir() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |duration| duration.as_nanos());
        std::env::temp_dir().join(format!("mm_core_scan_test_{}_{}", std::process::id(), nanos))
    }
}
