use std::fs;
use std::path::Path;

/// CLI entry: `yolo persist-state <archived_state_path> <output_path> <project_name>`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo persist-state <archived_state_path> <output_path> <project_name>".to_string());
    }

    let archived_path = cwd.join(&args[0]);
    let output_path = cwd.join(&args[1]);
    let project_name = &args[2];

    if !archived_path.is_file() {
        return Err(format!(
            "ERROR: Archived STATE.md not found: {}",
            archived_path.display()
        ));
    }

    if let Some(parent) = output_path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let content = fs::read_to_string(&archived_path)
        .map_err(|e| format!("Failed to read archived state: {}", e))?;

    let output = generate_root_state(&content, project_name);

    fs::write(&output_path, &output)
        .map_err(|e| format!("Failed to write output: {}", e))?;

    Ok((output_path.to_string_lossy().to_string(), 0))
}

fn generate_root_state(archived_content: &str, project_name: &str) -> String {
    let mut out = String::new();
    out.push_str("# State\n\n");
    out.push_str(&format!("**Project:** {}\n\n", project_name));

    // Decisions (including Skills subsection) — matches "## Decisions" or "## Key Decisions"
    let decisions = extract_decisions_with_skills(archived_content);
    if section_has_body(&decisions) {
        out.push_str(&decisions);
        out.push('\n');
    } else {
        out.push_str("## Decisions\n- _(No decisions yet)_\n\n");
    }

    // Todos
    let todos = extract_section(archived_content, "todos");
    if section_has_body(&todos) {
        out.push_str(&todos);
        out.push('\n');
    } else {
        out.push_str("## Todos\nNone.\n\n");
    }

    // Blockers
    let blockers = extract_section(archived_content, "blockers");
    if section_has_body(&blockers) {
        out.push_str(&blockers);
        out.push('\n');
    } else {
        out.push_str("## Blockers\nNone\n\n");
    }

    // Codebase Profile (optional)
    let codebase = extract_section(archived_content, "codebase profile");
    if section_has_body(&codebase) {
        out.push_str(&codebase);
        out.push('\n');
    }

    out
}

/// Extract a section by heading (case-insensitive), merging duplicate headings.
fn extract_section(content: &str, heading: &str) -> String {
    let heading_lower = heading.to_lowercase();
    let mut result = String::new();
    let mut found = false;
    let mut header_written = false;

    for line in content.lines() {
        let line_lower = line.to_lowercase();
        let trimmed = line_lower.trim();

        // Check if this is our target heading (## Heading)
        if trimmed.starts_with("## ") {
            let h = trimmed.trim_start_matches("## ").trim();
            if h == heading_lower {
                found = true;
                if !header_written {
                    result.push_str(line);
                    result.push('\n');
                    header_written = true;
                }
                continue;
            } else if found {
                found = false;
            }
        }

        if found {
            result.push_str(line);
            result.push('\n');
        }
    }

    result
}

/// Extract "## Decisions" or "## Key Decisions" sections, merging all occurrences.
fn extract_decisions_with_skills(content: &str) -> String {
    let mut result = String::new();
    let mut found = false;
    let mut header_written = false;

    for line in content.lines() {
        let line_lower = line.to_lowercase();
        let trimmed = line_lower.trim();

        if trimmed.starts_with("## ") {
            let h = trimmed.trim_start_matches("## ").trim();
            if h == "decisions" || h == "key decisions" {
                found = true;
                if !header_written {
                    result.push_str(line);
                    result.push('\n');
                    header_written = true;
                }
                continue;
            } else if found {
                found = false;
            }
        }

        if found {
            result.push_str(line);
            result.push('\n');
        }
    }

    result
}

