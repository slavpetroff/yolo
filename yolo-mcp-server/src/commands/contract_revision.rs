use serde_json::Value;
use std::fs;
use std::path::Path;

use super::{collect_metrics, generate_contract, log_event};

/// Core contract revision logic.
/// Compares old contract hash to newly generated contract.
/// If different, archives old as .revN.json and logs the event.
/// Returns: "no_change", "revised:{archive_path}", or "" on skip.
pub fn revise(old_contract_path: &Path, plan_path: &Path, cwd: &Path) -> String {
    // Check v2_hard_contracts flag
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if config_path.exists()
        && let Ok(config_str) = fs::read_to_string(&config_path)
        && let Ok(config) = serde_json::from_str::<Value>(&config_str) {
            let enabled = config
                .get("v2_hard_contracts")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            if !enabled {
                return String::new();
            }
        }

    if !old_contract_path.exists() || !plan_path.exists() {
        return String::new();
    }

    // Read old contract hash
    let old_hash = match fs::read_to_string(old_contract_path) {
        Ok(s) => match serde_json::from_str::<Value>(&s) {
            Ok(v) => v
                .get("contract_hash")
                .and_then(|h| h.as_str())
                .unwrap_or("")
                .to_string(),
            Err(_) => return String::new(),
        },
        Err(_) => return String::new(),
    };

    if old_hash.is_empty() {
        return String::new();
    }

    // Generate new contract
    let new_result = generate_contract::generate(plan_path, cwd);
    let (new_contract, _new_path) = match new_result {
        Some(pair) => pair,
        None => return String::new(),
    };

    let new_hash = new_contract
        .get("contract_hash")
        .and_then(|h| h.as_str())
        .unwrap_or("")
        .to_string();

    if old_hash == new_hash {
        return "no_change".to_string();
    }

    // Archive old contract as .revN.json
    let contract_dir = match old_contract_path.parent() {
        Some(d) => d,
        None => return String::new(),
    };
    let base = old_contract_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("contract");

    let mut rev = 1;
    loop {
        let archive_name = format!("{}.rev{}.json", base, rev);
        let archive_path = contract_dir.join(&archive_name);
        if !archive_path.exists() {
            // Copy old contract to archive
            let _ = fs::copy(old_contract_path, &archive_path);

            // Extract phase/plan for logging
            let phase = new_contract
                .get("phase")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);
            let plan = new_contract
                .get("plan")
                .and_then(|v| v.as_u64())
                .unwrap_or(0);

            let phase_str = phase.to_string();
            let plan_str = plan.to_string();
            let rev_str = rev.to_string();
            let old_short = if old_hash.len() >= 16 {
                &old_hash[..16]
            } else {
                &old_hash
            };
            let new_short = if new_hash.len() >= 16 {
                &new_hash[..16]
            } else {
                &new_hash
            };

            let data_pairs = vec![
                ("old_hash".to_string(), old_short.to_string()),
                ("new_hash".to_string(), new_short.to_string()),
                ("revision".to_string(), rev_str),
            ];

            // Log event
            let _ = log_event::log(
                "contract_revision",
                &phase_str,
                Some(&plan_str),
                &data_pairs,
                cwd,
            );

            // Collect metrics
            let _ = collect_metrics::collect(
                "contract_revision",
                &phase_str,
                Some(&plan_str),
                &data_pairs,
                cwd,
            );

            return format!("revised:{}", archive_path.to_string_lossy());
        }
        rev += 1;
    }
}

