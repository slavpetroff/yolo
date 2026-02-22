use serde_json::{json, Value};
use std::fs;

/// PostToolUse handler that validates SUMMARY.md structure in .yolo-planning/.
/// Non-blocking: always returns exit code 0.
///
/// Checks:
/// 1. File starts with `---` (YAML frontmatter)
/// 2. Contains `## What Was Built`
/// 3. Contains `## Files Modified`
pub fn validate_summary(input: &Value) -> (Value, i32) {
    let file_path = extract_file_path(input);

    // Only check SUMMARY.md files in .yolo-planning/
    if !is_summary_in_planning(&file_path) {
        return (Value::Null, 0);
    }

    let content = match fs::read_to_string(&file_path) {
        Ok(c) => c,
        Err(_) => return (Value::Null, 0),
    };

    let missing = check_summary_structure(&content);

    if missing.is_empty() {
        return (Value::Null, 0);
    }

    let msg = missing.join(" ");
    let output = json!({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": format!("SUMMARY validation: {}", msg)
        }
    });

    (output, 0)
}

fn extract_file_path(input: &Value) -> String {
    input
        .get("tool_input")
        .and_then(|ti| {
            ti.get("file_path")
                .or_else(|| ti.get("command"))
                .and_then(|v| v.as_str())
        })
        .unwrap_or("")
        .to_string()
}

fn is_summary_in_planning(path: &str) -> bool {
    path.contains(".yolo-planning/") && path.ends_with("SUMMARY.md")
}

fn check_summary_structure(content: &str) -> Vec<String> {
    let mut missing = Vec::new();

    if !content.starts_with("---") {
        missing.push("Missing YAML frontmatter.".to_string());
    } else {
        // Extract and validate frontmatter fields
        let frontmatter = extract_frontmatter(content);
        if let Some(fm) = frontmatter {
            let required_fields = [
                "phase",
                "plan",
                "status",
                "tasks_completed",
                "tasks_total",
                "commit_hashes",
            ];
            for field in &required_fields {
                if !frontmatter_has_field(&fm, field) {
                    missing.push(format!("Missing frontmatter field '{}'.", field));
                }
            }
            // Validate status value if present
            if let Some(status_val) = frontmatter_field_value(&fm, "status") {
                let valid_statuses = ["complete", "partial", "failed"];
                if !valid_statuses.contains(&status_val.as_str()) {
                    missing.push(format!(
                        "Invalid status '{}'. Must be one of: complete, partial, failed.",
                        status_val
                    ));
                }
            }
        } else {
            missing.push("YAML frontmatter not properly closed (missing second '---').".to_string());
        }
    }

    if !content.contains("## What Was Built") {
        missing.push("Missing '## What Was Built'.".to_string());
    }

    if !content.contains("## Files Modified") {
        missing.push("Missing '## Files Modified'.".to_string());
    }

    if !content.contains("## Deviations") {
        missing.push("Missing '## Deviations'.".to_string());
    }

    missing
}

