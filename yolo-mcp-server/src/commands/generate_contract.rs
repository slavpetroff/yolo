use regex::Regex;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

/// Parse YAML frontmatter delimited by `---` lines.
/// Returns the frontmatter text (without delimiters) and the body after it.
fn split_frontmatter(content: &str) -> (String, String) {
    let mut lines = content.lines();
    let mut fm_lines = Vec::new();
    let mut body_lines = Vec::new();
    let mut dashes_seen = 0;

    for line in &mut lines {
        if line.trim() == "---" {
            dashes_seen += 1;
            if dashes_seen == 2 {
                break;
            }
            continue;
        }
        if dashes_seen == 1 {
            fm_lines.push(line);
        }
    }

    for line in lines {
        body_lines.push(line);
    }

    (fm_lines.join("\n"), body_lines.join("\n"))
}

/// Extract a simple scalar value from frontmatter: `key: value`
fn fm_scalar(fm: &str, key: &str) -> Option<String> {
    let prefix = format!("{}:", key);
    for line in fm.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(&prefix) {
            let val = trimmed[prefix.len()..].trim();
            // Strip surrounding quotes
            let val = val.trim_matches('"').trim_matches('\'');
            if !val.is_empty() {
                return Some(val.to_string());
            }
        }
    }
    None
}

/// Extract a YAML list from frontmatter. Handles both:
///   key:
///     - item1
///     - item2
/// and inline: key: [item1, item2]
fn fm_list(fm: &str, key: &str) -> Vec<String> {
    let prefix = format!("{}:", key);
    let mut result = Vec::new();
    let mut in_list = false;

    for line in fm.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(&prefix) {
            let rest = trimmed[prefix.len()..].trim();
            // Inline array: [item1, item2]
            if rest.starts_with('[') && rest.ends_with(']') {
                let inner = &rest[1..rest.len() - 1];
                for item in inner.split(',') {
                    let item = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !item.is_empty() {
                        result.push(item.to_string());
                    }
                }
                return result;
            }
            in_list = true;
            continue;
        }
        if in_list {
            if let Some(stripped) = trimmed.strip_prefix("- ") {
                let item = stripped.trim().trim_matches('"').trim_matches('\'').trim();
                if !item.is_empty() {
                    result.push(item.to_string());
                }
            } else if !trimmed.is_empty() && !trimmed.starts_with('#') {
                // Non-indented, non-empty line means end of list
                break;
            }
        }
    }
    result
}

/// Extract allowed_paths from `**Files:**` lines in the plan body.
fn extract_allowed_paths(body: &str) -> Vec<String> {
    let re = Regex::new(r"\*\*Files:\*\*\s+(.+)").unwrap();
    let mut paths = BTreeSet::new();

    for cap in re.captures_iter(body) {
        let files_str = &cap[1];
        for part in files_str.split(',') {
            let cleaned = part
                .trim()
                .replace("(new)", "")
                .replace("(if exists)", "")
                .trim()
                .trim_matches('`')
                .trim()
                .to_string();
            if !cleaned.is_empty() {
                paths.insert(cleaned);
            }
        }
    }

    paths.into_iter().collect()
}

/// Count task headings: `## Task N` or `### Task N`
fn count_tasks(body: &str) -> usize {
    let re = Regex::new(r"(?m)^#{2,3}\s+Task\s+\d+").unwrap();
    re.find_iter(body).count()
}

/// Generate task IDs: {phase}-{plan}-T{N}
fn task_ids(phase: u64, plan: u64, count: usize) -> Vec<String> {
    (1..=count)
        .map(|i| format!("{}-{}-T{}", phase, plan, i))
        .collect()
}

/// Read config.json and return (v3_contract_lite, v2_hard_contracts) flags.
fn read_config_flags(cwd: &Path) -> (bool, bool) {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if !config_path.exists() {
        return (false, false);
    }
    let Ok(config_str) = fs::read_to_string(&config_path) else {
        return (false, false);
    };
    let Ok(config) = serde_json::from_str::<Value>(&config_str) else {
        return (false, false);
    };
    let v3 = config
        .get("v3_contract_lite")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let v2 = config
        .get("v2_hard_contracts")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    (v3, v2)
}

/// Read a numeric config value with default.
fn config_number(cwd: &Path, key: &str, default: u64) -> u64 {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if !config_path.exists() {
        return default;
    }
    let Ok(config_str) = fs::read_to_string(&config_path) else {
        return default;
    };
    let Ok(config) = serde_json::from_str::<Value>(&config_str) else {
        return default;
    };
    config
        .get(key)
        .and_then(|v| v.as_u64())
        .unwrap_or(default)
}

