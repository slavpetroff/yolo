use serde_json::json;
use std::fs;
use std::path::Path;

/// Reviews a plan file for quality and completeness.
///
/// Usage: yolo review-plan <plan_path> [<phase_dir>]
///
/// Checks:
/// 1. Frontmatter completeness (phase, plan, title, wave, depends_on, must_haves)
/// 2. Task count (warn if >5)
/// 3. Must-haves present and non-empty
/// 4. Wave validity (positive integer)
/// 5. File paths check (if phase_dir provided, verify referenced files exist)
///
/// Exit codes: 0=approve, 1=reject (critical findings), 2=conditional (warnings only)
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo review-plan <plan_path> [<phase_dir>]".to_string());
    }

    let plan_path = Path::new(&args[2]);
    let phase_dir = args.get(3).map(|s| Path::new(s.as_str()));

    // Check plan file exists
    if !plan_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "review-plan",
            "verdict": "reject",
            "checks": [],
            "findings": [{"severity": "high", "check": "file", "issue": format!("Plan file not found: {}", plan_path.display())}]
        });
        return Ok((resp.to_string(), 1));
    }

    let content = fs::read_to_string(plan_path)
        .map_err(|e| format!("Failed to read plan file: {}", e))?;

    let mut checks = Vec::new();
    let mut findings = Vec::new();

    // Check 1: Frontmatter completeness
    let frontmatter = extract_frontmatter(&content);
    match &frontmatter {
        None => {
            checks.push(json!({"name": "frontmatter", "status": "fail"}));
            findings.push(json!({"severity": "high", "check": "frontmatter", "issue": "No valid YAML frontmatter found"}));
        }
        Some(fm) => {
            let required_fields = ["phase", "plan", "title", "wave", "depends_on", "must_haves"];
            let mut missing: Vec<&str> = Vec::new();
            for field in &required_fields {
                if !has_field(fm, field) {
                    missing.push(field);
                }
            }
            if missing.is_empty() {
                checks.push(json!({"name": "frontmatter", "status": "pass"}));
            } else {
                checks.push(json!({"name": "frontmatter", "status": "fail"}));
                findings.push(json!({
                    "severity": "high",
                    "check": "frontmatter",
                    "issue": format!("Missing fields: {}", missing.join(", "))
                }));
            }
        }
    };

    // Check 2: Task count
    let task_count = count_tasks(&content);
    if task_count > 5 {
        checks.push(json!({"name": "task_count", "status": "warn", "count": task_count}));
        findings.push(json!({
            "severity": "medium",
            "check": "task_count",
            "issue": format!("Plan has {} tasks (recommended max: 5)", task_count)
        }));
    } else {
        checks.push(json!({"name": "task_count", "status": "pass", "count": task_count}));
    }

    // Check 3: Must-haves present
    if let Some(ref fm) = frontmatter {
        let must_haves = parse_list_field(fm, "must_haves");
        if must_haves.is_empty() {
            checks.push(json!({"name": "must_haves", "status": "fail", "count": 0}));
            findings.push(json!({
                "severity": "high",
                "check": "must_haves",
                "issue": "must_haves is empty or missing"
            }));
        } else {
            checks.push(json!({"name": "must_haves", "status": "pass", "count": must_haves.len()}));
        }
    } else {
        checks.push(json!({"name": "must_haves", "status": "fail", "count": 0}));
        findings.push(json!({
            "severity": "high",
            "check": "must_haves",
            "issue": "Cannot check must_haves without frontmatter"
        }));
    }

    // Check 4: Wave validity
    if let Some(ref fm) = frontmatter {
        let wave_val = field_value(fm, "wave");
        match wave_val {
            Some(v) => {
                if let Ok(n) = v.parse::<u32>() {
                    if n > 0 {
                        checks.push(json!({"name": "wave_valid", "status": "pass"}));
                    } else {
                        checks.push(json!({"name": "wave_valid", "status": "fail"}));
                        findings.push(json!({
                            "severity": "high",
                            "check": "wave_valid",
                            "issue": "wave must be a positive integer (got 0)"
                        }));
                    }
                } else {
                    checks.push(json!({"name": "wave_valid", "status": "fail"}));
                    findings.push(json!({
                        "severity": "high",
                        "check": "wave_valid",
                        "issue": format!("wave is not a valid integer: {}", v)
                    }));
                }
            }
            None => {
                checks.push(json!({"name": "wave_valid", "status": "fail"}));
                findings.push(json!({
                    "severity": "high",
                    "check": "wave_valid",
                    "issue": "wave field missing from frontmatter"
                }));
            }
        }
    } else {
        checks.push(json!({"name": "wave_valid", "status": "fail"}));
    }

    // Check 5: File paths check (only if phase_dir provided)
    if let Some(pd) = phase_dir {
        let file_refs = extract_file_paths(&content);
        let mut missing_count = 0u32;
        let checked = file_refs.len() as u32;
        for file_ref in &file_refs {
            // Resolve relative to phase_dir's parent's parent (project root)
            let project_root = pd.parent()
                .and_then(|p| p.parent())
                .unwrap_or(pd);
            let full_path = project_root.join(file_ref);
            if !full_path.exists() {
                missing_count += 1;
                findings.push(json!({
                    "severity": "low",
                    "check": "file_paths",
                    "issue": format!("Referenced file not found: {}", file_ref)
                }));
            }
        }
        if missing_count > 0 {
            checks.push(json!({"name": "file_paths", "status": "warn", "checked": checked, "missing": missing_count}));
        } else {
            checks.push(json!({"name": "file_paths", "status": "pass", "checked": checked, "missing": 0}));
        }
    }

    // Determine verdict
    let has_high = findings.iter().any(|f| f["severity"] == "high");
    let has_warnings = !findings.is_empty();

    let (verdict, exit_code) = if has_high {
        ("reject", 1)
    } else if has_warnings {
        ("conditional", 2)
    } else {
        ("approve", 0)
    };

    let resp = json!({
        "ok": !has_high,
        "cmd": "review-plan",
        "verdict": verdict,
        "checks": checks,
        "findings": findings,
    });

    Ok((resp.to_string(), exit_code))
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
    frontmatter.lines().any(|line| line.trim().starts_with(&prefix))
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