/// Extract the frontmatter content between the first `---` and second `---`.
/// Returns None if frontmatter is not properly delimited.
fn extract_frontmatter(content: &str) -> Option<String> {
    if !content.starts_with("---") {
        return None;
    }
    // Find the second `---` after the first line
    let after_first = &content[3..];
    // Skip any characters on the first --- line (e.g., newline)
    let rest = after_first.trim_start_matches(|c: char| c != '\n');
    let rest = rest.strip_prefix('\n').unwrap_or(rest);
    if let Some(end_idx) = rest.find("\n---") {
        Some(rest[..end_idx].to_string())
    } else if rest.ends_with("---") {
        // Handle case where --- is at the very end without trailing newline
        let trimmed = rest.trim_end_matches("---");
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// Check if a frontmatter string contains a given field (line starting with `field_name:`).
fn frontmatter_has_field(frontmatter: &str, field_name: &str) -> bool {
    let prefix = format!("{}:", field_name);
    frontmatter.lines().any(|line| {
        let trimmed = line.trim();
        trimmed.starts_with(&prefix)
    })
}

/// Extract the value of a frontmatter field. Returns None if field not found.
fn frontmatter_field_value(frontmatter: &str, field_name: &str) -> Option<String> {
    let prefix = format!("{}:", field_name);
    for line in frontmatter.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim().trim_matches('"').trim();
            return Some(value.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_valid_summary() {
        let content = "---\nphase: \"01\"\nplan: \"01\"\nstatus: complete\ntasks_completed: 3\ntasks_total: 3\ncommit_hashes:\n  - abc123\n---\n## What Was Built\nStuff\n## Files Modified\nfiles\n## Deviations\nNone";
        let missing = check_summary_structure(content);
        assert!(missing.is_empty(), "Expected no missing items but got: {:?}", missing);
    }

    #[test]
    fn test_missing_frontmatter() {
        let content = "# Summary\n## What Was Built\nStuff\n## Files Modified\nfiles\n## Deviations\nNone";
        let missing = check_summary_structure(content);
        assert_eq!(missing.len(), 1);
        assert!(missing[0].contains("YAML frontmatter"));
    }

    #[test]
    fn test_missing_what_was_built() {
        let content = "---\nphase: \"01\"\nplan: \"01\"\nstatus: complete\ntasks_completed: 3\ntasks_total: 3\ncommit_hashes:\n  - abc123\n---\n## Files Modified\nfiles\n## Deviations\nNone";
        let missing = check_summary_structure(content);
        assert_eq!(missing.len(), 1);
        assert!(missing[0].contains("What Was Built"));
    }

    #[test]
    fn test_missing_files_modified() {
        let content = "---\nphase: \"01\"\nplan: \"01\"\nstatus: complete\ntasks_completed: 3\ntasks_total: 3\ncommit_hashes:\n  - abc123\n---\n## What Was Built\nStuff\n## Deviations\nNone";
        let missing = check_summary_structure(content);
        assert_eq!(missing.len(), 1);
        assert!(missing[0].contains("Files Modified"));
    }

    #[test]
    fn test_missing_all_sections() {
        let content = "Just some text";
        let missing = check_summary_structure(content);
        assert_eq!(missing.len(), 4); // frontmatter + What Was Built + Files Modified + Deviations
    }

    #[test]
    fn test_non_summary_path_skipped() {
        let input = json!({"tool_input": {"file_path": "/some/other/file.md"}});
        let (output, code) = validate_summary(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_summary_path_detected() {
        assert!(is_summary_in_planning(".yolo-planning/phases/01/01-SUMMARY.md"));
        assert!(!is_summary_in_planning("src/main.rs"));
        assert!(!is_summary_in_planning(".yolo-planning/plan.md"));
    }

    #[test]
    fn test_extract_file_path_from_file_path() {
        let input = json!({"tool_input": {"file_path": "/foo/bar.md"}});
        assert_eq!(extract_file_path(&input), "/foo/bar.md");
    }

    #[test]
    fn test_extract_file_path_from_command() {
        let input = json!({"tool_input": {"command": "/foo/bar.md"}});
        assert_eq!(extract_file_path(&input), "/foo/bar.md");
    }

    #[test]
    fn test_extract_file_path_missing() {
        let input = json!({"tool_input": {}});
        assert_eq!(extract_file_path(&input), "");
    }

    #[test]
    fn test_validate_summary_with_real_file() {
        let dir = tempfile::tempdir().unwrap();
        let planning_dir = dir.path().join(".yolo-planning").join("phases").join("01");
        std::fs::create_dir_all(&planning_dir).unwrap();
        let summary_path = planning_dir.join("01-SUMMARY.md");
        std::fs::write(&summary_path, "---\nphase: \"01\"\nplan: \"01\"\nstatus: complete\ntasks_completed: 3\ntasks_total: 3\ncommit_hashes:\n  - abc123\n---\n## What Was Built\nDone\n## Files Modified\nf.rs\n## Deviations\nNone").unwrap();

        let input = json!({"tool_input": {"file_path": summary_path.to_str().unwrap()}});
        let (output, code) = validate_summary(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_validate_summary_missing_sections() {
        let dir = tempfile::tempdir().unwrap();
        let planning_dir = dir.path().join(".yolo-planning").join("phases").join("01");
        std::fs::create_dir_all(&planning_dir).unwrap();
        let summary_path = planning_dir.join("01-SUMMARY.md");
        std::fs::write(&summary_path, "no frontmatter").unwrap();

        let input = json!({"tool_input": {"file_path": summary_path.to_str().unwrap()}});
        let (output, code) = validate_summary(&input);
        assert_eq!(code, 0);
        assert!(output.get("hookSpecificOutput").is_some());
        let ctx = output["hookSpecificOutput"]["additionalContext"].as_str().unwrap();
        assert!(ctx.contains("SUMMARY validation:"));
    }
}
