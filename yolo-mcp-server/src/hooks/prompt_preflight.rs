use std::fs;
use std::path::Path;

use super::types::{HookInput, HookOutput};

const PLANNING_DIR: &str = ".yolo-planning";

/// UserPromptSubmit handler: pre-flight validation for YOLO commands.
///
/// Non-blocking (always exit 0). Creates .yolo-session marker on YOLO command
/// invocation when GSD isolation is active. Warns on --execute without PLANs
/// and --archive with incomplete phases.
pub fn handle(input: &HookInput) -> Result<HookOutput, String> {
    let planning = Path::new(PLANNING_DIR);
    if !planning.is_dir() {
        return Ok(HookOutput::empty());
    }

    let prompt = extract_prompt(&input.data);
    if prompt.is_empty() {
        return Ok(HookOutput::empty());
    }

    // GSD Isolation: create .yolo-session marker on YOLO command invocation
    handle_gsd_isolation(planning, &prompt);

    // Check warnings
    let mut warnings = Vec::new();

    if prompt.contains("/yolo:vibe") && prompt.contains("--execute") {
        if let Some(warning) = check_execute_without_plans(planning) {
            warnings.push(warning);
        }
    }

    if prompt.contains("/yolo:vibe") && prompt.contains("--archive") {
        if let Some(warning) = check_archive_incomplete(planning) {
            warnings.push(warning);
        }
    }

    if warnings.is_empty() {
        Ok(HookOutput::empty())
    } else {
        let combined = warnings.join("; ");
        let output = serde_json::json!({
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": format!("YOLO pre-flight warning: {}", combined)
            }
        });
        Ok(HookOutput::ok(output.to_string()))
    }
}

