use std::fs;
use std::path::Path;

const LINE_CAP: usize = 200;

/// CLI entry: `yolo rolling-summary [phases-dir] [output-path]`
/// Compile completed SUMMARY.md files into a condensed rolling digest.
/// 200-line cap. Fail-open: exits 0 on any error.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let phases_dir = if !args.is_empty() && !args[0].is_empty() {
        cwd.join(&args[0])
    } else {
        cwd.join(".yolo-planning/phases")
    };

    let output_path = if args.len() > 1 && !args[1].is_empty() {
        cwd.join(&args[1])
    } else {
        cwd.join(".yolo-planning/ROLLING-CONTEXT.md")
    };

    // Discover all SUMMARY.md files
    let (completed_files, total_count) = discover_summaries(&phases_dir);

    // Single-phase no-op: if only one total summary, no prior context to roll up
    if total_count <= 1 {
        let content = "# Rolling Context\nNo prior completed phases.\n";
        write_output(&output_path, content)?;
        return Ok((output_path.to_string_lossy().to_string(), 0));
    }

    // Zero completed
    if completed_files.is_empty() {
        let content = "# Rolling Context\nNo prior completed phases.\n";
        write_output(&output_path, content)?;
        return Ok((output_path.to_string_lossy().to_string(), 0));
    }

    // Extract and compile entries
    let mut entries = Vec::new();
    for summary_file in &completed_files {
        if let Some(entry) = extract_entry(summary_file) {
            entries.push(entry);
        }
    }

    let accepted_count = entries.len();

    // Assemble output with 200-line cap
    let mut lines = Vec::new();
    lines.push("# Rolling Context".to_string());
    lines.push(format!(
        "Compiled from {} completed phase plan(s). Cap: {} lines.",
        accepted_count, LINE_CAP
    ));
    lines.push(String::new());

    for entry in &entries {
        lines.push(entry.clone());
    }

    // Apply line cap — expand multi-line entries, then truncate
    let mut expanded: Vec<String> = Vec::new();
    for line in &lines {
        for l in line.lines() {
            expanded.push(l.to_string());
        }
    }
    expanded.truncate(LINE_CAP);

    let content = expanded.join("\n") + "\n";
    write_output(&output_path, &content)?;

    Ok((output_path.to_string_lossy().to_string(), 0))
}

/// Discover SUMMARY.md files in phases directory.
/// Returns (completed files sorted by path, total count).
fn discover_summaries(phases_dir: &Path) -> (Vec<std::path::PathBuf>, usize) {
    let mut all_summaries = Vec::new();
    let mut completed = Vec::new();

    if !phases_dir.is_dir() {
        return (completed, 0);
    }

    // Collect phase directories
    let mut phase_dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(entries) = fs::read_dir(phases_dir) {
        for entry in entries.flatten() {
            if entry.path().is_dir() {
                phase_dirs.push(entry.path());
            }
        }
    }
    phase_dirs.sort();

    // Scan each phase directory for *-SUMMARY.md
    for phase_dir in &phase_dirs {
        if let Ok(entries) = fs::read_dir(phase_dir) {
            let mut summaries: Vec<std::path::PathBuf> = entries
                .flatten()
                .filter(|e| {
                    e.file_name()
                        .to_string_lossy()
                        .ends_with("-SUMMARY.md")
                })
                .map(|e| e.path())
                .collect();
            summaries.sort();

            for summary in summaries {
                all_summaries.push(summary.clone());

                // Check frontmatter for status: complete/completed
                if let Ok(content) = fs::read_to_string(&summary) {
                    let status = extract_frontmatter_field(&content, "status");
                    if status == "complete" || status == "completed" {
                        completed.push(summary);
                    }
                }
            }
        }
    }

    (completed, all_summaries.len())
}

/// Extract a frontmatter field from YAML frontmatter (between --- delimiters).
fn extract_frontmatter_field(content: &str, field: &str) -> String {
    let mut in_frontmatter = false;
    let prefix = format!("{}:", field);

    for line in content.lines() {
        if line.trim() == "---" {
            if in_frontmatter {
                break; // end of frontmatter
            }
            in_frontmatter = true;
            continue;
        }
        if in_frontmatter && line.starts_with(&prefix) {
            return line[prefix.len()..]
                .trim()
                .trim_matches('"')
                .to_string();
        }
    }

    String::new()
}