/// Core contract generation. Returns (contract_json, output_path) or None on skip.
pub fn generate(plan_path: &Path, cwd: &Path) -> Option<(Value, String)> {
    if !plan_path.exists() {
        return None;
    }

    let (v3_lite, v2_hard) = read_config_flags(cwd);
    if !v3_lite && !v2_hard {
        return None;
    }

    let content = fs::read_to_string(plan_path).ok()?;
    let (fm, body) = split_frontmatter(&content);

    let phase: u64 = fm_scalar(&fm, "phase")?.parse().ok()?;
    let plan: u64 = fm_scalar(&fm, "plan")?.parse().ok()?;
    let title = fm_scalar(&fm, "title").unwrap_or_default();
    let must_haves = fm_list(&fm, "must_haves");
    let allowed_paths = extract_allowed_paths(&body);
    let task_count = count_tasks(&body);

    let contract_dir = cwd.join(".yolo-planning").join(".contracts");
    fs::create_dir_all(&contract_dir).ok()?;
    let contract_file = contract_dir.join(format!("{}-{}.json", phase, plan));

    let contract = if v2_hard {
        // V2 Full: 11 fields + contract_hash
        let forbidden_paths = fm_list(&fm, "forbidden_paths");
        let depends_on: Vec<Value> = fm_list(&fm, "depends_on")
            .iter()
            .filter_map(|s| s.parse::<i64>().ok().map(Value::from))
            .collect();
        let verification_checks = fm_list(&fm, "verification_checks");
        let tids = task_ids(phase, plan, task_count);

        let token_budget = config_number(cwd, "max_token_budget", 50000);
        let timeout = config_number(cwd, "task_timeout_seconds", 600);

        let body_json = json!({
            "phase_id": format!("phase-{}", phase),
            "plan_id": format!("phase-{}-plan-{}", phase, plan),
            "phase": phase,
            "plan": plan,
            "objective": title,
            "task_ids": tids,
            "task_count": task_count,
            "allowed_paths": allowed_paths,
            "forbidden_paths": forbidden_paths,
            "depends_on": depends_on,
            "must_haves": must_haves,
            "verification_checks": verification_checks,
            "max_token_budget": token_budget,
            "timeout_seconds": timeout,
        });

        // SHA-256 of serialized body (matching bash: echo "$BODY" | shasum -a 256)
        let body_str = serde_json::to_string_pretty(&body_json).ok()?;
        let hash_input = format!("{}\n", body_str);
        let mut hasher = Sha256::new();
        hasher.update(hash_input.as_bytes());
        let hash = format!("{:x}", hasher.finalize());

        let mut contract = body_json;
        contract["contract_hash"] = json!(hash);
        contract
    } else {
        // V3 Lite: 5 fields
        json!({
            "phase": phase,
            "plan": plan,
            "task_count": task_count,
            "must_haves": must_haves,
            "allowed_paths": allowed_paths,
        })
    };

    let contract_str = serde_json::to_string_pretty(&contract).ok()?;
    fs::write(&contract_file, &contract_str).ok()?;

    let path_str = contract_file.to_string_lossy().to_string();
    Some((contract, path_str))
}

