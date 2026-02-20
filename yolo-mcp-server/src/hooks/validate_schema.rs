use serde_json::{json, Value};
use std::fs;

const PLANNING_DIR: &str = ".yolo-planning";

/// Validates YAML frontmatter or JSON fields for a given schema type.
///
/// Schema types:
/// - `plan`: requires phase, plan, title, wave, depends_on, must_haves
/// - `summary`: requires phase, plan, title, status, tasks_completed, tasks_total
/// - `contract`: requires phase, plan, task_count, allowed_paths (JSON validation)
///
/// Gated by `v3_schema_validation` flag. Fail-open: always exit 0.
pub fn validate_schema(schema_type: &str, file_path: &str) -> (String, i32) {
    if !read_schema_validation_flag() {
        return ("valid".to_string(), 0);
    }

    if !std::path::Path::new(file_path).exists() {
        return ("invalid: file not found".to_string(), 0);
    }

    // Contract is JSON, not frontmatter
    if schema_type == "contract" {
        return validate_contract_schema(file_path);
    }

    let content = match fs::read_to_string(file_path) {
        Ok(c) => c,
        Err(_) => return ("valid".to_string(), 0),
    };

    let frontmatter = match extract_frontmatter(&content) {
        Some(fm) => fm,
        None => return ("invalid: no frontmatter".to_string(), 0),
    };

    let required = match schema_type {
        "plan" => vec!["phase", "plan", "title", "wave", "depends_on", "must_haves"],
        "summary" => vec![
            "phase",
            "plan",
            "title",
            "status",
            "tasks_completed",
            "tasks_total",
        ],
        _ => return ("valid".to_string(), 0),
    };

    let missing: Vec<&str> = required
        .iter()
        .filter(|field| !frontmatter_has_field(&frontmatter, field))
        .copied()
        .collect();

    if missing.is_empty() {
        ("valid".to_string(), 0)
    } else {
        (format!("invalid: missing {}", missing.join(", ")), 0)
    }
}

/// Hook entry point: takes hook JSON input, extracts schema_type and file_path.
pub fn validate_schema_hook(input: &Value) -> (Value, i32) {
    let schema_type = input
        .get("schema_type")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let file_path = input
        .get("file_path")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let (msg, code) = validate_schema(schema_type, file_path);

    if msg == "valid" {
        (json!({"valid": true}), code)
    } else {
        (json!({"valid": false, "reason": msg}), code)
    }
}

fn read_schema_validation_flag() -> bool {
    let config_path = format!("{}/config.json", PLANNING_DIR);
    let content = match fs::read_to_string(&config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };
    let config: Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };
    config
        .get("v3_schema_validation")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn validate_contract_schema(file_path: &str) -> (String, i32) {
    let content = match fs::read_to_string(file_path) {
        Ok(c) => c,
        Err(_) => return ("valid".to_string(), 0),
    };
    let contract: Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return ("invalid: not valid JSON".to_string(), 0),
    };

    let required = ["phase", "plan", "task_count", "allowed_paths"];
    for field in &required {
        if contract.get(*field).is_none() {
            return (format!("invalid: missing {}", field), 0);
        }
    }

    ("valid".to_string(), 0)
}

/// Extract frontmatter block between first and second `---` lines.
fn extract_frontmatter(content: &str) -> Option<String> {
    let mut lines = content.lines();

    if lines.next() != Some("---") {
        return None;
    }

    let mut fm_lines = Vec::new();
    for line in lines {
        if line == "---" {
            break;
        }
        fm_lines.push(line);
    }

    if fm_lines.is_empty() {
        return None;
    }

    Some(fm_lines.join("\n"))
}

