use std::fs;
use std::path::Path;
use std::time::Instant;

fn slugify(name: &str) -> String {
    let lower = name.to_lowercase();
    let slug: String = lower.chars().map(|c| {
        if c.is_ascii_alphanumeric() { c } else { '-' }
    }).collect();
    // Collapse multiple hyphens, trim leading/trailing
    let mut result = String::new();
    let mut prev_dash = true; // treat start as dash to trim leading
    for c in slug.chars() {
        if c == '-' {
            if !prev_dash {
                result.push('-');
            }
            prev_dash = true;
        } else {
            result.push(c);
            prev_dash = false;
        }
    }
    // Trim trailing dash
    if result.ends_with('-') {
        result.pop();
    }
    result
}

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    // args: ["roadmap", OUTPUT_PATH, PROJECT_NAME, PHASES_JSON]
    if args.len() < 4 {
        let response = serde_json::json!({
            "ok": false,
            "cmd": "bootstrap-roadmap",
            "error": "Usage: yolo bootstrap roadmap <output_path> <project_name> <phases_json>",
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let output_path = Path::new(&args[1]);
    let project_name = &args[2];
    let phases_path = Path::new(&args[3]);

    if !phases_path.exists() {
        return Err(format!("Error: Phases file not found: {}", phases_path.display()));
    }

    let phases_content = fs::read_to_string(phases_path)
        .map_err(|e| format!("Failed to read phases: {}", e))?;
    let phases: serde_json::Value = serde_json::from_str(&phases_content)
        .map_err(|_| format!("Error: Invalid JSON in {}", phases_path.display()))?;

    let phases_arr = phases.as_array()
        .ok_or_else(|| "Error: Phases JSON must be an array".to_string())?;

    if phases_arr.is_empty() {
        return Err(format!("Error: No phases defined in {}", phases_path.display()));
    }

    let phase_count = phases_arr.len();

    // Ensure parent directory exists
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
    }

    // Derive phases directory
    let planning_dir = output_path.parent().unwrap_or(Path::new("."));
    let phases_dir = planning_dir.join("phases");

    let mut out = String::new();

    // Header
    out.push_str(&format!("# {} Roadmap\n\n", project_name));
    out.push_str(&format!("**Goal:** {}\n\n", project_name));
    out.push_str(&format!("**Scope:** {} phases\n\n", phase_count));

    // Progress table
    out.push_str("## Progress\n");
    out.push_str("| Phase | Status | Plans | Tasks | Commits |\n");
    out.push_str("|-------|--------|-------|-------|----------|\n");
    for i in 1..=phase_count {
        out.push_str(&format!("| {} | Pending | 0 | 0 | 0 |\n", i));
    }
    out.push_str("\n---\n\n");

    // Phase list
    out.push_str("## Phase List\n");
    for (i, phase) in phases_arr.iter().enumerate() {
        let num = i + 1;
        let name = phase.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let slug = slugify(name);
        out.push_str(&format!("- [ ] [Phase {}: {}](#phase-{}-{})\n", num, name, num, slug));
    }
    out.push_str("\n---\n\n");

    // Phase details
    for (i, phase) in phases_arr.iter().enumerate() {
        let num = i + 1;
        let name = phase.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let goal = phase.get("goal").and_then(|v| v.as_str()).unwrap_or("");
        let reqs = phase.get("requirements")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(", "))
            .unwrap_or_default();
        let criteria = phase.get("success_criteria")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        out.push_str(&format!("## Phase {}: {}\n\n", num, name));
        out.push_str(&format!("**Goal:** {}\n\n", goal));

        if !reqs.is_empty() {
            out.push_str(&format!("**Requirements:** {}\n\n", reqs));
        }

        out.push_str("**Success Criteria:**\n");
        for criterion in &criteria {
            if let Some(s) = criterion.as_str() {
                out.push_str(&format!("- {}\n", s));
            }
        }
        out.push('\n');

        if num == 1 {
            out.push_str("**Dependencies:** None\n");
        } else {
            out.push_str(&format!("**Dependencies:** Phase {}\n", num - 1));
        }
        out.push('\n');

        if i < phase_count - 1 {
            out.push_str("---\n\n");
        }
    }

    fs::write(output_path, &out)
        .map_err(|e| format!("Failed to write {}: {}", output_path.display(), e))?;

    // Create phase directories and collect changed paths
    let mut changed: Vec<String> = vec![output_path.to_string_lossy().to_string()];
    let mut phase_dir_names: Vec<String> = Vec::new();
    for (i, phase) in phases_arr.iter().enumerate() {
        let num = format!("{:02}", i + 1);
        let name = phase.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let slug = slugify(name);
        let dir_name = format!("{}-{}", num, slug);
        let dir = phases_dir.join(&dir_name);
        fs::create_dir_all(&dir)
            .map_err(|e| format!("Failed to create phase dir: {}", e))?;
        phase_dir_names.push(dir_name);
        changed.push(dir.to_string_lossy().to_string());
    }

    let response = serde_json::json!({
        "ok": true,
        "cmd": "bootstrap-roadmap",
        "changed": changed,
        "delta": {
            "project_name": project_name,
            "phase_count": phase_count,
            "phase_dirs_created": phase_dir_names
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });
    Ok((response.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn write_phases(dir: &Path, content: &str) -> String {
        let path = dir.join("phases.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_single_phase() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("ROADMAP.md");
        let phases = write_phases(dir.path(), r#"[
            {"name": "Core Setup", "goal": "Set up basics", "requirements": ["REQ-01"], "success_criteria": ["Tests pass"]}
        ]"#);

        let (out, code) = execute(
            &["roadmap".into(), output.to_string_lossy().to_string(), "MyApp".into(), phases],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["cmd"], "bootstrap-roadmap");
        assert_eq!(json["delta"]["phase_count"], 1);
        assert_eq!(json["delta"]["project_name"], "MyApp");
        assert_eq!(json["delta"]["phase_dirs_created"].as_array().unwrap().len(), 1);
        assert!(json["changed"].as_array().unwrap().len() >= 2);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("# MyApp Roadmap"));
        assert!(content.contains("**Scope:** 1 phases"));
        assert!(content.contains("## Phase 1: Core Setup"));
        assert!(content.contains("**Dependencies:** None"));
    }

    #[test]
    fn test_multiple_phases() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("plan").join("ROADMAP.md");
        let phases = write_phases(dir.path(), r#"[
            {"name": "Foundation", "goal": "Build base", "requirements": [], "success_criteria": ["Compiles"]},
            {"name": "Features", "goal": "Add features", "requirements": ["REQ-01"], "success_criteria": ["All tests pass", "Docs updated"]}
        ]"#);

        let (out, _) = execute(
            &["roadmap".into(), output.to_string_lossy().to_string(), "TestProj".into(), phases],
            dir.path(),
        ).unwrap();

        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["delta"]["phase_count"], 2);
        let phase_dirs = json["delta"]["phase_dirs_created"].as_array().unwrap();
        assert_eq!(phase_dirs.len(), 2);
        assert_eq!(phase_dirs[0], "01-foundation");
        assert_eq!(phase_dirs[1], "02-features");

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("**Scope:** 2 phases"));
        assert!(content.contains("## Phase 1: Foundation"));
        assert!(content.contains("## Phase 2: Features"));
        assert!(content.contains("**Dependencies:** Phase 1"));

        // Check phase dirs created
        let phases_dir = dir.path().join("plan").join("phases");
        assert!(phases_dir.join("01-foundation").exists());
        assert!(phases_dir.join("02-features").exists());
    }

    #[test]
    fn test_slug_generation() {
        assert_eq!(slugify("Core CLI Commands"), "core-cli-commands");
        assert_eq!(slugify("Phase 1: Setup"), "phase-1-setup");
        assert_eq!(slugify("  Leading Spaces  "), "leading-spaces");
        assert_eq!(slugify("special!!chars##here"), "special-chars-here");
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let (out, code) = execute(
            &["roadmap".into(), "/tmp/out.md".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 1);
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["ok"], false);
        assert_eq!(json["cmd"], "bootstrap-roadmap");
        assert!(json["error"].as_str().unwrap().contains("Usage:"));
    }

    #[test]
    fn test_empty_phases_error() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("ROADMAP.md");
        let phases = write_phases(dir.path(), "[]");

        let result = execute(
            &["roadmap".into(), output.to_string_lossy().to_string(), "MyApp".into(), phases],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("No phases defined"));
    }

    #[test]
    fn test_missing_phases_file() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["roadmap".into(), "/tmp/out.md".into(), "MyApp".into(), "/nonexistent/phases.json".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    #[test]
    fn test_progress_table_rows() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("ROADMAP.md");
        let phases = write_phases(dir.path(), r#"[
            {"name": "A", "goal": "G1", "requirements": [], "success_criteria": []},
            {"name": "B", "goal": "G2", "requirements": [], "success_criteria": []},
            {"name": "C", "goal": "G3", "requirements": [], "success_criteria": []}
        ]"#);

        let (out, _) = execute(
            &["roadmap".into(), output.to_string_lossy().to_string(), "Test".into(), phases],
            dir.path(),
        ).unwrap();

        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["delta"]["phase_count"], 3);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("| 1 | Pending | 0 | 0 | 0 |"));
        assert!(content.contains("| 2 | Pending | 0 | 0 | 0 |"));
        assert!(content.contains("| 3 | Pending | 0 | 0 | 0 |"));
    }
}