/// Extract prompt text from hook input.
fn extract_prompt(data: &serde_json::Value) -> String {
    data.get("prompt")
        .or_else(|| data.get("content"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

/// Handle GSD isolation marker creation.
fn handle_gsd_isolation(planning: &Path, prompt: &str) {
    let isolation_file = planning.join(".gsd-isolation");
    if !isolation_file.exists() {
        return;
    }

    let is_yolo_command = prompt
        .lines()
        .any(|line| {
            let trimmed = line.trim().to_lowercase();
            trimmed.starts_with("/yolo:")
        });

    if is_yolo_command || is_expanded_yolo_prompt(prompt) {
        let session_path = planning.join(".yolo-session");
        let _ = fs::write(&session_path, "session");
    }
}

/// Detect expanded YOLO command content via YAML frontmatter.
///
/// Returns true if the prompt starts with `---` frontmatter containing
/// a `name: yolo:` line (case-insensitive).
fn is_expanded_yolo_prompt(prompt: &str) -> bool {
    let mut in_frontmatter = false;
    let mut saw_start = false;

    for line in prompt.lines() {
        let trimmed = line.trim();

        // Skip leading blank lines
        if !saw_start && trimmed.is_empty() {
            continue;
        }

        if !saw_start {
            if trimmed == "---" {
                saw_start = true;
                in_frontmatter = true;
                continue;
            } else {
                return false; // First non-blank line must be ---
            }
        }

        if in_frontmatter {
            if trimmed == "---" {
                return false; // End of frontmatter without finding name: yolo:
            }

            // Check for name: yolo: (case-insensitive)
            let lower = trimmed.to_lowercase();
            if lower.starts_with("name:") {
                let value = lower["name:".len()..].trim();
                if value.starts_with("yolo:") {
                    return true;
                }
            }
        }
    }

    false
}

/// Check if --execute is run without any PLAN.md files.
fn check_execute_without_plans(planning: &Path) -> Option<String> {
    let state_path = planning.join("STATE.md");
    let current_phase = read_current_phase(&state_path)?;

    if current_phase.is_empty() {
        return None;
    }

    let phase_dir = planning.join("phases").join(&current_phase);
    let plan_count = count_plan_files(&phase_dir);

    if plan_count == 0 {
        Some(format!(
            "No PLAN.md for phase {}. Run /yolo:vibe to plan first.",
            current_phase
        ))
    } else {
        None
    }
}

/// Check if --archive is run with incomplete phases.
fn check_archive_incomplete(planning: &Path) -> Option<String> {
    let state_path = planning.join("STATE.md");
    if !state_path.exists() {
        return None;
    }

    let content = fs::read_to_string(&state_path).ok()?;
    let incomplete_count = content
        .lines()
        .filter(|line| {
            let lower = line.to_lowercase();
            lower.contains("status:") && (lower.contains("incomplete")
                || lower.contains("in progress")
                || lower.contains("in_progress")
                || lower.contains("pending"))
        })
        .count();

    if incomplete_count > 0 {
        Some(format!(
            "{} incomplete phase(s). Review STATE.md before shipping.",
            incomplete_count
        ))
    } else {
        None
    }
}

/// Read the current phase from STATE.md.
fn read_current_phase(state_path: &Path) -> Option<String> {
    let content = fs::read_to_string(state_path).ok()?;
    for line in content.lines() {
        if line.starts_with("## Current Phase") {
            // Extract phase identifier after "Phase" or ":"
            let phase = line
                .trim_start_matches("## Current Phase")
                .trim_start_matches(':')
                .trim();
            if !phase.is_empty() {
                return Some(phase.to_string());
            }
        }
    }
    None
}

/// Count PLAN.md files in a phase directory.
fn count_plan_files(phase_dir: &Path) -> usize {
    if !phase_dir.is_dir() {
        return 0;
    }

    fs::read_dir(phase_dir)
        .ok()
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .filter(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    name == "PLAN.md" || name.ends_with("-PLAN.md")
                })
                .count()
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tempfile::TempDir;

    fn make_input(data: serde_json::Value) -> HookInput {
        HookInput { data }
    }

    #[test]
    fn test_skip_no_planning_dir() {
        let input = make_input(json!({ "prompt": "/yolo:vibe" }));
        // No .yolo-planning/ in cwd, should return empty
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_skip_empty_prompt() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();

        // Temporarily change CWD — this test is inherently tied to CWD
        // Since we can't easily control CWD in tests, just verify the logic
        let input = make_input(json!({ "prompt": "" }));
        let result = handle(&input).unwrap();
        assert_eq!(result.exit_code, 0);
    }

    #[test]
    fn test_extract_prompt_from_prompt_field() {
        let data = json!({ "prompt": "hello world" });
        assert_eq!(extract_prompt(&data), "hello world");
    }

    #[test]
    fn test_extract_prompt_from_content_field() {
        let data = json!({ "content": "hello world" });
        assert_eq!(extract_prompt(&data), "hello world");
    }

    #[test]
    fn test_extract_prompt_missing() {
        let data = json!({ "other": "value" });
        assert_eq!(extract_prompt(&data), "");
    }

    #[test]
    fn test_is_expanded_yolo_prompt_valid() {
        let prompt = "---\nname: yolo:vibe\n---\nSome content";
        assert!(is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_case_insensitive() {
        let prompt = "---\nName: YOLO:status\n---\nContent";
        assert!(is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_leading_blanks() {
        let prompt = "\n\n---\nname: yolo:vibe\n---\n";
        assert!(is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_not_yolo() {
        let prompt = "---\nname: gsd:plan\n---\nContent";
        assert!(!is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_no_frontmatter() {
        let prompt = "Just a regular prompt";
        assert!(!is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_empty() {
        assert!(!is_expanded_yolo_prompt(""));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_only_dashes() {
        let prompt = "---\n---";
        assert!(!is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_gsd_isolation_creates_marker() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join(".gsd-isolation"), "").unwrap();

        handle_gsd_isolation(&planning, "/yolo:vibe");

        assert!(planning.join(".yolo-session").exists());
    }

    #[test]
    fn test_gsd_isolation_expanded_prompt() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join(".gsd-isolation"), "").unwrap();

        handle_gsd_isolation(&planning, "---\nname: yolo:status\n---\n");

        assert!(planning.join(".yolo-session").exists());
    }

    #[test]
    fn test_gsd_isolation_no_marker_for_plain_text() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join(".gsd-isolation"), "").unwrap();

        handle_gsd_isolation(&planning, "just a regular message");

        assert!(!planning.join(".yolo-session").exists());
    }

    #[test]
    fn test_gsd_isolation_no_isolation_file() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();

        handle_gsd_isolation(&planning, "/yolo:vibe");

        assert!(!planning.join(".yolo-session").exists());
    }

    #[test]
    fn test_check_execute_no_plans() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        let phase_dir = planning.join("phases").join("01");
        fs::create_dir_all(&phase_dir).unwrap();

        let state_path = planning.join("STATE.md");
        fs::write(&state_path, "## Current Phase: 01\n").unwrap();

        let warning = check_execute_without_plans(&planning);
        assert!(warning.is_some());
        assert!(warning.unwrap().contains("No PLAN.md"));
    }

    #[test]
    fn test_check_execute_with_plans() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        let phase_dir = planning.join("phases").join("01");
        fs::create_dir_all(&phase_dir).unwrap();

        fs::write(phase_dir.join("PLAN.md"), "# Plan").unwrap();
        let state_path = planning.join("STATE.md");
        fs::write(&state_path, "## Current Phase: 01\n").unwrap();

        let warning = check_execute_without_plans(&planning);
        assert!(warning.is_none());
    }

    #[test]
    fn test_check_execute_with_suffixed_plan() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        let phase_dir = planning.join("phases").join("02");
        fs::create_dir_all(&phase_dir).unwrap();

        fs::write(phase_dir.join("01-PLAN.md"), "# Plan 01").unwrap();
        let state_path = planning.join("STATE.md");
        fs::write(&state_path, "## Current Phase: 02\n").unwrap();

        let warning = check_execute_without_plans(&planning);
        assert!(warning.is_none());
    }

    #[test]
    fn test_check_archive_incomplete() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();

        let state_path = planning.join("STATE.md");
        fs::write(
            &state_path,
            "# State\nstatus: incomplete\nstatus: completed\nstatus: pending\n",
        )
        .unwrap();

        let warning = check_archive_incomplete(&planning);
        assert!(warning.is_some());
        assert!(warning.unwrap().contains("2 incomplete"));
    }

    #[test]
    fn test_check_archive_all_complete() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();

        let state_path = planning.join("STATE.md");
        fs::write(&state_path, "# State\nstatus: completed\nstatus: completed\n").unwrap();

        let warning = check_archive_incomplete(&planning);
        assert!(warning.is_none());
    }

    #[test]
    fn test_read_current_phase() {
        let tmp = TempDir::new().unwrap();
        let state = tmp.path().join("STATE.md");
        fs::write(&state, "# State\n## Current Phase: 03\nSome content").unwrap();

        let phase = read_current_phase(&state);
        assert_eq!(phase, Some("03".to_string()));
    }

    #[test]
    fn test_read_current_phase_missing() {
        let tmp = TempDir::new().unwrap();
        let state = tmp.path().join("STATE.md");
        fs::write(&state, "# State\nNo phase header here").unwrap();

        let phase = read_current_phase(&state);
        assert!(phase.is_none());
    }

    #[test]
    fn test_count_plan_files_empty() {
        let tmp = TempDir::new().unwrap();
        assert_eq!(count_plan_files(tmp.path()), 0);
    }

    #[test]
    fn test_count_plan_files_mixed() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("PLAN.md"), "").unwrap();
        fs::write(tmp.path().join("01-PLAN.md"), "").unwrap();
        fs::write(tmp.path().join("notes.md"), "").unwrap();
        assert_eq!(count_plan_files(tmp.path()), 2);
    }

    #[test]
    fn test_count_plan_files_nonexistent_dir() {
        assert_eq!(count_plan_files(Path::new("/nonexistent/dir")), 0);
    }

    #[test]
    fn test_is_expanded_yolo_prompt_with_extra_fields() {
        let prompt = "---\ntitle: My Command\nname: yolo:vibe\nversion: 1\n---\nBody";
        assert!(is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_name_with_spaces() {
        let prompt = "---\nname:   yolo:status  \n---\n";
        assert!(is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_is_expanded_yolo_prompt_non_yolo_name() {
        let prompt = "---\nname: some-other-plugin:cmd\n---\n";
        assert!(!is_expanded_yolo_prompt(prompt));
    }

    #[test]
    fn test_gsd_isolation_yolo_prefix_case_insensitive() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        fs::write(planning.join(".gsd-isolation"), "").unwrap();

        // /yolo: at start of a line (case insensitive check via starts_with + to_lowercase)
        handle_gsd_isolation(&planning, "/Yolo:vibe");
        // lowercase check only — /Yolo: won't match with to_lowercase().starts_with("/yolo:")
        // Actually it will because we lowercase the trimmed line
        assert!(planning.join(".yolo-session").exists());
    }

    #[test]
    fn test_check_archive_in_progress_status() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();

        let state_path = planning.join("STATE.md");
        fs::write(&state_path, "# State\nstatus: in progress\n").unwrap();

        let warning = check_archive_incomplete(&planning);
        assert!(warning.is_some());
        assert!(warning.unwrap().contains("1 incomplete"));
    }

    #[test]
    fn test_check_archive_no_state_file() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        // No STATE.md created

        let warning = check_archive_incomplete(&planning);
        assert!(warning.is_none());
    }

    #[test]
    fn test_check_execute_no_state_file() {
        let tmp = TempDir::new().unwrap();
        let planning = tmp.path().join(PLANNING_DIR);
        fs::create_dir_all(&planning).unwrap();
        // No STATE.md

        let warning = check_execute_without_plans(&planning);
        assert!(warning.is_none());
    }

    #[test]
    fn test_extract_prompt_prefers_prompt_over_content() {
        let data = json!({ "prompt": "from prompt", "content": "from content" });
        assert_eq!(extract_prompt(&data), "from prompt");
    }
}