/// Check if extracted section has content beyond just the heading line.
fn section_has_body(section: &str) -> bool {
    if section.is_empty() {
        return false;
    }
    // Skip first line (heading) and check if there's non-whitespace content
    section
        .lines()
        .skip(1)
        .any(|line| !line.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_extract_section_basic() {
        let content = "# State\n\n## Todos\n- Fix bug\n- Add feature\n\n## Blockers\nNone\n";
        let todos = extract_section(content, "todos");
        assert!(todos.contains("## Todos"));
        assert!(todos.contains("Fix bug"));
        assert!(!todos.contains("Blockers"));
    }

    #[test]
    fn test_extract_section_case_insensitive() {
        let content = "## TODOS\n- Item 1\n\n## Other\nstuff\n";
        let todos = extract_section(content, "todos");
        assert!(todos.contains("Item 1"));
    }

    #[test]
    fn test_extract_decisions_with_skills() {
        let content = "## Key Decisions\n- Use Rust\n### Skills\n- /deploy\n\n## Blockers\nNone\n";
        let decisions = extract_decisions_with_skills(content);
        assert!(decisions.contains("Key Decisions"));
        assert!(decisions.contains("Use Rust"));
        assert!(decisions.contains("### Skills"));
        assert!(decisions.contains("/deploy"));
        assert!(!decisions.contains("Blockers"));
    }

    #[test]
    fn test_extract_decisions_plain_heading() {
        let content = "## Decisions\n- Choice A\n\n## Other\nstuff\n";
        let decisions = extract_decisions_with_skills(content);
        assert!(decisions.contains("Decisions"));
        assert!(decisions.contains("Choice A"));
    }

    #[test]
    fn test_section_has_body() {
        assert!(!section_has_body(""));
        assert!(!section_has_body("## Heading\n"));
        assert!(!section_has_body("## Heading\n   \n"));
        assert!(section_has_body("## Heading\nContent here\n"));
    }

    #[test]
    fn test_generate_root_state_full() {
        let archived = "\
# State

**Project:** Test

## Key Decisions
- Use Rust for performance
### Skills
- /commit

## Todos
- Write docs
- Add tests

## Blockers
- CI flaky

## Codebase Profile
- Language: Rust

## Current Phase
Phase 3
";
        let output = generate_root_state(archived, "MyProject");
        assert!(output.contains("**Project:** MyProject"));
        assert!(output.contains("## Key Decisions"));
        assert!(output.contains("Use Rust"));
        assert!(output.contains("### Skills"));
        assert!(output.contains("## Todos"));
        assert!(output.contains("Write docs"));
        assert!(output.contains("## Blockers"));
        assert!(output.contains("CI flaky"));
        assert!(output.contains("## Codebase Profile"));
        // Should NOT include milestone-specific sections
        assert!(!output.contains("Current Phase"));
    }

    #[test]
    fn test_generate_root_state_empty_sections() {
        let archived = "# State\n\n## Current Phase\nPhase 1\n";
        let output = generate_root_state(archived, "TestProj");
        assert!(output.contains("**Project:** TestProj"));
        assert!(output.contains("## Decisions"));
        assert!(output.contains("_(No decisions yet)_"));
        assert!(output.contains("## Todos"));
        assert!(output.contains("None."));
        assert!(output.contains("## Blockers"));
        assert!(output.contains("None"));
    }

    #[test]
    fn test_execute_integration() {
        let dir = TempDir::new().unwrap();
        let archived = dir.path().join("archived-STATE.md");
        fs::write(
            &archived,
            "# State\n\n## Decisions\n- Use Rust\n\n## Todos\n- Deploy\n",
        )
        .unwrap();

        let output_path = dir.path().join("STATE.md");
        let args: Vec<String> = vec![
            archived.to_string_lossy().to_string(),
            output_path.to_string_lossy().to_string(),
            "TestProject".into(),
        ];

        // Use root "/" as cwd since paths are absolute
        let (out, code) = execute(&args, Path::new("/")).unwrap();
        assert_eq!(code, 0);
        assert!(!out.is_empty());

        let content = fs::read_to_string(&output_path).unwrap();
        assert!(content.contains("**Project:** TestProject"));
        assert!(content.contains("Use Rust"));
        assert!(content.contains("Deploy"));
    }

    #[test]
    fn test_execute_missing_file() {
        let result = execute(
            &["nonexistent.md".into(), "out.md".into(), "Proj".into()],
            Path::new("/tmp"),
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_execute_missing_args() {
        let result = execute(&["one.md".into()], Path::new("/tmp"));
        assert!(result.is_err());
    }
}