/// CLI entry point: `yolo generate-contract <plan-path>`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo generate-contract <plan-path>".to_string());
    }

    let plan_path = cwd.join(&args[2]);
    match generate(&plan_path, cwd) {
        Some((_contract, path)) => Ok((path, 0)),
        None => Ok(("".to_string(), 0)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_config(dir: &Path, v3: bool, v2: bool) {
        let planning = dir.join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        let config = json!({
            "v3_contract_lite": v3,
            "v2_hard_contracts": v2,
            "max_token_budget": 40000,
            "task_timeout_seconds": 300,
        });
        fs::write(planning.join("config.json"), config.to_string()).unwrap();
    }

    fn sample_plan() -> String {
        r#"---
phase: 2
plan: 11
title: "Migrate contract scripts to native Rust"
must_haves:
  - "SHA-256 contract hash"
  - "V3 lite output"
depends_on: [9, 10]
verification_checks:
  - "cargo test passes"
forbidden_paths:
  - "scripts/"
---
## Task 1: Implement generate_contract module
**Files:** `yolo-mcp-server/src/commands/generate_contract.rs` (new)
Some description here.

## Task 2: Implement contract_revision module
**Files:** `yolo-mcp-server/src/commands/contract_revision.rs` (new)
Another description.

## Task 3: Register CLI commands
**Files:** `yolo-mcp-server/src/commands/mod.rs`, `yolo-mcp-server/src/cli/router.rs`
Final task.
"#
        .to_string()
    }

    #[test]
    fn test_split_frontmatter() {
        let (fm, body) = split_frontmatter(&sample_plan());
        assert!(fm.contains("phase: 2"));
        assert!(fm.contains("plan: 11"));
        assert!(body.contains("## Task 1"));
    }

    #[test]
    fn test_fm_scalar() {
        let (fm, _) = split_frontmatter(&sample_plan());
        assert_eq!(fm_scalar(&fm, "phase"), Some("2".to_string()));
        assert_eq!(fm_scalar(&fm, "plan"), Some("11".to_string()));
        assert_eq!(
            fm_scalar(&fm, "title"),
            Some("Migrate contract scripts to native Rust".to_string())
        );
    }

    #[test]
    fn test_fm_list() {
        let (fm, _) = split_frontmatter(&sample_plan());
        let mh = fm_list(&fm, "must_haves");
        assert_eq!(mh.len(), 2);
        assert_eq!(mh[0], "SHA-256 contract hash");

        let deps = fm_list(&fm, "depends_on");
        assert_eq!(deps, vec!["9", "10"]);
    }

    #[test]
    fn test_extract_allowed_paths() {
        let (_, body) = split_frontmatter(&sample_plan());
        let paths = extract_allowed_paths(&body);
        assert_eq!(paths.len(), 4);
        assert!(paths.contains(&"yolo-mcp-server/src/commands/generate_contract.rs".to_string()));
        assert!(paths.contains(&"yolo-mcp-server/src/commands/contract_revision.rs".to_string()));
        assert!(paths.contains(&"yolo-mcp-server/src/commands/mod.rs".to_string()));
        assert!(paths.contains(&"yolo-mcp-server/src/cli/router.rs".to_string()));
    }

    #[test]
    fn test_count_tasks() {
        let (_, body) = split_frontmatter(&sample_plan());
        assert_eq!(count_tasks(&body), 3);
    }

    #[test]
    fn test_generate_v3_lite() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, true, false);

        let plan_path = cwd.join("PLAN.md");
        fs::write(&plan_path, sample_plan()).unwrap();

        let (contract, path) = generate(&plan_path, cwd).unwrap();
        assert!(path.contains("2-11.json"));
        assert_eq!(contract["phase"], 2);
        assert_eq!(contract["plan"], 11);
        assert_eq!(contract["task_count"], 3);
        assert!(contract.get("contract_hash").is_none());
        assert_eq!(contract["must_haves"].as_array().unwrap().len(), 2);
        assert_eq!(contract["allowed_paths"].as_array().unwrap().len(), 4);
    }

    #[test]
    fn test_generate_v2_full() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, false, true);

        let plan_path = cwd.join("PLAN.md");
        fs::write(&plan_path, sample_plan()).unwrap();

        let (contract, path) = generate(&plan_path, cwd).unwrap();
        assert!(path.contains("2-11.json"));
        assert_eq!(contract["phase"], 2);
        assert_eq!(contract["plan"], 11);
        assert_eq!(contract["phase_id"], "phase-2");
        assert_eq!(contract["plan_id"], "phase-2-plan-11");
        assert_eq!(
            contract["objective"],
            "Migrate contract scripts to native Rust"
        );
        assert_eq!(contract["task_count"], 3);
        assert_eq!(contract["task_ids"].as_array().unwrap().len(), 3);
        assert_eq!(contract["task_ids"][0], "2-11-T1");
        assert_eq!(contract["allowed_paths"].as_array().unwrap().len(), 4);
        assert_eq!(contract["forbidden_paths"].as_array().unwrap().len(), 1);
        assert_eq!(contract["depends_on"].as_array().unwrap().len(), 2);
        assert_eq!(contract["depends_on"][0], 9);
        assert_eq!(contract["must_haves"].as_array().unwrap().len(), 2);
        assert_eq!(contract["verification_checks"].as_array().unwrap().len(), 1);
        assert_eq!(contract["max_token_budget"], 40000);
        assert_eq!(contract["timeout_seconds"], 300);
        // Hash must be a 64-char hex string
        let hash = contract["contract_hash"].as_str().unwrap();
        assert_eq!(hash.len(), 64);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_generate_no_flags() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, false, false);

        let plan_path = cwd.join("PLAN.md");
        fs::write(&plan_path, sample_plan()).unwrap();

        assert!(generate(&plan_path, cwd).is_none());
    }

    #[test]
    fn test_generate_missing_plan() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, true, false);

        let plan_path = cwd.join("NONEXISTENT.md");
        assert!(generate(&plan_path, cwd).is_none());
    }

    #[test]
    fn test_execute_cli() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, true, false);

        let plan_path = cwd.join("PLAN.md");
        fs::write(&plan_path, sample_plan()).unwrap();

        let args = vec![
            "yolo".to_string(),
            "generate-contract".to_string(),
            "PLAN.md".to_string(),
        ];
        let (output, code) = execute(&args, cwd).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("2-11.json"));
    }

    #[test]
    fn test_execute_missing_args() {
        let tmp = TempDir::new().unwrap();
        let result = execute(
            &["yolo".to_string(), "generate-contract".to_string()],
            tmp.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_v2_hash_deterministic() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_config(cwd, false, true);

        let plan_path = cwd.join("PLAN.md");
        fs::write(&plan_path, sample_plan()).unwrap();

        let (c1, _) = generate(&plan_path, cwd).unwrap();
        let (c2, _) = generate(&plan_path, cwd).unwrap();
        assert_eq!(
            c1["contract_hash"].as_str().unwrap(),
            c2["contract_hash"].as_str().unwrap()
        );
    }
}