/// Check if a frontmatter block contains a top-level field (line starts with `field:`).
fn frontmatter_has_field(frontmatter: &str, field: &str) -> bool {
    let prefix = format!("{}:", field);
    frontmatter.lines().any(|line| line.starts_with(&prefix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plan_schema_valid() {
        let content = "---\nphase: 1\nplan: 01\ntitle: Test\nwave: 1\ndepends_on: []\nmust_haves:\n  - item\n---\n";
        let fm = extract_frontmatter(content).unwrap();
        let required = vec!["phase", "plan", "title", "wave", "depends_on", "must_haves"];
        let missing: Vec<&str> = required
            .iter()
            .filter(|f| !frontmatter_has_field(&fm, f))
            .copied()
            .collect();
        assert!(missing.is_empty());
    }

    #[test]
    fn test_plan_schema_missing_wave() {
        let content = "---\nphase: 1\nplan: 01\ntitle: Test\ndepends_on: []\nmust_haves:\n  - item\n---\n";
        let fm = extract_frontmatter(content).unwrap();
        assert!(!frontmatter_has_field(&fm, "wave"));
    }

    #[test]
    fn test_summary_schema_valid() {
        let content =
            "---\nphase: 1\nplan: 01\ntitle: Test\nstatus: done\ntasks_completed: 5\ntasks_total: 5\n---\n";
        let fm = extract_frontmatter(content).unwrap();
        let required = vec![
            "phase",
            "plan",
            "title",
            "status",
            "tasks_completed",
            "tasks_total",
        ];
        let missing: Vec<&str> = required
            .iter()
            .filter(|f| !frontmatter_has_field(&fm, f))
            .copied()
            .collect();
        assert!(missing.is_empty());
    }

    #[test]
    fn test_summary_schema_missing_fields() {
        let content = "---\nphase: 1\ntitle: Test\n---\n";
        let fm = extract_frontmatter(content).unwrap();
        assert!(!frontmatter_has_field(&fm, "plan"));
        assert!(!frontmatter_has_field(&fm, "status"));
    }

    #[test]
    fn test_contract_schema_valid() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("contract.json");
        std::fs::write(
            &path,
            r#"{"phase":1,"plan":"01","task_count":3,"allowed_paths":["src/"]}"#,
        )
        .unwrap();

        let (result, code) = validate_contract_schema(path.to_str().unwrap());
        assert_eq!(result, "valid");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_contract_schema_missing_field() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("contract.json");
        std::fs::write(&path, r#"{"phase":1,"plan":"01"}"#).unwrap();

        let (result, code) = validate_contract_schema(path.to_str().unwrap());
        assert!(result.contains("missing task_count"));
        assert_eq!(code, 0);
    }

    #[test]
    fn test_contract_schema_invalid_json() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("contract.json");
        std::fs::write(&path, "not json").unwrap();

        let (result, code) = validate_contract_schema(path.to_str().unwrap());
        assert!(result.contains("not valid JSON"));
        assert_eq!(code, 0);
    }

    #[test]
    fn test_extract_frontmatter() {
        let content = "---\nfoo: bar\nbaz: 1\n---\nbody";
        let fm = extract_frontmatter(content).unwrap();
        assert_eq!(fm, "foo: bar\nbaz: 1");
    }

    #[test]
    fn test_extract_frontmatter_no_opening() {
        let content = "no frontmatter";
        assert!(extract_frontmatter(content).is_none());
    }

    #[test]
    fn test_extract_frontmatter_empty() {
        let content = "---\n---\nbody";
        assert!(extract_frontmatter(content).is_none());
    }

    #[test]
    fn test_frontmatter_has_field() {
        let fm = "phase: 1\nplan: 01\ntitle: Test";
        assert!(frontmatter_has_field(fm, "phase"));
        assert!(frontmatter_has_field(fm, "plan"));
        assert!(frontmatter_has_field(fm, "title"));
        assert!(!frontmatter_has_field(fm, "wave"));
    }

    #[test]
    fn test_validate_schema_flag_off() {
        // Without config.json, flag is off => "valid"
        let (result, code) = validate_schema("plan", "/nonexistent/file.md");
        assert_eq!(result, "valid");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_validate_schema_unknown_type() {
        // Unknown schema type returns "valid" (pass-through)
        // This only triggers when flag is on, but flag is off in test env => "valid" anyway
        let (result, code) = validate_schema("unknown_type", "/some/file.md");
        assert_eq!(result, "valid");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_hook_entry_point_valid() {
        let input = json!({
            "schema_type": "plan",
            "file_path": "/nonexistent"
        });
        let (result, code) = validate_schema_hook(&input);
        assert_eq!(code, 0);
        // Flag is off, so it returns valid
        assert_eq!(result["valid"], true);
    }

    #[test]
    fn test_hook_entry_point_empty_fields() {
        let input = json!({});
        let (result, code) = validate_schema_hook(&input);
        assert_eq!(code, 0);
        assert_eq!(result["valid"], true);
    }

    #[test]
    fn test_validate_schema_with_real_plan_file() {
        let dir = tempfile::tempdir().unwrap();
        let plan_path = dir.path().join("plan.md");
        std::fs::write(
            &plan_path,
            "---\nphase: 1\nplan: 01\ntitle: Test Plan\nwave: 1\ndepends_on: []\nmust_haves:\n  - item\n---\n# Plan",
        )
        .unwrap();

        // Create config with flag enabled
        let planning_dir = dir.path().join(".yolo-planning");
        std::fs::create_dir_all(&planning_dir).unwrap();
        std::fs::write(
            planning_dir.join("config.json"),
            r#"{"v3_schema_validation": true}"#,
        )
        .unwrap();

        // Note: validate_schema reads config from relative PLANNING_DIR,
        // so the flag won't be found in the test env. Test core logic directly.
        let content = std::fs::read_to_string(&plan_path).unwrap();
        let fm = extract_frontmatter(&content).unwrap();
        let required = vec!["phase", "plan", "title", "wave", "depends_on", "must_haves"];
        let missing: Vec<&str> = required
            .iter()
            .filter(|f| !frontmatter_has_field(&fm, f))
            .copied()
            .collect();
        assert!(missing.is_empty());
    }

    #[test]
    fn test_validate_schema_with_real_summary_file() {
        let dir = tempfile::tempdir().unwrap();
        let summary_path = dir.path().join("summary.md");
        std::fs::write(
            &summary_path,
            "---\nphase: 1\nplan: 01\ntitle: Done\nstatus: complete\ntasks_completed: 3\ntasks_total: 3\n---\n",
        )
        .unwrap();

        let content = std::fs::read_to_string(&summary_path).unwrap();
        let fm = extract_frontmatter(&content).unwrap();
        let required = vec![
            "phase",
            "plan",
            "title",
            "status",
            "tasks_completed",
            "tasks_total",
        ];
        let missing: Vec<&str> = required
            .iter()
            .filter(|f| !frontmatter_has_field(&fm, f))
            .copied()
            .collect();
        assert!(missing.is_empty());
    }
}
