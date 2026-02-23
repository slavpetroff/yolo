use std::fs;
use std::path::{Path, PathBuf};

/// List directories under `phases_dir` whose names start with two ASCII digits
/// followed by a hyphen (e.g. "01-setup"), returned sorted by name.
pub fn sorted_phase_dirs(phases_dir: &Path) -> Vec<(String, PathBuf)> {
    let mut dirs = Vec::new();
    if let Ok(entries) = fs::read_dir(phases_dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if entry.path().is_dir()
                && name.len() >= 3
                && name.as_bytes()[0].is_ascii_digit()
                && name.as_bytes()[1].is_ascii_digit()
                && name.as_bytes()[2] == b'-'
            {
                dirs.push((name, entry.path()));
            }
        }
    }
    dirs.sort_by(|a, b| a.0.cmp(&b.0));
    dirs
}
