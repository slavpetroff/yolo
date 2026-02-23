use regex::Regex;
use serde_json::json;
use std::fs;
use std::path::Path;

/// Verifies plan completion by cross-referencing SUMMARY.md against PLAN.md.
///
/// Usage: yolo verify-plan-completion <summary_path> <plan_path>
///
/// Checks:
/// 1. SUMMARY frontmatter has required fields (phase, plan, title, status, tasks_completed, tasks_total, commit_hashes)
/// 2. PLAN task count matches tasks_total in SUMMARY
/// 3. tasks_completed equals plan task count when status=complete
/// 4. commit_hashes is non-empty and each hash is 7+ hex chars
/// 5. Required body sections exist: ## What Was Built, ## Files Modified
///
/// Exit codes: 0=all pass, 1=any fail
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err(
            "Usage: yolo verify-plan-completion <summary_path> <plan_path>".to_string(),
        );
    }

    let summary_path = Path::new(&args[2]);
    let plan_path = Path::new(&args[3]);

    let mut checks = Vec::new();
    let mut all_pass = true;

    // Read SUMMARY.md
    if !summary_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "verify-plan-completion",
            "checks": [{"name": "summary_exists", "status": "fail", "detail": format!("SUMMARY not found: {}", summary_path.display()), "fixable_by": "dev"}]
        });
        return Ok((resp.to_string(), 1));
    }

    let summary_content = fs::read_to_string(summary_path)
        .map_err(|e| format!("Failed to read SUMMARY: {}", e))?;

    // Read PLAN.md
    if !plan_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "verify-plan-completion",
            "checks": [{"name": "plan_exists", "status": "fail", "detail": format!("PLAN not found: {}", plan_path.display()), "fixable_by": "dev"}]
        });
        return Ok((resp.to_string(), 1));
    }

    let plan_content = fs::read_to_string(plan_path)
        .map_err(|e| format!("Failed to read PLAN: {}", e))?;

    // Extract frontmatter from SUMMARY
    let frontmatter = extract_frontmatter(&summary_content);

    // Check 1: Required frontmatter fields
    let required_fields = [
        "phase",
        "plan",
        "title",
        "status",
        "tasks_completed",
        "tasks_total",
        "commit_hashes",
    ];
    match &frontmatter {
        None => {
            checks.push(json!({"name": "frontmatter_fields", "status": "fail", "detail": "No YAML frontmatter found in SUMMARY", "fixable_by": "dev"}));
            all_pass = false;
        }
        Some(fm) => {
            let missing: Vec<&str> = required_fields
                .iter()
                .filter(|f| !has_field(fm, f))
                .copied()
                .collect();
            if missing.is_empty() {
                checks.push(
                    json!({"name": "frontmatter_fields", "status": "pass", "detail": "All required fields present", "fixable_by": "none"}),
                );
            } else {
                checks.push(json!({"name": "frontmatter_fields", "status": "fail", "detail": format!("Missing fields: {}", missing.join(", ")), "fixable_by": "dev"}));
                all_pass = false;
            }
        }
    }

    // Check 2: Plan task count matches tasks_total
    let plan_task_count = count_plan_tasks(&plan_content);
    if let Some(ref fm) = frontmatter {
        let tasks_total = field_value(fm, "tasks_total")
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(0);
        if plan_task_count == tasks_total {
            checks.push(json!({"name": "task_count_match", "status": "pass", "detail": format!("Plan tasks ({}) matches tasks_total ({})", plan_task_count, tasks_total), "fixable_by": "none"}));
        } else {
            checks.push(json!({"name": "task_count_match", "status": "fail", "detail": format!("Plan tasks ({}) != tasks_total ({})", plan_task_count, tasks_total), "fixable_by": "architect"}));
            all_pass = false;
        }
    } else {
        checks.push(
            json!({"name": "task_count_match", "status": "fail", "detail": "Cannot check: no frontmatter", "fixable_by": "architect"}),
        );
        all_pass = false;
    }

    // Check 3: tasks_completed == plan task count when status=complete
    if let Some(ref fm) = frontmatter {
        let status = field_value(fm, "status").unwrap_or_default();
        let tasks_completed = field_value(fm, "tasks_completed")
            .and_then(|v| v.parse::<u32>().ok())
            .unwrap_or(0);
        if status == "complete" {
            if tasks_completed == plan_task_count {
                checks.push(json!({"name": "completion_match", "status": "pass", "detail": format!("tasks_completed ({}) matches plan tasks ({})", tasks_completed, plan_task_count), "fixable_by": "none"}));
            } else {
                checks.push(json!({"name": "completion_match", "status": "fail", "detail": format!("tasks_completed ({}) != plan tasks ({})", tasks_completed, plan_task_count), "fixable_by": "dev"}));
                all_pass = false;
            }
        } else {
            checks.push(json!({"name": "completion_match", "status": "pass", "detail": format!("Status is '{}', not 'complete' — skipping completion check", status), "fixable_by": "none"}));
        }
    } else {
        checks.push(
            json!({"name": "completion_match", "status": "fail", "detail": "Cannot check: no frontmatter", "fixable_by": "dev"}),
        );
        all_pass = false;
    }

    // Check 4: commit_hashes non-empty and valid format
    if let Some(ref fm) = frontmatter {
        let hashes = parse_list_field(fm, "commit_hashes");
        let hex_re = Regex::new(r"^[0-9a-fA-F]{7,}$").unwrap();
        if hashes.is_empty() {
            checks.push(
                json!({"name": "commit_hashes", "status": "fail", "detail": "commit_hashes is empty", "fixable_by": "dev"}),
            );
            all_pass = false;
        } else {
            let invalid: Vec<&String> =
                hashes.iter().filter(|h| !hex_re.is_match(h)).collect();
            if invalid.is_empty() {
                checks.push(json!({"name": "commit_hashes", "status": "pass", "detail": format!("{} valid hashes", hashes.len()), "fixable_by": "none"}));
            } else {
                checks.push(json!({"name": "commit_hashes", "status": "fail", "detail": format!("Invalid hashes: {:?}", invalid), "fixable_by": "dev"}));
                all_pass = false;
            }
        }
    } else {
        checks.push(
            json!({"name": "commit_hashes", "status": "fail", "detail": "Cannot check: no frontmatter", "fixable_by": "dev"}),
        );
        all_pass = false;
    }

    // Check 5: Required body sections
    let has_what_built = summary_content.contains("## What Was Built");
    let has_files_modified = summary_content.contains("## Files Modified");
    if has_what_built && has_files_modified {
        checks.push(json!({"name": "body_sections", "status": "pass", "detail": "Both '## What Was Built' and '## Files Modified' present", "fixable_by": "none"}));
    } else {
        let mut missing_sections = Vec::new();
        if !has_what_built {
            missing_sections.push("## What Was Built");
        }
        if !has_files_modified {
            missing_sections.push("## Files Modified");
        }
        checks.push(json!({"name": "body_sections", "status": "fail", "detail": format!("Missing sections: {}", missing_sections.join(", ")), "fixable_by": "dev"}));
        all_pass = false;
    }

    let resp = json!({
        "ok": all_pass,
        "cmd": "verify-plan-completion",
        "checks": checks,
    });

    Ok((resp.to_string(), if all_pass { 0 } else { 1 }))
}

