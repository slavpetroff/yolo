use std::fs;
use std::path::Path;
use std::time::Instant;
use chrono::Local;

/// Extract a section's body from existing STATE.md content.
/// Matches `## {heading}` (case-insensitive) and captures until next `## `.
fn extract_section(content: &str, headings: &[&str]) -> String {
    let lines: Vec<&str> = content.lines().collect();
    let mut found = false;
    let mut body = Vec::new();

    for line in &lines {
        let lower = line.to_lowercase();
        let trimmed = lower.trim();

        if headings.iter().any(|h| trimmed == h.to_lowercase()) {
            found = true;
            continue;
        }

        if found && trimmed.starts_with("## ") {
            break;
        }

        if found {
            body.push(*line);
        }
    }

    let result = body.join("\n");
    result.trim().to_string()
}

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    // args: ["state", OUTPUT_PATH, PROJECT_NAME, MILESTONE_NAME, PHASE_COUNT]
    if args.len() < 5 {
        let response = serde_json::json!({
            "ok": false,
            "cmd": "bootstrap-state",
            "error": "Usage: yolo bootstrap state <output_path> <project_name> <milestone_name> <phase_count>",
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let output_path = Path::new(&args[1]);
    let project_name = &args[2];
    let milestone_name = &args[3];
    let phase_count: usize = args[4].parse()
        .map_err(|_| format!("Invalid phase count: {}", args[4]))?;

    let started = Local::now().format("%Y-%m-%d").to_string();

    // Ensure parent directory exists
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
    }

    // Preserve existing sections if file exists
    let existing_content = if output_path.exists() {
        fs::read_to_string(output_path).unwrap_or_default()
    } else {
        String::new()
    };

    let existing_todos = extract_section(&existing_content, &["## Todos"]);
    let existing_decisions = extract_section(&existing_content, &["## Key Decisions", "## Decisions"]);

    let mut out = String::new();

    out.push_str("# YOLO State\n\n");
    out.push_str(&format!("**Project:** {}\n", project_name));
    out.push_str(&format!("**Milestone:** {}\n", milestone_name));
    out.push_str("**Current Phase:** Phase 1\n");
    out.push_str("**Status:** Pending planning\n");
    out.push_str(&format!("**Started:** {}\n", started));
    out.push_str("**Progress:** 0%\n\n");
    out.push_str("## Phase Status\n");

    for i in 1..=phase_count {
        if i == 1 {
            out.push_str(&format!("- **Phase {}:** Pending planning\n", i));
        } else {
            out.push_str(&format!("- **Phase {}:** Pending\n", i));
        }
    }

    out.push_str("\n## Key Decisions\n");
    if !existing_decisions.is_empty() {
        out.push_str(&existing_decisions);
        out.push('\n');
    } else {
        out.push_str("| Decision | Date | Rationale |\n");
        out.push_str("|----------|------|-----------|\n");
        out.push_str("| _(No decisions yet)_ | | |\n");
    }

    out.push_str("\n## Todos\n");
    if !existing_todos.is_empty() {
        out.push_str(&existing_todos);
        out.push('\n');
    } else {
        out.push_str("None.\n");
    }

    out.push_str(&format!("\n## Recent Activity\n- {}: Created {} milestone ({} phases)", started, milestone_name, phase_count));

    fs::write(output_path, &out)
        .map_err(|e| format!("Failed to write {}: {}", output_path.display(), e))?;

    let response = serde_json::json!({
        "ok": true,
        "cmd": "bootstrap-state",
        "changed": [output_path.to_string_lossy()],
        "delta": {
            "project_name": project_name,
            "milestone_name": milestone_name,
            "phase_count": phase_count,
            "preserved_todos": !existing_todos.is_empty(),
            "preserved_decisions": !existing_decisions.is_empty()
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });
    Ok((response.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_fresh_generation() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("STATE.md");

        let (_, code) = execute(
            &["state".into(), output.to_string_lossy().to_string(), "MyApp".into(), "Initial Release".into(), "3".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("# YOLO State"));
        assert!(content.contains("**Project:** MyApp"));
        assert!(content.contains("**Milestone:** Initial Release"));
        assert!(content.contains("- **Phase 1:** Pending planning"));
        assert!(content.contains("- **Phase 2:** Pending"));
        assert!(content.contains("- **Phase 3:** Pending"));
        assert!(content.contains("None."));
        assert!(content.contains("_(No decisions yet)_"));
    }

    #[test]
    fn test_preserve_existing_todos() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("STATE.md");

        // Write initial state with todos
        fs::write(&output, "# YOLO State\n\n## Todos\n- [ ] Fix bug #42\n- [x] Review PR\n\n## Key Decisions\n| D | R |\n").unwrap();

        execute(
            &["state".into(), output.to_string_lossy().to_string(), "MyApp".into(), "v2".into(), "2".into()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("- [ ] Fix bug #42"));
        assert!(content.contains("- [x] Review PR"));
    }

    #[test]
    fn test_preserve_existing_decisions() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("STATE.md");

        fs::write(&output, "# YOLO State\n\n## Key Decisions\n| Decision | Date | Rationale |\n|---|---|---|\n| Use Rust | 2026-01-01 | Performance |\n\n## Todos\nNone.\n").unwrap();

        execute(
            &["state".into(), output.to_string_lossy().to_string(), "MyApp".into(), "v2".into(), "1".into()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("Use Rust"));
        assert!(content.contains("Performance"));
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["state".into(), "/tmp/test.md".into(), "MyApp".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_recent_activity() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("STATE.md");

        execute(
            &["state".into(), output.to_string_lossy().to_string(), "MyApp".into(), "Beta".into(), "2".into()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("Created Beta milestone (2 phases)"));
    }

    #[test]
    fn test_extract_section() {
        let content = "# Title\n\n## Todos\n- Item 1\n- Item 2\n\n## Other\nStuff\n";
        let result = extract_section(content, &["## Todos"]);
        assert_eq!(result, "- Item 1\n- Item 2");
    }
}
