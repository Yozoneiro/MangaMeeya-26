//! Tiny CLI harness for exercising core behavior before the desktop UI exists.

use mm_core::scan_folder;
use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let Some(input) = env::args_os().nth(1) else {
        eprintln!("usage: mm_cli <folder-or-image>");
        return ExitCode::FAILURE;
    };

    let root = PathBuf::from(input);
    match scan_folder(&root) {
        Ok(pages) => {
            println!("{} page(s)", pages.len());
            for page in pages {
                println!("{:>5}  {}", page.index + 1, page.path.display());
            }
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("failed to scan {}: {error}", root.display());
            ExitCode::FAILURE
        }
    }
}