/// Extract frontmatter content between first `---` and second `---`.
fn extract_frontmatter(content: &str) -> Option<String> {
    if !content.starts_with("---") {
        return None;
    }
    let after_first = &content[3..];
    let rest = after_first.trim_start_matches(|c: char| c != '\n');
    let rest = rest.strip_prefix('\n').unwrap_or(rest);
    if let Some(end_idx) = rest.find("\n---") {
        Some(rest[..end_idx].to_string())
    } else if rest.ends_with("---") {
        let trimmed = rest.trim_end_matches("---");
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// Check if a frontmatter field exists.
fn has_field(frontmatter: &str, field_name: &str) -> bool {
    let prefix = format!("{}:", field_name);
    frontmatter
        .lines()
        .any(|line| line.trim().starts_with(&prefix))
}

/// Extract the value of a frontmatter field.
fn field_value(frontmatter: &str, field_name: &str) -> Option<String> {
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

/// Count `### Task N` headers in the plan content.
fn count_plan_tasks(content: &str) -> u32 {
    let re = Regex::new(r"(?m)^### Task \d+").unwrap();
    re.find_iter(content).count() as u32
}

/// Parse a YAML list field from frontmatter (supports inline array and block list).
fn parse_list_field(frontmatter: &str, field_name: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut in_field = false;
    let prefix = format!("{}:", field_name);

    for line in frontmatter.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim();

            // Inline array: ["a", "b"]
            if value.starts_with('[') {
                let inner = value.trim_start_matches('[').trim_end_matches(']');
                if inner.trim().is_empty() {
                    return result;
                }
                for item in inner.split(',') {
                    let cleaned = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !cleaned.is_empty() {
                        result.push(cleaned.to_string());
                    }
                }
                return result;
            }

            if value == "[]" {
                return result;
            }

            in_field = true;
            continue;
        }

        if in_field {
            if let Some(rest) = trimmed.strip_prefix("- ") {
                let item = rest.trim().trim_matches('"').trim_matches('\'');
                if !item.is_empty() {
                    result.push(item.to_string());
                }
            } else if !trimmed.is_empty() {
                break;
            }
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_valid_summary_passes() {
        let dir = tempdir().unwrap();
        let summary_path = dir.path().join("SUMMARY.md");
        let plan_path = dir.path().join("PLAN.md");

        fs::write(
            &summary_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"QA commands\"
status: complete
tasks_completed: 2
tasks_total: 2
commit_hashes:
  - \"abc1234\"
  - \"def5678\"
---

# Summary

## What Was Built

QA verification commands.

## Files Modified

- verify_plan_completion.rs
- commit_lint.rs
",
        )
        .unwrap();

        fs::write(
            &plan_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"QA commands\"
wave: 1
depends_on: []
must_haves:
  - \"Commands work\"
---

# Plan

### Task 1: First task

Do something.

### Task 2: Second task

Do another thing.
",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "verify-plan-completion".to_string(),
            summary_path.to_string_lossy().to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0, "Expected exit 0, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        // All passing checks should have fixable_by: "none"
        let checks = parsed["checks"].as_array().unwrap();
        for check in checks {
            assert_eq!(check["fixable_by"], "none", "Passing check {} should have fixable_by=none", check["name"]);
        }
    }

    #[test]
    fn test_missing_fields_fails() {
        let dir = tempdir().unwrap();
        let summary_path = dir.path().join("SUMMARY.md");
        let plan_path = dir.path().join("PLAN.md");

        fs::write(
            &summary_path,
            "\
---
phase: \"04\"
title: \"Incomplete\"
---

# Summary
",
        )
        .unwrap();

        fs::write(
            &plan_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"Test\"
wave: 1
depends_on: []
must_haves:
  - \"Works\"
---

### Task 1: Only task
",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "verify-plan-completion".to_string(),
            summary_path.to_string_lossy().to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1, "Expected exit 1, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
        let checks = parsed["checks"].as_array().unwrap();
        assert!(checks.iter().any(|c| c["name"] == "frontmatter_fields"
            && c["status"] == "fail"));
        // Failed checks should have a non-"none" fixable_by
        for check in checks {
            if check["status"] == "fail" {
                assert_ne!(check["fixable_by"], "none", "Failed check {} should not have fixable_by=none", check["name"]);
                assert!(check["fixable_by"].is_string(), "Failed check {} should have fixable_by field", check["name"]);
            }
        }
    }
}
