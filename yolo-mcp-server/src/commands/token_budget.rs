use serde_json::{json, Value};
use std::fs;
use std::path::Path;

use super::{log_event, collect_metrics};

/// Default budgets per role (chars) when no config/token-budgets.json exists.
const DEFAULT_BUDGET: u64 = 32000;

/// Load token budget config from config/token-budgets.json relative to cwd.
fn load_budgets(cwd: &Path) -> Value {
    let budgets_path = cwd.join("config").join("token-budgets.json");
    if budgets_path.exists()
        && let Ok(content) = fs::read_to_string(&budgets_path)
        && let Ok(v) = serde_json::from_str::<Value>(&content)
    {
        return v;
    }
    json!({
        "budgets": {},
        "truncation_strategy": "head",
        "overage_action": "truncate_and_log"
    })
}

/// Check if v2_token_budgets is enabled in config.json.
fn is_enabled(cwd: &Path) -> bool {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    if config_path.exists()
        && let Ok(content) = fs::read_to_string(&config_path)
        && let Ok(config) = serde_json::from_str::<Value>(&content)
    {
        return config.get("v2_token_budgets").and_then(|v| v.as_bool()).unwrap_or(false);
    }
    false
}

/// Get the budget for a role. Checks per-task budget from contract metadata first,
/// then falls back to per-role budget from token-budgets.json, then DEFAULT_BUDGET.
fn resolve_budget(role: &str, budgets_config: &Value, contract: Option<&Value>) -> u64 {
    // Per-task budget from contract metadata
    if let Some(c) = contract
        && let Some(max) = c.get("max_token_budget").and_then(|v| v.as_u64())
        && max > 0
    {
        return max;
    }

    // Per-role fallback from token-budgets.json
    if let Some(role_budget) = budgets_config
        .get("budgets")
        .and_then(|b| b.get(role))
        .and_then(|r| r.get("max_chars"))
        .and_then(|v| v.as_u64())
    {
        return role_budget;
    }

    DEFAULT_BUDGET
}

/// Truncate content using head strategy with char boundary safety.
/// Returns (truncated_content, was_truncated, original_len).
fn truncate_head(content: &str, max_chars: u64) -> (String, bool, usize) {
    let original_len = content.len();
    let max = max_chars as usize;

    if original_len <= max {
        return (content.to_string(), false, original_len);
    }

    // Find a safe char boundary at or before max
    let mut end = max;
    while end > 0 && !content.is_char_boundary(end) {
        end -= 1;
    }

    let truncated = &content[..end];
    (truncated.to_string(), true, original_len)
}

/// Core budget check function callable from other Rust modules.
/// Returns (output_content, was_truncated, budget_used, budget_max).
pub fn check_budget(
    role: &str,
    content: &str,
    contract_path: Option<&Path>,
    cwd: &Path,
) -> (String, bool, u64, u64) {
    let budgets_config = load_budgets(cwd);

    // Load contract if path provided
    let contract: Option<Value> = contract_path.and_then(|p| {
        let full_path = if p.is_absolute() { p.to_path_buf() } else { cwd.join(p) };
        fs::read_to_string(&full_path).ok().and_then(|c| serde_json::from_str(&c).ok())
    });

    let budget = resolve_budget(role, &budgets_config, contract.as_ref());
    let (output, was_truncated, original_len) = truncate_head(content, budget);

    if was_truncated {
        let chars_over = original_len as i64 - budget as i64;
        // Log overage event
        let phase = "0"; // Budget checks happen outside specific phase context
        let data = vec![
            ("role".to_string(), role.to_string()),
            ("chars_total".to_string(), original_len.to_string()),
            ("chars_max".to_string(), budget.to_string()),
            ("chars_truncated".to_string(), chars_over.to_string()),
        ];
        let _ = log_event::log("token_overage", phase, None, &data, cwd);
        let _ = collect_metrics::collect("token_overage", phase, None, &data, cwd);
    }

    (output, was_truncated, content.len() as u64, budget)
}

