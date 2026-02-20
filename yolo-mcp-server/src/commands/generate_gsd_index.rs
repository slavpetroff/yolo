use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;

/// Scan a gsd-archive directory and build INDEX.json with phases, milestones, quick_paths.
pub fn generate_index(cwd: &Path) -> Result<(String, i32), String> {
    let archive_dir = cwd.join(".yolo-planning/gsd-archive");
    if !archive_dir.is_dir() {
        return Ok(("".to_string(), 0));
    }

    // Extract GSD version from config.json
    let gsd_version = archive_dir
        .join("config.json")
        .exists()
        .then(|| {
            fs::read_to_string(archive_dir.join("config.json"))
                .ok()
                .and_then(|s| serde_json::from_str::<Value>(&s).ok())
                .and_then(|v| v.get("version").and_then(|v| v.as_str()).map(String::from))
        })
        .flatten()
        .unwrap_or_else(|| "unknown".to_string());

    let imported_at = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    // Scan phases
    let mut phases: Vec<Value> = Vec::new();
    let mut phases_total = 0u64;
    let mut phases_complete = 0u64;

    let phases_dir = archive_dir.join("phases");
    if phases_dir.is_dir() {
        let mut phase_entries: Vec<_> = fs::read_dir(&phases_dir)
            .map_err(|e| format!("Failed to read phases dir: {}", e))?
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.file_type().map(|ft| ft.is_dir()).unwrap_or(false)
                    && e.file_name()
                        .to_str()
                        .map(|n| n.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false))
                        .unwrap_or(false)
            })
            .collect();

        phase_entries.sort_by_key(|e| e.file_name().to_string_lossy().to_string());

        for entry in phase_entries {
            let name = entry.file_name().to_string_lossy().to_string();

            // Extract phase number
            let num_str: String = name.chars().take_while(|c| c.is_ascii_digit()).collect();
            let num: u64 = num_str.parse().unwrap_or(0);

            // Extract slug (everything after "N-")
            let slug = if name.len() > num_str.len() + 1 {
                &name[num_str.len() + 1..]
            } else {
                "unknown"
            };

            let phase_path = entry.path();

            // Count plans and summaries
            let plan_count = count_files_matching(&phase_path, "-PLAN.md");
            let summary_count = count_files_matching(&phase_path, "-SUMMARY.md");

            let status = if plan_count > 0 && summary_count >= plan_count {
                phases_complete += 1;
                "complete"
            } else {
                "in_progress"
            };

            phases.push(json!({
                "num": num,
                "slug": slug,
                "plans": plan_count,
                "status": status,
            }));

            phases_total += 1;
        }
    }

    // Extract milestones from ROADMAP.md
    let mut milestones: Vec<String> = Vec::new();
    let roadmap_path = archive_dir.join("ROADMAP.md");
    if roadmap_path.exists() {
        if let Ok(content) = fs::read_to_string(&roadmap_path) {
            for line in content.lines() {
                if let Some(stripped) = line.strip_prefix("## ") {
                    milestones.push(stripped.trim().to_string());
                }
            }
        }
    }

    // Build final JSON
    let index = json!({
        "imported_at": imported_at,
        "gsd_version": gsd_version,
        "phases_total": phases_total,
        "phases_complete": phases_complete,
        "milestones": milestones,
        "quick_paths": {
            "roadmap": "gsd-archive/ROADMAP.md",
            "project": "gsd-archive/PROJECT.md",
            "phases": "gsd-archive/phases/",
            "config": "gsd-archive/config.json",
        },
        "phases": phases,
    });

    let output = serde_json::to_string_pretty(&index)
        .map_err(|e| format!("Failed to serialize INDEX.json: {}", e))?;

    fs::write(archive_dir.join("INDEX.json"), &output)
        .map_err(|e| format!("Failed to write INDEX.json: {}", e))?;

    Ok((output, 0))
}

/// Count files in a directory whose name ends with the given suffix.
fn count_files_matching(dir: &Path, suffix: &str) -> u64 {
    fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .filter(|e| {
                    e.file_name()
                        .to_str()
                        .map(|n| n.ends_with(suffix))
                        .unwrap_or(false)
                })
                .count() as u64
        })
        .unwrap_or(0)
}