/// Extract a condensed entry from a SUMMARY.md file.
fn extract_entry(summary_path: &Path) -> Option<String> {
    let content = fs::read_to_string(summary_path).ok()?;

    let fm_phase = extract_frontmatter_field(&content, "phase");
    let fm_plan = extract_frontmatter_field(&content, "plan");
    let fm_title = extract_frontmatter_field(&content, "title");
    let fm_deviations = extract_frontmatter_field(&content, "deviations");
    let fm_commits_raw = extract_frontmatter_field(&content, "commit_hashes");

    let phase = if fm_phase.is_empty() { "?" } else { &fm_phase };
    let plan = if fm_plan.is_empty() { "?" } else { &fm_plan };
    let title = if fm_title.is_empty() {
        "Untitled"
    } else {
        &fm_title
    };
    let deviations = if fm_deviations.is_empty() {
        "0"
    } else {
        &fm_deviations
    };

    // Parse first commit hash from comma-separated list
    let commit = fm_commits_raw
        .trim_matches(|c| c == '[' || c == ']')
        .split(',')
        .next()
        .unwrap_or("none")
        .trim()
        .trim_matches('"');
    let commit = if commit.is_empty() { "none" } else { commit };

    // Extract "## What Was Built" — first 3 non-empty lines
    let built_line = extract_section_lines(&content, "What Was Built", 3)
        .into_iter()
        .next()
        .unwrap_or_else(|| "(no details)".to_string());
    let built_line = built_line
        .trim()
        .trim_start_matches(['-', '*'])
        .trim()
        .to_string();
    let built_line = if built_line.is_empty() {
        "(no details)".to_string()
    } else {
        built_line
    };

    // Extract "## Files Modified" — lines starting with "- " (up to 5)
    let files_lines = extract_section_lines(&content, "Files Modified", 5);
    let files_list = if files_lines.is_empty() {
        "(none listed)".to_string()
    } else {
        files_lines
            .iter()
            .map(|l| l.trim().trim_start_matches("- ").to_string())
            .collect::<Vec<_>>()
            .join(",")
    };

    Some(format!(
        "## Phase {} Plan {}: {}\nBuilt: {}\nFiles: {}\nDeviations: {}\nCommit: {}",
        phase, plan, title, built_line, files_list, deviations, commit
    ))
}

/// Extract non-empty lines from a ## section (up to max_lines).
fn extract_section_lines(content: &str, heading: &str, max_lines: usize) -> Vec<String> {
    let mut found = false;
    let mut lines = Vec::new();
    let heading_lower = heading.to_lowercase();

    for line in content.lines() {
        if let Some(stripped) = line.strip_prefix("## ") {
            let h = stripped.trim().to_lowercase();
            if h == heading_lower {
                found = true;
                continue;
            } else if found {
                break;
            }
        }
        if found && !line.trim().is_empty() {
            lines.push(line.to_string());
            if lines.len() >= max_lines {
                break;
            }
        }
    }

    lines
}