/// CLI entry point: `yolo contract-revision <old-contract-path> <plan-path>`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err("Usage: yolo contract-revision <old-contract-path> <plan-path>".to_string());
    }

    let old_contract_path = cwd.join(&args[2]);
    let plan_path = cwd.join(&args[3]);
    let result = revise(&old_contract_path, &plan_path, cwd);
    Ok((result, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tempfile::TempDir;

    fn setup_v2_config(dir: &Path) {
        let planning = dir.join(".yolo-planning");
        std::fs::create_dir_all(&planning).unwrap();
        let config = json!({
            "v2_hard_contracts": true,
            "v3_event_log": false,
            "max_token_budget": 40000,
            "task_timeout_seconds": 300,
        });
        std::fs::write(planning.join("config.json"), config.to_string()).unwrap();
    }

    fn sample_plan() -> String {
        r#"---
phase: 3
plan: 5
title: "Test revision"
must_haves:
  - "item1"
depends_on: [1]
verification_checks:
  - "test passes"
forbidden_paths:
  - "secrets/"
---
## Task 1: Do something
**Files:** `src/foo.rs` (new)
"#
        .to_string()
    }

    #[test]
    fn test_no_change_when_same_plan() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        // Generate initial contract
        let plan_path = cwd.join("PLAN.md");
        std::fs::write(&plan_path, sample_plan()).unwrap();
        let (contract, _) = generate_contract::generate(&plan_path, cwd).unwrap();

        // The contract was written to .yolo-planning/.contracts/3-5.json
        let contract_path = cwd.join(".yolo-planning/.contracts/3-5.json");
        assert!(contract_path.exists());

        // Revise with same plan => no_change
        let result = revise(&contract_path, &plan_path, cwd);
        assert_eq!(result, "no_change");
    }

    #[test]
    fn test_revision_detected_on_change() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        // Generate initial contract
        let plan_path = cwd.join("PLAN.md");
        std::fs::write(&plan_path, sample_plan()).unwrap();
        let _ = generate_contract::generate(&plan_path, cwd).unwrap();

        let contract_path = cwd.join(".yolo-planning/.contracts/3-5.json");

        // Now change the plan
        let modified_plan = sample_plan().replace(
            "## Task 1: Do something",
            "## Task 1: Do something\n\n## Task 2: Extra task\n**Files:** `src/bar.rs` (new)",
        );
        std::fs::write(&plan_path, &modified_plan).unwrap();

        let result = revise(&contract_path, &plan_path, cwd);
        assert!(result.starts_with("revised:"), "Expected revised, got: {}", result);
        assert!(result.contains(".rev1.json"));

        // Archive file should exist
        let archive = cwd.join(".yolo-planning/.contracts/3-5.rev1.json");
        assert!(archive.exists());
    }

    #[test]
    fn test_skip_when_not_enabled() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        let planning = cwd.join(".yolo-planning");
        std::fs::create_dir_all(&planning).unwrap();
        let config = json!({"v2_hard_contracts": false});
        std::fs::write(planning.join("config.json"), config.to_string()).unwrap();

        let contract = cwd.join("contract.json");
        std::fs::write(&contract, "{}").unwrap();
        let plan = cwd.join("PLAN.md");
        std::fs::write(&plan, sample_plan()).unwrap();

        let result = revise(&contract, &plan, cwd);
        assert!(result.is_empty());
    }

    #[test]
    fn test_skip_missing_old_contract() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        let contract = cwd.join("nonexistent.json");
        let plan = cwd.join("PLAN.md");
        std::fs::write(&plan, sample_plan()).unwrap();

        let result = revise(&contract, &plan, cwd);
        assert!(result.is_empty());
    }

    #[test]
    fn test_skip_empty_hash() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        // Old contract without hash
        let contract = cwd.join(".yolo-planning/.contracts/3-5.json");
        std::fs::create_dir_all(contract.parent().unwrap()).unwrap();
        std::fs::write(&contract, json!({"phase": 3, "plan": 5}).to_string()).unwrap();

        let plan = cwd.join("PLAN.md");
        std::fs::write(&plan, sample_plan()).unwrap();

        let result = revise(&contract, &plan, cwd);
        assert!(result.is_empty());
    }

    #[test]
    fn test_multiple_revisions() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        let plan_path = cwd.join("PLAN.md");
        std::fs::write(&plan_path, sample_plan()).unwrap();
        let _ = generate_contract::generate(&plan_path, cwd).unwrap();
        let contract_path = cwd.join(".yolo-planning/.contracts/3-5.json");

        // First revision
        let plan_v2 = sample_plan().replace("item1", "item1_changed");
        std::fs::write(&plan_path, &plan_v2).unwrap();
        let r1 = revise(&contract_path, &plan_path, cwd);
        assert!(r1.contains(".rev1.json"));

        // Second revision
        let plan_v3 = plan_v2.replace("item1_changed", "item1_changed_again");
        std::fs::write(&plan_path, &plan_v3).unwrap();
        let r2 = revise(&contract_path, &plan_path, cwd);
        assert!(r2.contains(".rev2.json"));
    }

    #[test]
    fn test_execute_cli() {
        let tmp = TempDir::new().unwrap();
        let cwd = tmp.path();
        setup_v2_config(cwd);

        let plan_path = cwd.join("PLAN.md");
        std::fs::write(&plan_path, sample_plan()).unwrap();
        let _ = generate_contract::generate(&plan_path, cwd).unwrap();

        let args = vec![
            "yolo".to_string(),
            "contract-revision".to_string(),
            ".yolo-planning/.contracts/3-5.json".to_string(),
            "PLAN.md".to_string(),
        ];
        let (output, code) = execute(&args, cwd).unwrap();
        assert_eq!(code, 0);
        assert_eq!(output, "no_change");
    }

    #[test]
    fn test_execute_missing_args() {
        let tmp = TempDir::new().unwrap();
        let result = execute(
            &["yolo".to_string(), "contract-revision".to_string()],
            tmp.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }
}
