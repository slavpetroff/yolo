use std::fs;
use std::path::{Path, PathBuf};
use serde::Deserialize;

/// Typed config struct for `.yolo-planning/config.json`.
/// Uses `#[serde(default)]` so missing keys fall back to defaults
/// and unknown keys are silently ignored.
#[derive(Deserialize)]
#[serde(default)]
pub struct YoloConfig {
    pub effort: String,
    pub autonomy: String,
    pub auto_commit: bool,
    pub planning_tracking: String,
    pub auto_push: String,
    pub verification_tier: String,
    pub prefer_teams: String,
    pub max_tasks_per_plan: u32,
    pub context_compiler: bool,
    pub model_profile: String,
    pub review_gate: String,
    pub qa_gate: String,
    pub review_max_cycles: u32,
    pub qa_max_cycles: u32,
}

impl Default for YoloConfig {
    fn default() -> Self {
        Self {
            effort: "balanced".into(),
            autonomy: "standard".into(),
            auto_commit: true,
            planning_tracking: "manual".into(),
            auto_push: "never".into(),
            verification_tier: "standard".into(),
            prefer_teams: "always".into(),
            max_tasks_per_plan: 5,
            context_compiler: true,
            model_profile: "quality".into(),
            review_gate: "on_request".into(),
            qa_gate: "on_request".into(),
            review_max_cycles: 3,
            qa_max_cycles: 3,
        }
    }
}

/// Load config from a JSON file, falling back to defaults on any error.
pub fn load_config(config_path: &Path) -> YoloConfig {
    fs::read_to_string(config_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

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