/// CLI entry point: `yolo token-budget <role> [file]`
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // args[0] = "yolo", args[1] = "token-budget", args[2] = role, args[3] = file (optional)
    if args.len() < 3 {
        return Err("Usage: yolo token-budget <role> [file] [--contract=<path>]".to_string());
    }

    if !is_enabled(cwd) {
        return Ok((json!({"result": "skip", "reason": "v2_token_budgets=false"}).to_string(), 0));
    }

    let role = &args[2];

    // Parse optional flags
    let mut file_path: Option<String> = None;
    let mut contract_path: Option<String> = None;

    for arg in args.iter().skip(3) {
        if arg.starts_with("--contract=") {
            contract_path = Some(arg.replace("--contract=", ""));
        } else if file_path.is_none() {
            file_path = Some(arg.clone());
        }
    }

    // Read content from file or stdin
    let content = if let Some(ref fp) = file_path {
        let p = Path::new(fp);
        let full = if p.is_absolute() { p.to_path_buf() } else { cwd.join(p) };
        fs::read_to_string(&full).map_err(|e| format!("Failed to read {}: {}", full.display(), e))?
    } else {
        let mut buf = String::new();
        use std::io::Read;
        std::io::stdin().read_to_string(&mut buf).map_err(|e| format!("Failed to read stdin: {}", e))?;
        buf
    };

    let cp = contract_path.as_ref().map(|s| Path::new(s.as_str()));
    let (output, was_truncated, used, max) = check_budget(role, &content, cp, cwd);

    let result = json!({
        "result": if was_truncated { "truncated" } else { "within_budget" },
        "role": role,
        "chars_used": used,
        "chars_max": max,
        "was_truncated": was_truncated,
        "output_length": output.len(),
    });

    if was_truncated {
        // Print truncated content to stdout, result JSON to stderr for tooling
        eprintln!("{}", result);
        Ok((output, 0))
    } else {
        Ok((result.to_string(), 0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn setup_test_env(enabled: bool) -> TempDir {
        let dir = TempDir::new().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = json!({"v2_token_budgets": enabled, "v3_event_log": true});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();
        dir
    }

    fn setup_budgets(dir: &TempDir) {
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        let budgets = json!({
            "budgets": {
                "dev": {"max_chars": 100, "description": "test"},
                "lead": {"max_chars": 50, "description": "test"}
            },
            "truncation_strategy": "head",
            "overage_action": "truncate_and_log"
        });
        fs::write(config_dir.join("token-budgets.json"), budgets.to_string()).unwrap();
    }

    #[test]
    fn test_skip_when_disabled() {
        let dir = setup_test_env(false);
        let args = vec!["yolo".into(), "token-budget".into(), "dev".into()];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("v2_token_budgets=false"));
    }

    #[test]
    fn test_within_budget() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        let content = "short content";
        let (output, truncated, _, max) = check_budget("dev", content, None, dir.path());
        assert!(!truncated);
        assert_eq!(output, content);
        assert_eq!(max, 100);
    }

    #[test]
    fn test_truncation_head() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        let content = "a".repeat(200);
        let (output, truncated, _, max) = check_budget("dev", &content, None, dir.path());
        assert!(truncated);
        assert_eq!(output.len(), 100);
        assert_eq!(max, 100);
    }

    #[test]
    fn test_char_boundary_safety() {
        // Multi-byte character at boundary
        let (truncated, was_trunc, _) = truncate_head("hello\u{1F600}world", 7);
        assert!(was_trunc);
        // Should not split the emoji (4 bytes) - truncates to "hello" (5 bytes)
        assert!(truncated.len() <= 7);
        assert!(truncated.is_char_boundary(truncated.len()));
    }

    #[test]
    fn test_per_role_fallback() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        // "lead" has max_chars=50
        let content = "a".repeat(80);
        let (output, truncated, _, max) = check_budget("lead", &content, None, dir.path());
        assert!(truncated);
        assert_eq!(output.len(), 50);
        assert_eq!(max, 50);
    }

    #[test]
    fn test_default_budget_unknown_role() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        // "unknown" role falls back to DEFAULT_BUDGET (32000)
        let content = "a".repeat(100);
        let (_, truncated, _, max) = check_budget("unknown", &content, None, dir.path());
        assert!(!truncated);
        assert_eq!(max, DEFAULT_BUDGET);
    }

    #[test]
    fn test_contract_budget_override() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        let contract_path = dir.path().join("contract.json");
        let contract = json!({"max_token_budget": 30});
        fs::write(&contract_path, contract.to_string()).unwrap();

        let content = "a".repeat(50);
        let (output, truncated, _, max) = check_budget("dev", &content, Some(&contract_path), dir.path());
        assert!(truncated);
        assert_eq!(max, 30);
        assert_eq!(output.len(), 30);
    }

    #[test]
    fn test_overage_logging() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        let content = "a".repeat(200);
        let _ = check_budget("dev", &content, None, dir.path());

        // Check that metrics were logged
        let metrics_file = dir.path().join(".yolo-planning/.metrics/run-metrics.jsonl");
        assert!(metrics_file.exists());
        let metrics_content = fs::read_to_string(&metrics_file).unwrap();
        assert!(metrics_content.contains("token_overage"));
    }

    #[test]
    fn test_missing_args() {
        let dir = setup_test_env(true);
        let args = vec!["yolo".into(), "token-budget".into()];
        assert!(execute(&args, dir.path()).is_err());
    }

    #[test]
    fn test_execute_with_file() {
        let dir = setup_test_env(true);
        setup_budgets(&dir);
        let test_file = dir.path().join("input.txt");
        fs::write(&test_file, "short").unwrap();

        let args = vec![
            "yolo".into(), "token-budget".into(), "dev".into(),
            test_file.to_str().unwrap().into(),
        ];
        let (out, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("within_budget"));
    }
}
