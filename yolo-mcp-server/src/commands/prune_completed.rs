use std::path::Path;

/// Scans a phase directory for completed phases (where every PLAN.md has a
/// matching SUMMARY.md) and removes the PLAN.md files, keeping only SUMMARYs.
///
/// Usage: yolo prune-completed <phase-dir>
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let phase_dir = if args.len() > 2 {
        let p = Path::new(&args[2]);
        if p.is_absolute() { p.to_path_buf() } else { cwd.join(p) }
    } else {
        return Err("Usage: yolo prune-completed <phase-dir>".to_string());
    };

    if !phase_dir.is_dir() {
        return Ok((
            serde_json::json!({
                "ok": false,
                "cmd": "prune-completed",
                "error": format!("Directory not found: {}", phase_dir.display())
            }).to_string(),
            1,
        ));
    }

    let mut pruned_phases = 0u32;
    let mut files_removed = 0u32;
    let mut bytes_freed: u64 = 0;

    // Scan for subdirectories matching NN-* or NN pattern (phase directories)
    let entries = std::fs::read_dir(&phase_dir).map_err(|e| e.to_string())?;
    let mut phase_dirs: Vec<_> = entries
        .flatten()
        .filter(|e| {
            let name = e.file_name();
            let name_str = name.to_string_lossy();
            e.path().is_dir() && is_phase_dir_name(&name_str)
        })
        .collect();
    phase_dirs.sort_by_key(|e| e.file_name());

    for entry in &phase_dirs {
        let dir = entry.path();
        if is_phase_complete(&dir) {
            let removed = prune_phase_plans(&dir);
            if removed.0 > 0 {
                pruned_phases += 1;
                files_removed += removed.0;
                bytes_freed += removed.1;
            }
        }
    }

    let result = serde_json::json!({
        "ok": true,
        "cmd": "prune-completed",
        "pruned_phases": pruned_phases,
        "files_removed": files_removed,
        "bytes_freed": bytes_freed
    });

    Ok((result.to_string(), 0))
}

/// Checks if a directory name looks like a phase directory (starts with digits).
fn is_phase_dir_name(name: &str) -> bool {
    name.chars().next().map_or(false, |c| c.is_ascii_digit())
}

/// A phase is complete when every *-PLAN.md or *.plan.jsonl has a corresponding
/// SUMMARY.md file. If there are no plans at all, the phase is not "complete"
/// (it has nothing to prune).
fn is_phase_complete(dir: &Path) -> bool {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return false,
    };

    let files: Vec<String> = entries
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            if e.path().is_file() { Some(name) } else { None }
        })
        .collect();

    // Find all plan files
    let plans: Vec<&String> = files.iter()
        .filter(|f| f.ends_with("-PLAN.md") || f.ends_with(".plan.jsonl"))
        .collect();

    if plans.is_empty() {
        return false;
    }

    // Check each plan has a corresponding SUMMARY
    for plan in &plans {
        let summary_name = plan_to_summary_name(plan);
        if !files.iter().any(|f| f == &summary_name) {
            return false;
        }
    }

    true
}

/// Converts a plan filename to its expected summary filename.
/// e.g. "01-01-PLAN.md" -> "01-01-SUMMARY.md"
///      "01-01.plan.jsonl" -> "01-01-SUMMARY.md"
fn plan_to_summary_name(plan: &str) -> String {
    if plan.ends_with("-PLAN.md") {
        plan.replace("-PLAN.md", "-SUMMARY.md")
    } else if plan.ends_with(".plan.jsonl") {
        plan.replace(".plan.jsonl", "-SUMMARY.md")
    } else {
        format!("{}-SUMMARY.md", plan)
    }
}

/// Removes PLAN.md files from a completed phase directory.
/// Returns (files_removed, bytes_freed).
fn prune_phase_plans(dir: &Path) -> (u32, u64) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return (0, 0),
    };

    let mut count = 0u32;
    let mut bytes = 0u64;

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.ends_with("-PLAN.md") || name_str.ends_with(".plan.jsonl") {
            if let Ok(meta) = entry.metadata() {
                bytes += meta.len();
            }
            if std::fs::remove_file(entry.path()).is_ok() {
                count += 1;
            }
        }
    }

    (count, bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_prune_removes_plans_keeps_summaries() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        let phase1 = phases.join("01-foundation");
        fs::create_dir_all(&phase1).unwrap();

        // Complete phase: both plan and summary exist
        fs::write(phase1.join("01-01-PLAN.md"), "plan content").unwrap();
        fs::write(phase1.join("01-01-SUMMARY.md"), "summary content").unwrap();

        let args = vec![
            "yolo".to_string(),
            "prune-completed".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["pruned_phases"], 1);
        assert_eq!(json["files_removed"], 1);

        // PLAN.md removed, SUMMARY.md preserved
        assert!(!phase1.join("01-01-PLAN.md").exists());
        assert!(phase1.join("01-01-SUMMARY.md").exists());
    }

    #[test]
    fn test_prune_skips_incomplete_phases() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        let phase1 = phases.join("01-foundation");
        fs::create_dir_all(&phase1).unwrap();

        // Incomplete phase: plan exists but no summary
        fs::write(phase1.join("01-01-PLAN.md"), "plan content").unwrap();

        let args = vec![
            "yolo".to_string(),
            "prune-completed".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["pruned_phases"], 0);
        assert_eq!(json["files_removed"], 0);

        // PLAN.md should still exist
        assert!(phase1.join("01-01-PLAN.md").exists());
    }

    #[test]
    fn test_prune_multi_plan_phase() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        let phase1 = phases.join("02-features");
        fs::create_dir_all(&phase1).unwrap();

        // Two plans, both with summaries = complete
        fs::write(phase1.join("02-01-PLAN.md"), "plan 1").unwrap();
        fs::write(phase1.join("02-01-SUMMARY.md"), "summary 1").unwrap();
        fs::write(phase1.join("02-02-PLAN.md"), "plan 2").unwrap();
        fs::write(phase1.join("02-02-SUMMARY.md"), "summary 2").unwrap();

        let args = vec![
            "yolo".to_string(),
            "prune-completed".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["pruned_phases"], 1);
        assert_eq!(json["files_removed"], 2);

        // Both plans removed, both summaries preserved
        assert!(!phase1.join("02-01-PLAN.md").exists());
        assert!(!phase1.join("02-02-PLAN.md").exists());
        assert!(phase1.join("02-01-SUMMARY.md").exists());
        assert!(phase1.join("02-02-SUMMARY.md").exists());
    }

    #[test]
    fn test_prune_partial_summaries_skipped() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        let phase1 = phases.join("03-polish");
        fs::create_dir_all(&phase1).unwrap();

        // Two plans, only one has a summary = incomplete
        fs::write(phase1.join("03-01-PLAN.md"), "plan 1").unwrap();
        fs::write(phase1.join("03-01-SUMMARY.md"), "summary 1").unwrap();
        fs::write(phase1.join("03-02-PLAN.md"), "plan 2 (no summary)").unwrap();

        let args = vec![
            "yolo".to_string(),
            "prune-completed".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["pruned_phases"], 0);
        assert_eq!(json["files_removed"], 0);

        // All files untouched
        assert!(phase1.join("03-01-PLAN.md").exists());
        assert!(phase1.join("03-02-PLAN.md").exists());
    }
}