fn write_output(output_path: &Path, content: &str) -> Result<(), String> {
    if let Some(parent) = output_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::write(output_path, content).map_err(|e| format!("Failed to write output: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_summary(phase: &str, plan: &str, title: &str, status: &str) -> String {
        format!(
            "---\nphase: {}\nplan: {}\ntitle: \"{}\"\nstatus: {}\ndeviations: 0\ncommit_hashes: [\"abc123\"]\n---\n\n## What Was Built\n- Implemented {} feature\n\n## Files Modified\n- src/main.rs\n- src/lib.rs\n",
            phase, plan, title, status, title
        )
    }

    fn setup_multi_phase() -> TempDir {
        let dir = TempDir::new().unwrap();
        let phases = dir.path().join(".yolo-planning/phases");

        // Phase 01 with 2 completed summaries
        let p1 = phases.join("01-setup");
        fs::create_dir_all(&p1).unwrap();
        fs::write(
            p1.join("01-01-SUMMARY.md"),
            make_summary("1", "01", "Bootstrap", "complete"),
        )
        .unwrap();
        fs::write(
            p1.join("01-02-SUMMARY.md"),
            make_summary("1", "02", "Config", "complete"),
        )
        .unwrap();

        // Phase 02 with 1 completed summary
        let p2 = phases.join("02-build");
        fs::create_dir_all(&p2).unwrap();
        fs::write(
            p2.join("02-01-SUMMARY.md"),
            make_summary("2", "01", "Core", "complete"),
        )
        .unwrap();

        dir
    }

    #[test]
    fn test_rolling_summary_multi_phase() {
        let dir = setup_multi_phase();
        let output = dir.path().join(".yolo-planning/ROLLING-CONTEXT.md");

        let args: Vec<String> = vec![];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(!out.is_empty());

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("# Rolling Context"));
        assert!(content.contains("Compiled from 3 completed"));
        assert!(content.contains("Phase 1 Plan 01: Bootstrap"));
        assert!(content.contains("Phase 2 Plan 01: Core"));
        assert!(content.contains("Built:"));
        assert!(content.contains("Files:"));
    }

    #[test]
    fn test_rolling_summary_single_phase_noop() {
        let dir = TempDir::new().unwrap();
        let phases = dir.path().join(".yolo-planning/phases/01-only");
        fs::create_dir_all(&phases).unwrap();
        fs::write(
            phases.join("01-01-SUMMARY.md"),
            make_summary("1", "01", "Only", "complete"),
        )
        .unwrap();

        let args: Vec<String> = vec![];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(dir.path().join(".yolo-planning/ROLLING-CONTEXT.md")).unwrap();
        assert!(content.contains("No prior completed phases"));
    }

    #[test]
    fn test_rolling_summary_no_completed() {
        let dir = TempDir::new().unwrap();
        let phases = dir.path().join(".yolo-planning/phases/01-wip");
        fs::create_dir_all(&phases).unwrap();
        fs::write(
            phases.join("01-01-SUMMARY.md"),
            make_summary("1", "01", "WIP1", "in_progress"),
        )
        .unwrap();
        fs::write(
            phases.join("01-02-SUMMARY.md"),
            make_summary("1", "02", "WIP2", "in_progress"),
        )
        .unwrap();

        let args: Vec<String> = vec![];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(dir.path().join(".yolo-planning/ROLLING-CONTEXT.md")).unwrap();
        assert!(content.contains("No prior completed phases"));
    }

    #[test]
    fn test_200_line_cap() {
        let dir = TempDir::new().unwrap();
        let phases = dir.path().join(".yolo-planning/phases");

        // Create enough summaries to exceed 200 lines (each entry ~5 lines + header)
        for i in 1..=50 {
            let p = phases.join(format!("{:02}-phase{}", i, i));
            fs::create_dir_all(&p).unwrap();
            fs::write(
                p.join(format!("{:02}-01-SUMMARY.md", i)),
                make_summary(&i.to_string(), "01", &format!("Phase {} work", i), "complete"),
            )
            .unwrap();
        }

        let args: Vec<String> = vec![];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(dir.path().join(".yolo-planning/ROLLING-CONTEXT.md")).unwrap();
        let line_count = content.lines().count();
        assert!(
            line_count <= LINE_CAP,
            "Expected <= {} lines, got {}",
            LINE_CAP,
            line_count
        );
    }

    #[test]
    fn test_extract_frontmatter_field() {
        let content = "---\nphase: 1\ntitle: \"Hello World\"\nstatus: complete\n---\n# Body\n";
        assert_eq!(extract_frontmatter_field(content, "phase"), "1");
        assert_eq!(extract_frontmatter_field(content, "title"), "Hello World");
        assert_eq!(extract_frontmatter_field(content, "status"), "complete");
        assert_eq!(extract_frontmatter_field(content, "missing"), "");
    }

    #[test]
    fn test_extract_section_lines() {
        let content = "## What Was Built\n- Item 1\n- Item 2\n- Item 3\n- Item 4\n\n## Other\nStuff\n";
        let lines = extract_section_lines(content, "What Was Built", 3);
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains("Item 1"));
    }

    #[test]
    fn test_custom_paths() {
        let dir = setup_multi_phase();
        let custom_output = dir.path().join("custom-output.md");

        let args: Vec<String> = vec![
            ".yolo-planning/phases".into(),
            custom_output.to_string_lossy().to_string(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        // For absolute path in arg[1], cwd.join will still work correctly
        assert!(!out.is_empty());
    }

    #[test]
    fn test_empty_phases_dir() {
        let dir = TempDir::new().unwrap();
        let args: Vec<String> = vec![];
        let (_, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(dir.path().join(".yolo-planning/ROLLING-CONTEXT.md")).unwrap();
        assert!(content.contains("No prior completed phases"));
    }
}
