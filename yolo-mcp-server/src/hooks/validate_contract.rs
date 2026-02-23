use crate::commands::feature_flags::{self, FeatureFlag};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

use super::types::ContractValidationInput;

/// Validates a task against its contract sidecar.
///
/// Modes:
/// - `start`: verify task in range (1..task_count), verify SHA-256 hash integrity (v2_hard_contracts)
/// - `end`: check modified files against allowed_paths and forbidden_paths
///
/// V3 Lite (v3_contract_lite): advisory only, exit 0
/// V2 Hard (v2_hard_contracts): hard stop, exit 2 on violation
pub fn validate_contract(
    mode: &str,
    contract_path: &str,
    task_num: u32,
    modified_files: &[String],
) -> (String, i32) {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let v3_lite = feature_flags::is_enabled(FeatureFlag::V3ContractLite, &cwd);
    let v2_hard = feature_flags::is_enabled(FeatureFlag::V2HardContracts, &cwd);

    if !v3_lite && !v2_hard {
        return (String::new(), 0);
    }

    // Validate contract file exists
    if !Path::new(contract_path).exists() {
        let msg = format!("V2 contract: contract file not found: {}", contract_path);
        if v2_hard {
            return (msg, 2);
        }
        return (msg, 0);
    }

    let contract_content = match fs::read_to_string(contract_path) {
        Ok(c) => c,
        Err(_) => return ("V2 contract: cannot read contract file".to_string(), 0),
    };

    let contract: Value = match serde_json::from_str(&contract_content) {
        Ok(v) => v,
        Err(_) => return ("V2 contract: invalid JSON in contract file".to_string(), 0),
    };

    match mode {
        "start" => validate_start(&contract, task_num, v2_hard),
        "end" => validate_end(&contract, task_num, modified_files, v2_hard),
        _ => (format!("Unknown mode: {}. Valid: start, end", mode), 0),
    }
}

fn validate_start(contract: &Value, task_num: u32, v2_hard: bool) -> (String, i32) {
    let task_count = contract
        .get("task_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as u32;

    let phase = contract
        .get("phase")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);

    // Verify task number is within range
    if task_num < 1 || task_num > task_count {
        let detail = format!("Task {} outside contract range 1-{}", task_num, task_count);
        emit_violation("task_range", &detail, phase);
        if v2_hard {
            return (format!("V2 contract violation (task_range): {}", detail), 2);
        }
        return (format!("V2 contract violation (task_range): {}", detail), 0);
    }

    // V2: verify contract hash integrity
    if v2_hard
        && let Some(stored_hash) = contract.get("contract_hash").and_then(|v| v.as_str())
        && !stored_hash.is_empty()
    {
        // Recompute hash from contract body excluding contract_hash field
        let mut contract_clone = contract.clone();
        if let Some(obj) = contract_clone.as_object_mut() {
            obj.remove("contract_hash");
        }
        let contract_bytes = serde_json::to_string(&contract_clone).unwrap_or_default();
        let computed_hash = sha256_hex(&contract_bytes);

        if stored_hash != computed_hash {
            let detail = format!(
                "Contract hash mismatch: stored={}... computed={}...",
                &stored_hash[..stored_hash.len().min(16)],
                &computed_hash[..computed_hash.len().min(16)]
            );
            emit_violation("hash_mismatch", &detail, phase);
            return (
                format!("V2 contract violation (hash_mismatch): {}", detail),
                2,
            );
        }
    }

    (String::new(), 0)
}

fn validate_end(
    contract: &Value,
    _task_num: u32,
    modified_files: &[String],
    v2_hard: bool,
) -> (String, i32) {
    let phase = contract
        .get("phase")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);

    let allowed_paths: Vec<String> = contract
        .get("allowed_paths")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(normalize_path))
                .collect()
        })
        .unwrap_or_default();

    let forbidden_paths: Vec<String> = if v2_hard {
        contract
            .get("forbidden_paths")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(normalize_path))
                    .collect()
            })
            .unwrap_or_default()
    } else {
        Vec::new()
    };

    let mut violations = Vec::new();

    for file in modified_files {
        if file.is_empty() {
            continue;
        }
        let norm_file = normalize_path(file);

        // Check forbidden paths first (hard stop)
        for forbidden in &forbidden_paths {
            if norm_file == *forbidden || norm_file.starts_with(&format!("{}/", forbidden)) {
                let detail = format!("{} matches forbidden path {}", norm_file, forbidden);
                emit_violation("forbidden_path", &detail, phase);
                if v2_hard {
                    return (
                        format!("V2 contract violation (forbidden_path): {}", detail),
                        2,
                    );
                }
                violations.push(detail);
            }
        }

        // Check allowed paths
        let found = allowed_paths.contains(&norm_file);

        if !found {
            let detail = format!("{} not in allowed_paths", norm_file);
            emit_violation("out_of_scope", &detail, phase);
            if v2_hard {
                return (
                    format!("V2 contract violation (out_of_scope): {}", detail),
                    2,
                );
            }
            violations.push(detail);
        }
    }

    if violations.is_empty() {
        (String::new(), 0)
    } else {
        (violations.join("; "), 0)
    }
}

fn normalize_path(path: &str) -> String {
    path.strip_prefix("./").unwrap_or(path).to_string()
}