/// CLI entry point: `yolo gsd-index`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let _ = args; // no additional args needed
    generate_index(cwd)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_archive(dir: &Path) {
        let archive = dir.join(".yolo-planning/gsd-archive");
        fs::create_dir_all(archive.join("phases/01-setup")).unwrap();
        fs::create_dir_all(archive.join("phases/02-feature")).unwrap();

        // config.json
        fs::write(
            archive.join("config.json"),
            r#"{"version":"1.5.0"}"#,
        )
        .unwrap();

        // Phase 1: complete (1 plan + 1 summary)
        fs::write(archive.join("phases/01-setup/01-PLAN.md"), "plan").unwrap();
        fs::write(archive.join("phases/01-setup/01-SUMMARY.md"), "summary").unwrap();

        // Phase 2: in_progress (1 plan, no summary)
        fs::write(archive.join("phases/02-feature/01-PLAN.md"), "plan").unwrap();

        // ROADMAP.md
        fs::write(
            archive.join("ROADMAP.md"),
            "# Roadmap\n\n## Initial Setup\n\n## Feature Build\n",
        )
        .unwrap();
    }

    #[test]
    fn test_no_archive_dir() {
        let dir = TempDir::new().unwrap();
        let (output, code) = generate_index(dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.is_empty());
    }

    #[test]
    fn test_basic_index_generation() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let (output, code) = generate_index(dir.path()).unwrap();
        assert_eq!(code, 0);

        let index: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(index["gsd_version"], "1.5.0");
        assert_eq!(index["phases_total"], 2);
        assert_eq!(index["phases_complete"], 1);
    }

    #[test]
    fn test_phases_detail() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let (output, _) = generate_index(dir.path()).unwrap();
        let index: Value = serde_json::from_str(&output).unwrap();

        let phases = index["phases"].as_array().unwrap();
        assert_eq!(phases.len(), 2);

        assert_eq!(phases[0]["num"], 1);
        assert_eq!(phases[0]["slug"], "setup");
        assert_eq!(phases[0]["status"], "complete");
        assert_eq!(phases[0]["plans"], 1);

        assert_eq!(phases[1]["num"], 2);
        assert_eq!(phases[1]["slug"], "feature");
        assert_eq!(phases[1]["status"], "in_progress");
    }

    #[test]
    fn test_milestones_extraction() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let (output, _) = generate_index(dir.path()).unwrap();
        let index: Value = serde_json::from_str(&output).unwrap();

        let milestones = index["milestones"].as_array().unwrap();
        assert_eq!(milestones.len(), 2);
        assert_eq!(milestones[0], "Initial Setup");
        assert_eq!(milestones[1], "Feature Build");
    }

    #[test]
    fn test_quick_paths() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let (output, _) = generate_index(dir.path()).unwrap();
        let index: Value = serde_json::from_str(&output).unwrap();

        assert_eq!(index["quick_paths"]["roadmap"], "gsd-archive/ROADMAP.md");
        assert_eq!(index["quick_paths"]["config"], "gsd-archive/config.json");
    }

    #[test]
    fn test_index_file_written() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let _ = generate_index(dir.path()).unwrap();
        let index_file = dir.path().join(".yolo-planning/gsd-archive/INDEX.json");
        assert!(index_file.exists());

        let content = fs::read_to_string(&index_file).unwrap();
        let index: Value = serde_json::from_str(&content).unwrap();
        assert_eq!(index["phases_total"], 2);
    }

    #[test]
    fn test_execute_cli() {
        let dir = TempDir::new().unwrap();
        setup_archive(dir.path());

        let args: Vec<String> = vec!["yolo".into(), "gsd-index".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("gsd_version"));
    }

    #[test]
    fn test_missing_config() {
        let dir = TempDir::new().unwrap();
        let archive = dir.path().join(".yolo-planning/gsd-archive");
        fs::create_dir_all(&archive).unwrap();

        let (output, code) = generate_index(dir.path()).unwrap();
        assert_eq!(code, 0);
        let index: Value = serde_json::from_str(&output).unwrap();
        assert_eq!(index["gsd_version"], "unknown");
    }
}
