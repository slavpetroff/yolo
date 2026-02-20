use serde_json::{json, Value};
use std::fs;
use std::path::Path;

/// Read archive structure and extract project name, milestones, phases, current work.
pub fn infer_summary(archive_dir: &Path) -> Result<Value, String> {
    let empty = json!({
        "latest_milestone": null,
        "recent_phases": [],
        "key_decisions": [],
        "current_work": null,
    });

    if !archive_dir.is_dir() {
        return Ok(empty);
    }

    let index_file = archive_dir.join("INDEX.json");
    let index: Option<Value> = if index_file.exists() {
        fs::read_to_string(&index_file)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
    } else {
        None
    };

    // --- Extract latest milestone from INDEX.json ---
    let latest_milestone = extract_latest_milestone(&index);

    // --- Extract last 2-3 completed phases ---
    let recent_phases = extract_recent_phases(&index, archive_dir);

    // --- Extract key decisions from STATE.md ---
    let key_decisions = extract_key_decisions(archive_dir);

    // --- Extract current work status ---
    let current_work = extract_current_work(&index, archive_dir);

    Ok(json!({
        "latest_milestone": latest_milestone,
        "recent_phases": recent_phases,
        "key_decisions": key_decisions,
        "current_work": current_work,
    }))
}

fn extract_latest_milestone(index: &Option<Value>) -> Value {
    let index = match index {
        Some(i) => i,
        None => return Value::Null,
    };

    let milestones = match index.get("milestones").and_then(|v| v.as_array()) {
        Some(ms) if !ms.is_empty() => ms,
        _ => return Value::Null,
    };

    let name = match milestones.last().and_then(|v| v.as_str()) {
        Some(n) => n,
        None => return Value::Null,
    };

    let phases_total = index
        .get("phases_total")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let phases_complete = index
        .get("phases_complete")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);

    let status = if phases_total > 0 && phases_complete == phases_total {
        "complete"
    } else {
        "in_progress"
    };

    json!({
        "name": name,
        "phase_count": phases_total,
        "status": status,
    })
}

fn extract_recent_phases(index: &Option<Value>, archive_dir: &Path) -> Vec<Value> {
    let index = match index {
        Some(i) => i,
        None => return vec![],
    };

    let phases = match index.get("phases").and_then(|v| v.as_array()) {
        Some(p) => p,
        None => return vec![],
    };

    // Get completed phases, take last 3
    let completed: Vec<&Value> = phases
        .iter()
        .filter(|p| p.get("status").and_then(|v| v.as_str()) == Some("complete"))
        .collect();

    let start = if completed.len() > 3 {
        completed.len() - 3
    } else {
        0
    };
    let recent = &completed[start..];

    // Try to enrich with task/commit counts from ROADMAP.md
    let roadmap_data = parse_roadmap_table(archive_dir);

    recent
        .iter()
        .map(|p| {
            let num = p.get("num").and_then(|v| v.as_u64()).unwrap_or(0);
            let slug = p.get("slug").and_then(|v| v.as_str()).unwrap_or("unknown");
            let plans = p.get("plans").and_then(|v| v.as_u64()).unwrap_or(0);

            let (tasks, commits) = roadmap_data
                .get(&num)
                .map(|(t, c)| (*t, *c))
                .unwrap_or((plans, 0));

            json!({
                "name": format!("{}-{}", num, slug),
                "tasks": tasks,
                "commits": commits,
            })
        })
        .collect()
}

/// Parse ROADMAP.md progress table to get tasks/commits per phase.
fn parse_roadmap_table(archive_dir: &Path) -> std::collections::HashMap<u64, (u64, u64)> {
    let mut data = std::collections::HashMap::new();
    let roadmap_path = archive_dir.join("ROADMAP.md");

    if !roadmap_path.exists() {
        return data;
    }

    let content = match fs::read_to_string(&roadmap_path) {
        Ok(c) => c,
        Err(_) => return data,
    };

    // Parse table rows: | Phase | Status | Plans | Tasks | Commits |
    for line in content.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') {
            continue;
        }
        let cols: Vec<&str> = trimmed.split('|').collect();
        if cols.len() < 6 {
            continue;
        }
        // cols[0] is empty (before first |), cols[1] is phase, etc.
        let phase_str = cols[1].trim();
        let phase: u64 = match phase_str.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };
        // cols[4] = tasks, cols[5] = commits
        let tasks: u64 = cols.get(4).and_then(|s| s.trim().parse().ok()).unwrap_or(0);
        let commits: u64 = cols.get(5).and_then(|s| s.trim().parse().ok()).unwrap_or(0);
        data.insert(phase, (tasks, commits));
    }

    data
}