/// Count `### Task N:` headers in the plan content.
fn count_tasks(content: &str) -> u32 {
    content.lines()
        .filter(|line| {
            let trimmed = line.trim();
            trimmed.starts_with("### Task ") && trimmed.contains(':')
        })
        .count() as u32
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
            if trimmed.starts_with("- ") {
                let item = trimmed[2..].trim().trim_matches('"').trim_matches('\'');
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

/// Extract file paths from `**Files:**` lines in plan tasks.
/// Skips entries marked with `(new)`.
fn extract_file_paths(content: &str) -> Vec<String> {
    let mut paths = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("**Files:**") {
            let value = trimmed["**Files:**".len()..].trim();
            for part in value.split(',') {
                let part = part.trim();
                // Skip entries marked as new
                if part.contains("(new)") {
                    continue;
                }
                // Clean up backticks
                let cleaned = part.trim_matches('`').trim();
                if !cleaned.is_empty() {
                    paths.push(cleaned.to_string());
                }
            }
        }
    }
    paths
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_review_plan_valid() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("01-PLAN.md");
        fs::write(&plan_path, "\
---
phase: \"03\"
plan: \"01\"
title: \"Test plan\"
wave: 1
depends_on: []
must_haves:
  - \"Feature A works\"
  - \"Tests pass\"
---

# Plan 01: Test Plan

## Tasks

### Task 1: Do something

**Files:** `some/file.rs` (new)

Implement the thing.
").unwrap();

        let args = vec![
            "yolo".to_string(),
            "review-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0, "Expected exit 0, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["verdict"], "approve");
    }

    #[test]
    fn test_review_plan_missing_frontmatter() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("bad-PLAN.md");
        fs::write(&plan_path, "# No frontmatter\n\nJust a plain markdown file.\n").unwrap();

        let args = vec![
            "yolo".to_string(),
            "review-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1, "Expected exit 1, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["verdict"], "reject");
        let findings = parsed["findings"].as_array().unwrap();
        assert!(findings.iter().any(|f| f["issue"].as_str().unwrap().contains("frontmatter")));
    }

    #[test]
    fn test_review_plan_missing_must_haves() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("02-PLAN.md");
        fs::write(&plan_path, "\
---
phase: \"03\"
plan: \"02\"
title: \"Plan without must_haves\"
wave: 1
depends_on: []
must_haves: []
---

# Plan

### Task 1: Something

Do it.
").unwrap();

        let args = vec![
            "yolo".to_string(),
            "review-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1, "Expected exit 1 for empty must_haves, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["verdict"], "reject");
        let findings = parsed["findings"].as_array().unwrap();
        assert!(findings.iter().any(|f| f["check"].as_str().unwrap() == "must_haves"));
    }

    #[test]
    fn test_review_plan_too_many_tasks() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("03-PLAN.md");
        let mut content = String::from("\
---
phase: \"03\"
plan: \"03\"
title: \"Big plan\"
wave: 1
depends_on: []
must_haves:
  - \"It works\"
---

# Big Plan

");
        for i in 1..=7 {
            content.push_str(&format!("### Task {}: Do thing {}\n\nDetails.\n\n", i, i));
        }
        fs::write(&plan_path, &content).unwrap();

        let args = vec![
            "yolo".to_string(),
            "review-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 2, "Expected exit 2 for warnings, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["verdict"], "conditional");
        let findings = parsed["findings"].as_array().unwrap();
        assert!(findings.iter().any(|f| {
            f["check"].as_str().unwrap() == "task_count"
                && f["issue"].as_str().unwrap().contains("7")
        }));
    }

    #[test]
    fn test_review_plan_file_paths_check() {
        let dir = tempdir().unwrap();
        let phases_dir = dir.path().join("phases").join("03-test");
        fs::create_dir_all(&phases_dir).unwrap();

        // Create a file that the plan references
        let existing = dir.path().join("existing.txt");
        fs::write(&existing, "exists").unwrap();

        let plan_path = phases_dir.join("03-01-PLAN.md");
        fs::write(&plan_path, "\
---
phase: \"03\"
plan: \"01\"
title: \"File path test\"
wave: 1
depends_on: []
must_haves:
  - \"Files exist\"
---

# Plan

### Task 1: Check files

**Files:** `existing.txt`, `missing.txt`, `also/missing.rs` (new)

Do stuff.
").unwrap();

        let args = vec![
            "yolo".to_string(),
            "review-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phases_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();

        // Should find the file_paths check
        let checks = parsed["checks"].as_array().unwrap();
        let fp_check = checks.iter().find(|c| c["name"] == "file_paths").unwrap();
        // existing.txt + missing.txt (also/missing.rs skipped because of (new))
        assert_eq!(fp_check["checked"], 2);
        assert_eq!(fp_check["missing"], 1);
        // missing.txt doesn't exist but it's low severity, so verdict depends on other checks
        assert_eq!(parsed["ok"], true, "Low-severity file findings should not reject: {}", output);
        assert!(code == 0 || code == 2, "Expected exit 0 or 2, got {}: {}", code, output);
    }
}