fn sha256_hex(data: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn emit_violation(violation_type: &str, detail: &str, phase: u64) {
    // Metric collection: fail-open, no external dependencies.
    // When the metrics module is wired in, this will call it directly.
    eprintln!(
        "V2 contract violation ({}): {} [phase={}]",
        violation_type, detail, phase
    );
}

/// Hook entry point: wraps validate_contract for use from the hook dispatcher.
/// Takes hook JSON input, extracts mode/contract_path/task_num/files from it.
pub fn validate_contract_hook(input: &Value) -> (Value, i32) {
    let typed = ContractValidationInput::from_value(input);
    let mode = typed.mode.as_deref().unwrap_or("start");
    let contract_path = typed.contract_path.as_deref().unwrap_or("");
    let task_num = typed.task_number.unwrap_or(0);
    let modified_files = typed.modified_files.unwrap_or_default();

    let (msg, code) = validate_contract(mode, contract_path, task_num, &modified_files);

    if msg.is_empty() {
        (Value::Null, code)
    } else {
        (
            json!({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": msg
                }
            }),
            code,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_contract(task_count: u32, allowed: &[&str], forbidden: &[&str]) -> Value {
        json!({
            "phase": 1,
            "plan": 1,
            "task_count": task_count,
            "allowed_paths": allowed,
            "forbidden_paths": forbidden
        })
    }

    #[test]
    fn test_start_valid_task() {
        let contract = make_contract(5, &[], &[]);
        let (msg, code) = validate_start(&contract, 3, false);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_start_task_out_of_range_high() {
        let contract = make_contract(5, &[], &[]);
        let (msg, _code) = validate_start(&contract, 6, false);
        assert!(msg.contains("task_range"));
    }

    #[test]
    fn test_start_task_zero() {
        let contract = make_contract(5, &[], &[]);
        let (msg, _code) = validate_start(&contract, 0, false);
        assert!(msg.contains("task_range"));
    }

    #[test]
    fn test_start_hard_mode_exits_2() {
        let contract = make_contract(5, &[], &[]);
        let (_msg, code) = validate_start(&contract, 10, true);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_start_hash_integrity_pass() {
        let mut contract = json!({"phase": 1, "plan": 1, "task_count": 3});
        let hash = sha256_hex(&serde_json::to_string(&contract).unwrap());
        contract
            .as_object_mut()
            .unwrap()
            .insert("contract_hash".to_string(), json!(hash));

        let (msg, code) = validate_start(&contract, 1, true);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_start_hash_integrity_fail() {
        let contract = json!({
            "phase": 1,
            "plan": 1,
            "task_count": 3,
            "contract_hash": "deadbeef0000000000000000000000000000000000000000000000000000dead"
        });
        let (_msg, code) = validate_start(&contract, 1, true);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_end_allowed_paths() {
        let contract = make_contract(5, &["src/main.rs", "src/lib.rs"], &[]);
        let files = vec!["src/main.rs".to_string()];
        let (msg, code) = validate_end(&contract, 1, &files, false);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_end_out_of_scope() {
        let contract = make_contract(5, &["src/main.rs"], &[]);
        let files = vec!["src/other.rs".to_string()];
        let (msg, _code) = validate_end(&contract, 1, &files, false);
        assert!(msg.contains("not in allowed_paths"));
    }

    #[test]
    fn test_end_out_of_scope_hard() {
        let contract = make_contract(5, &["src/main.rs"], &[]);
        let files = vec!["src/other.rs".to_string()];
        let (_msg, code) = validate_end(&contract, 1, &files, true);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_end_forbidden_path() {
        let contract = make_contract(5, &["src/main.rs"], &["secrets/"]);
        let files = vec!["secrets/key.pem".to_string()];
        let (_msg, code) = validate_end(&contract, 1, &files, true);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_end_forbidden_exact_match() {
        let contract = make_contract(5, &["src/main.rs"], &[".env"]);
        let files = vec![".env".to_string()];
        let (_msg, code) = validate_end(&contract, 1, &files, true);
        assert_eq!(code, 2);
    }

    #[test]
    fn test_normalize_path() {
        assert_eq!(normalize_path("./src/main.rs"), "src/main.rs");
        assert_eq!(normalize_path("src/main.rs"), "src/main.rs");
    }

    #[test]
    fn test_sha256_hex() {
        let hash = sha256_hex("hello");
        assert_eq!(hash.len(), 64);
        assert_eq!(
            hash,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn test_validate_contract_flags_off() {
        // When both flags are off (no config.json in cwd), should return empty/0
        let (msg, code) = validate_contract("start", "/nonexistent", 1, &[]);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_hook_entry_point() {
        let input = json!({
            "mode": "start",
            "contract_path": "/nonexistent/contract.json",
            "task_number": 1
        });
        let (_output, code) = validate_contract_hook(&input);
        assert!(code == 0 || code == 2);
    }

    #[test]
    fn test_end_normalizes_dotslash() {
        let contract = make_contract(5, &["src/main.rs"], &[]);
        let files = vec!["./src/main.rs".to_string()];
        let (msg, code) = validate_end(&contract, 1, &files, false);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_end_empty_files_skipped() {
        let contract = make_contract(5, &["src/main.rs"], &[]);
        let files = vec!["".to_string(), "src/main.rs".to_string()];
        let (msg, code) = validate_end(&contract, 1, &files, false);
        assert_eq!(code, 0);
        assert!(msg.is_empty());
    }

    #[test]
    fn test_end_multiple_violations_advisory() {
        let contract = make_contract(5, &["src/main.rs"], &[]);
        let files = vec!["src/a.rs".to_string(), "src/b.rs".to_string()];
        let (msg, code) = validate_end(&contract, 1, &files, false);
        assert_eq!(code, 0);
        assert!(msg.contains("src/a.rs"));
        assert!(msg.contains("src/b.rs"));
    }
}
