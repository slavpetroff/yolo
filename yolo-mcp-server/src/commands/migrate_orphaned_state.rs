use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

/// Recover root STATE.md for brownfield installations that shipped a milestone
/// before this fix was deployed.
///
/// Detects:
///   - planning_dir exists
///   - No root STATE.md
///   - No ACTIVE file (milestone is fully shipped)
///   - At least one milestones/*/STATE.md exists
///
/// When detected, reconstructs a root STATE.md from the latest archived STATE.md.
/// Idempotent: no-ops if root STATE.md already exists or ACTIVE is set.
pub fn migrate_orphaned_state(planning_dir: &Path) -> Result<bool, String> {
    if !planning_dir.is_dir() {
        return Ok(false);
    }
    if planning_dir.join("STATE.md").exists() {
        return Ok(false);
    }
    if planning_dir.join("ACTIVE").exists() {
        return Ok(false);
    }

    // Find the latest archived STATE.md by modification time
    let milestones_dir = planning_dir.join("milestones");
    if !milestones_dir.is_dir() {
        return Ok(false);
    }

    let latest_state = find_latest_state(&milestones_dir)?;
    let latest_state = match latest_state {
        Some(p) => p,
        None => return Ok(false),
    };

    let archived_content = fs::read_to_string(&latest_state)
        .map_err(|e| format!("Failed to read archived state: {e}"))?;

    // Extract project name
    let project_name = archived_content
        .lines()
        .find(|line| line.starts_with("**Project:**"))
        .map(|line| line.replace("**Project:**", "").trim().to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    // Generate root STATE.md
    let root_state = generate_root_state(&archived_content, &project_name);
    let output_path = planning_dir.join("STATE.md");

    fs::write(&output_path, root_state)
        .map_err(|e| format!("Failed to write root STATE.md: {e}"))?;

    Ok(true)
}

fn find_latest_state(milestones_dir: &Path) -> Result<Option<std::path::PathBuf>, String> {
    let entries = fs::read_dir(milestones_dir)
        .map_err(|e| format!("Failed to read milestones dir: {e}"))?;

    let mut latest_path = None;
    let mut latest_mtime = 0u64;

    for entry in entries.flatten() {
        let state_path = entry.path().join("STATE.md");
        if !state_path.exists() {
            continue;
        }
        let mtime = fs::metadata(&state_path)
            .and_then(|m| m.modified())
            .map(|t| t.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs())
            .unwrap_or(0);
        if mtime > latest_mtime {
            latest_mtime = mtime;
            latest_path = Some(state_path);
        }
    }

    Ok(latest_path)
}

fn generate_root_state(archived: &str, project_name: &str) -> String {
    let mut output = String::new();
    output.push_str("# State\n\n");
    output.push_str(&format!("**Project:** {project_name}\n\n"));

    // Decisions (including Skills subsection)
    let decisions = extract_decisions_with_skills(archived);
    if section_has_body(&decisions) {
        output.push_str(&decisions);
        output.push('\n');
    } else {
        output.push_str("## Decisions\n- _(No decisions yet)_\n\n");
    }

    // Todos
    let todos = extract_section(archived, "todos");
    if section_has_body(&todos) {
        output.push_str(&todos);
        output.push('\n');
    } else {
        output.push_str("## Todos\nNone.\n\n");
    }

    // Blockers
    let blockers = extract_section(archived, "blockers");
    if section_has_body(&blockers) {
        output.push_str(&blockers);
        output.push('\n');
    } else {
        output.push_str("## Blockers\nNone\n\n");
    }

    // Codebase Profile (optional)
    let codebase = extract_section(archived, "codebase profile");
    if section_has_body(&codebase) {
        output.push_str(&codebase);
        output.push('\n');
    }

    output
}

/// Extract a ## section by heading (case-insensitive), stopping at the next ## heading.
fn extract_section(content: &str, heading: &str) -> String {
    let heading_lower = heading.to_lowercase();
    let mut result = String::new();
    let mut in_section = false;
    let mut header_printed = false;

    for line in content.lines() {
        let line_lower = line.to_lowercase();
        let trimmed = line_lower.trim();

        if let Some(rest) = trimmed.strip_prefix("## ") {
            let section_name = rest.trim();
            if section_name == heading_lower {
                in_section = true;
                if !header_printed {
                    result.push_str(line);
                    result.push('\n');
                    header_printed = true;
                }
                continue;
            } else if in_section {
                in_section = false;
            }
        }

        if in_section {
            result.push_str(line);
            result.push('\n');
        }
    }

    result
}

/// Extract Decisions section (matches both "## Decisions" and "## Key Decisions").
fn extract_decisions_with_skills(content: &str) -> String {
    let mut result = String::new();
    let mut in_section = false;
    let mut header_printed = false;

    for line in content.lines() {
        let line_lower = line.to_lowercase();
        let trimmed = line_lower.trim();

        if let Some(rest) = trimmed.strip_prefix("## ") {
            let section_name = rest.trim();
            if section_name == "decisions" || section_name == "key decisions" {
                in_section = true;
                if !header_printed {
                    result.push_str(line);
                    result.push('\n');
                    header_printed = true;
                }
                continue;
            } else if in_section {
                in_section = false;
            }
        }

        if in_section {
            result.push_str(line);
            result.push('\n');
        }
    }

    result
}

/// Check if extracted section has content beyond just whitespace.
fn section_has_body(section: &str) -> bool {
    if section.is_empty() {
        return false;
    }
    // Skip the first line (heading) and check if remaining has non-whitespace
    section
        .lines()
        .skip(1)
        .any(|line| !line.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_no_planning_dir() {
        let dir = tempdir().unwrap();
        assert!(!migrate_orphaned_state(&dir.path().join("nonexistent")).unwrap());
    }

    #[test]
    fn test_state_already_exists() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        fs::create_dir(&pd).unwrap();
        fs::write(pd.join("STATE.md"), "existing").unwrap();
        assert!(!migrate_orphaned_state(&pd).unwrap());
    }

    #[test]
    fn test_active_file_exists() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        fs::create_dir(&pd).unwrap();
        fs::write(pd.join("ACTIVE"), "some-milestone").unwrap();
        assert!(!migrate_orphaned_state(&pd).unwrap());
    }

    #[test]
    fn test_no_milestones() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        fs::create_dir(&pd).unwrap();
        assert!(!migrate_orphaned_state(&pd).unwrap());
    }

    #[test]
    fn test_reconstruct_from_archived() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        let ms = pd.join("milestones").join("v1-launch");
        fs::create_dir_all(&ms).unwrap();

        let archived = "\
# State