fn extract_key_decisions(archive_dir: &Path) -> Vec<String> {
    let state_file = archive_dir.join("STATE.md");
    if !state_file.exists() {
        return vec![];
    }

    let content = match fs::read_to_string(&state_file) {
        Ok(c) => c,
        Err(_) => return vec![],
    };

    let mut decisions: Vec<String> = Vec::new();
    let mut in_decisions = false;

    for line in content.lines() {
        // Detect Key Decisions / Decisions section header
        if line.starts_with("## ") && line.to_lowercase().contains("decisions") {
            in_decisions = true;
            continue;
        }
        // Stop at next section header
        if in_decisions && line.starts_with("## ") {
            break;
        }
        if !in_decisions {
            continue;
        }

        // Parse table rows: | Decision | Date | Rationale |
        if line.starts_with('|') && !line.contains("---") {
            let cols: Vec<&str> = line.split('|').collect();
            if cols.len() >= 3 {
                let decision = cols[1].trim();
                if !decision.is_empty()
                    && !decision.starts_with("Decision")
                    && !decision.contains("_(No decisions")
                {
                    decisions.push(decision.to_string());
                }
            }
        }

        // Parse bullet items: - Decision text
        let trimmed = line.trim();
        if let Some(stripped) = trimmed.strip_prefix("- ") {
            if !stripped.is_empty() {
                decisions.push(stripped.to_string());
            }
        }
    }

    decisions
}

fn extract_current_work(index: &Option<Value>, archive_dir: &Path) -> Value {
    // Try INDEX.json first — find first in_progress phase
    if let Some(idx) = index {
        if let Some(phases) = idx.get("phases").and_then(|v| v.as_array()) {
            for phase in phases {
                if phase.get("status").and_then(|v| v.as_str()) == Some("in_progress") {
                    let num = phase.get("num").and_then(|v| v.as_u64()).unwrap_or(0);
                    let slug = phase
                        .get("slug")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown");
                    return json!({
                        "phase": format!("{}-{}", num, slug),
                        "status": "in_progress",
                    });
                }
            }
        }
    }

    // Fallback to STATE.md
    let state_file = archive_dir.join("STATE.md");
    if !state_file.exists() {
        return Value::Null;
    }

    let content = match fs::read_to_string(&state_file) {
        Ok(c) => c,
        Err(_) => return Value::Null,
    };

    let mut phase_name: Option<String> = None;
    let mut phase_status = "unknown".to_string();

    for line in content.lines() {
        if line.starts_with("**Current Phase:**") {
            phase_name = Some(
                line.trim_start_matches("**Current Phase:**")
                    .trim()
                    .to_string(),
            );
        }
        if line.starts_with("**Status:**") {
            phase_status = line
                .trim_start_matches("**Status:**")
                .trim()
                .to_string();
        }
    }

    match phase_name {
        Some(name) if !name.is_empty() => json!({
            "phase": name,
            "status": phase_status,
        }),
        _ => Value::Null,
    }
}

/// CLI entry point: `yolo gsd-summary [archive_dir]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let archive_dir = if args.len() > 2 {
        std::path::PathBuf::from(&args[2])
    } else {
        cwd.join(".yolo-planning/gsd-archive")
    };

    let result = infer_summary(&archive_dir)?;
    let output = serde_json::to_string_pretty(&result)
        .map_err(|e| format!("Failed to serialize: {}", e))?;

    Ok((output, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_archive(dir: &Path) -> std::path::PathBuf {
        let archive = dir.join("gsd-archive");
        fs::create_dir_all(&archive).unwrap();
        archive
    }

    fn write_index(archive: &Path, phases_total: u64, phases_complete: u64) {
        let index = json!({
            "imported_at": "2026-02-20T10:00:00Z",
            "gsd_version": "1.5.0",
            "phases_total": phases_total,
            "phases_complete": phases_complete,
            "milestones": ["Alpha Release", "Beta Release"],
            "phases": [
                {"num": 1, "slug": "setup", "plans": 3, "status": "complete"},
                {"num": 2, "slug": "feature", "plans": 5, "status": "complete"},
                {"num": 3, "slug": "polish", "plans": 2, "status": "in_progress"},
            ],
        });
        fs::write(
            archive.join("INDEX.json"),
            serde_json::to_string_pretty(&index).unwrap(),
        )
        .unwrap();
    }

    fn write_state(archive: &Path) {
        fs::write(
            archive.join("STATE.md"),
            "# State\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|----------|------|-----------|\n| Use Rust | 2026-02-01 | Performance |\n| Skip QA | 2026-02-10 | Time constraint |\n\n## Other\n\nSome text.\n",
        )
        .unwrap();
    }

    #[test]
    fn test_missing_archive() {
        let dir = TempDir::new().unwrap();
        let result = infer_summary(&dir.path().join("nonexistent")).unwrap();
        assert!(result["latest_milestone"].is_null());
        assert_eq!(result["recent_phases"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn test_empty_archive() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        let result = infer_summary(&archive).unwrap();
        assert!(result["latest_milestone"].is_null());
    }

    #[test]
    fn test_latest_milestone() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        write_index(&archive, 3, 2);

        let result = infer_summary(&archive).unwrap();
        let milestone = &result["latest_milestone"];
        assert_eq!(milestone["name"], "Beta Release");
        assert_eq!(milestone["status"], "in_progress");
        assert_eq!(milestone["phase_count"], 3);
    }

    #[test]
    fn test_latest_milestone_complete() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());

        let index = json!({
            "phases_total": 2,
            "phases_complete": 2,
            "milestones": ["Done Milestone"],
            "phases": [
                {"num": 1, "slug": "a", "plans": 1, "status": "complete"},
                {"num": 2, "slug": "b", "plans": 1, "status": "complete"},
            ],
        });
        fs::write(
            archive.join("INDEX.json"),
            serde_json::to_string(&index).unwrap(),
        )
        .unwrap();

        let result = infer_summary(&archive).unwrap();
        assert_eq!(result["latest_milestone"]["status"], "complete");
    }

    #[test]
    fn test_recent_phases() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        write_index(&archive, 3, 2);

        let result = infer_summary(&archive).unwrap();
        let recent = result["recent_phases"].as_array().unwrap();
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0]["name"], "1-setup");
        assert_eq!(recent[1]["name"], "2-feature");
    }

    #[test]
    fn test_key_decisions() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        write_state(&archive);

        let result = infer_summary(&archive).unwrap();
        let decisions = result["key_decisions"].as_array().unwrap();
        assert_eq!(decisions.len(), 2);
        assert_eq!(decisions[0], "Use Rust");
        assert_eq!(decisions[1], "Skip QA");
    }

    #[test]
    fn test_key_decisions_bullet_format() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        fs::write(
            archive.join("STATE.md"),
            "# State\n\n## Decisions\n\n- Chose React\n- Dropped Vue\n\n## Other\n",
        )
        .unwrap();

        let result = infer_summary(&archive).unwrap();
        let decisions = result["key_decisions"].as_array().unwrap();
        assert_eq!(decisions.len(), 2);
        assert_eq!(decisions[0], "Chose React");
    }

    #[test]
    fn test_current_work_from_index() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());
        write_index(&archive, 3, 2);

        let result = infer_summary(&archive).unwrap();
        let current = &result["current_work"];
        assert_eq!(current["phase"], "3-polish");
        assert_eq!(current["status"], "in_progress");
    }

    #[test]
    fn test_current_work_from_state_fallback() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());

        // INDEX with all phases complete
        let index = json!({
            "phases_total": 1,
            "phases_complete": 1,
            "milestones": [],
            "phases": [{"num": 1, "slug": "done", "plans": 1, "status": "complete"}],
        });
        fs::write(
            archive.join("INDEX.json"),
            serde_json::to_string(&index).unwrap(),
        )
        .unwrap();

        // STATE.md with current phase
        fs::write(
            archive.join("STATE.md"),
            "**Current Phase:** Phase 2 - Extensions\n**Status:** active\n",
        )
        .unwrap();

        let result = infer_summary(&archive).unwrap();
        let current = &result["current_work"];
        assert_eq!(current["phase"], "Phase 2 - Extensions");
        assert_eq!(current["status"], "active");
    }

    #[test]
    fn test_execute_cli_default_path() {
        let dir = TempDir::new().unwrap();
        let archive = dir.path().join(".yolo-planning/gsd-archive");
        fs::create_dir_all(&archive).unwrap();

        let args: Vec<String> = vec!["yolo".into(), "gsd-summary".into()];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("latest_milestone"));
    }

    #[test]
    fn test_execute_cli_custom_path() {
        let dir = TempDir::new().unwrap();
        let archive = dir.path().join("custom-archive");
        fs::create_dir_all(&archive).unwrap();

        let args: Vec<String> = vec![
            "yolo".into(),
            "gsd-summary".into(),
            archive.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("latest_milestone"));
    }

    #[test]
    fn test_roadmap_table_parsing() {
        let dir = TempDir::new().unwrap();
        let archive = setup_archive(dir.path());

        // Write INDEX with completed phases
        let index = json!({
            "phases_total": 2,
            "phases_complete": 2,
            "milestones": [],
            "phases": [
                {"num": 1, "slug": "a", "plans": 3, "status": "complete"},
                {"num": 2, "slug": "b", "plans": 5, "status": "complete"},
            ],
        });
        fs::write(
            archive.join("INDEX.json"),
            serde_json::to_string(&index).unwrap(),
        )
        .unwrap();

        // Write ROADMAP.md with progress table
        fs::write(
            archive.join("ROADMAP.md"),
            "# Progress\n\n| Phase | Status | Plans | Tasks | Commits |\n|-------|--------|-------|-------|--------|\n| 1 | done | 3 | 10 | 5 |\n| 2 | done | 5 | 20 | 8 |\n",
        )
        .unwrap();

        let result = infer_summary(&archive).unwrap();
        let recent = result["recent_phases"].as_array().unwrap();
        assert_eq!(recent[0]["tasks"], 10);
        assert_eq!(recent[0]["commits"], 5);
        assert_eq!(recent[1]["tasks"], 20);
        assert_eq!(recent[1]["commits"], 8);
    }
}