**Project:** My App

## Decisions
- Use Rust for backend

### Skills
- /deploy

## Todos
- Fix bug #42

## Blockers
None

## Current Phase
Phase 1 of 3 (Setup)

## Activity Log
- Did stuff
";
        fs::write(ms.join("STATE.md"), archived).unwrap();

        assert!(migrate_orphaned_state(&pd).unwrap());

        let result = fs::read_to_string(pd.join("STATE.md")).unwrap();
        assert!(result.contains("**Project:** My App"));
        assert!(result.contains("## Decisions"));
        assert!(result.contains("Use Rust for backend"));
        assert!(result.contains("### Skills"));
        assert!(result.contains("## Todos"));
        assert!(result.contains("Fix bug #42"));
        assert!(result.contains("## Blockers"));
        // Should NOT contain milestone-specific sections
        assert!(!result.contains("## Current Phase"));
        assert!(!result.contains("## Activity Log"));
    }

    #[test]
    fn test_empty_sections_get_defaults() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        let ms = pd.join("milestones").join("v1");
        fs::create_dir_all(&ms).unwrap();

        let archived = "# State\n\n**Project:** Minimal\n";
        fs::write(ms.join("STATE.md"), archived).unwrap();

        assert!(migrate_orphaned_state(&pd).unwrap());

        let result = fs::read_to_string(pd.join("STATE.md")).unwrap();
        assert!(result.contains("_(No decisions yet)_"));
        assert!(result.contains("## Todos\nNone.\n"));
        assert!(result.contains("## Blockers\nNone\n"));
    }

    #[test]
    fn test_extract_section_case_insensitive() {
        let content = "## TODOS\n- item 1\n- item 2\n## Other\nstuff\n";
        let result = extract_section(content, "todos");
        assert!(result.contains("## TODOS"));
        assert!(result.contains("- item 1"));
        assert!(!result.contains("## Other"));
    }

    #[test]
    fn test_extract_decisions_matches_key_decisions() {
        let content = "## Key Decisions\n- Decision A\n## Other\n";
        let result = extract_decisions_with_skills(content);
        assert!(result.contains("## Key Decisions"));
        assert!(result.contains("Decision A"));
    }

    #[test]
    fn test_section_has_body() {
        assert!(!section_has_body(""));
        assert!(!section_has_body("## Heading\n"));
        assert!(!section_has_body("## Heading\n  \n"));
        assert!(section_has_body("## Heading\ncontent\n"));
    }

    #[test]
    fn test_idempotent() {
        let dir = tempdir().unwrap();
        let pd = dir.path().join("planning");
        let ms = pd.join("milestones").join("v1");
        fs::create_dir_all(&ms).unwrap();
        fs::write(ms.join("STATE.md"), "# State\n\n**Project:** Test\n").unwrap();

        // First call creates STATE.md
        assert!(migrate_orphaned_state(&pd).unwrap());
        // Second call is no-op (STATE.md exists)
        assert!(!migrate_orphaned_state(&pd).unwrap());
    }
}
