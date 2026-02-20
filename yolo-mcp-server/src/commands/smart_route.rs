use serde_json::json;
use std::fs;
use std::path::Path;

/// Determine whether an agent should be included or skipped based on effort.
/// When v3_smart_routing=true:
///   - Scout: skip for turbo/fast
///   - Architect: include only for thorough
///   - All others: always include
/// Output: JSON {"agent","decision","reason"}
/// Exit: 0 always — routing must never block execution.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // args: ["yolo", "smart-route", "<agent_role>", "<effort>"]
    if args.len() < 4 {
        let result = json!({
            "agent": "unknown",
            "decision": "include",
            "reason": "insufficient arguments"
        });
        return Ok((format!("{}\n", result), 0));
    }

    let agent_role = &args[2];
    let effort = &args[3];

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    // Check feature flag
    let smart_routing = read_bool_flag(&config_path, "v3_smart_routing");

    if !smart_routing {
        let result = json!({
            "agent": agent_role,
            "decision": "include",
            "reason": "smart_routing disabled"
        });
        return Ok((format!("{}\n", result), 0));
    }

    let (decision, reason) = route_agent(agent_role, effort);

    // Emit smart_route metric (best-effort, never fail)
    let data_pairs = vec![
        ("agent".to_string(), agent_role.clone()),
        ("effort".to_string(), effort.clone()),
        ("decision".to_string(), decision.to_string()),
    ];
    let _ = super::collect_metrics::collect("smart_route", "0", None, &data_pairs, cwd);

    let result = json!({
        "agent": agent_role,
        "decision": decision,
        "reason": reason
    });
    Ok((format!("{}\n", result), 0))
}

/// Core routing logic: decide include/skip for a given agent + effort.
pub fn route_agent(agent_role: &str, effort: &str) -> (&'static str, String) {
    match agent_role {
        "scout" => match effort {
            "turbo" | "fast" => ("skip", format!("effort={}: scout not needed", effort)),
            _ => ("include", format!("effort={}: scout included", effort)),
        },
        "architect" => match effort {
            "thorough" => ("include", format!("effort={}: architect included", effort)),
            _ => ("skip", format!("effort={}: architect only for thorough", effort)),
        },
        _ => ("include", format!("role={}: always included", agent_role)),
    }
}

/// Read a boolean flag from config.json. Returns false on any error.
fn read_bool_flag(config_path: &Path, key: &str) -> bool {
    let content = match fs::read_to_string(config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };
    let config: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };
    config.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scout_skip_turbo() {
        let (decision, _) = route_agent("scout", "turbo");
        assert_eq!(decision, "skip");
    }

    #[test]
    fn test_scout_skip_fast() {
        let (decision, _) = route_agent("scout", "fast");
        assert_eq!(decision, "skip");
    }

    #[test]
    fn test_scout_include_balanced() {
        let (decision, _) = route_agent("scout", "balanced");
        assert_eq!(decision, "include");
    }

    #[test]
    fn test_scout_include_thorough() {
        let (decision, _) = route_agent("scout", "thorough");
        assert_eq!(decision, "include");
    }

    #[test]
    fn test_architect_include_thorough() {
        let (decision, _) = route_agent("architect", "thorough");
        assert_eq!(decision, "include");
    }

    #[test]
    fn test_architect_skip_turbo() {
        let (decision, _) = route_agent("architect", "turbo");
        assert_eq!(decision, "skip");
    }

    #[test]
    fn test_architect_skip_fast() {
        let (decision, _) = route_agent("architect", "fast");
        assert_eq!(decision, "skip");
    }

    #[test]
    fn test_architect_skip_balanced() {
        let (decision, _) = route_agent("architect", "balanced");
        assert_eq!(decision, "skip");
    }

    #[test]
    fn test_dev_always_include() {
        let (decision, reason) = route_agent("dev", "turbo");
        assert_eq!(decision, "include");
        assert!(reason.contains("always included"));
    }

    #[test]
    fn test_lead_always_include() {
        let (decision, _) = route_agent("lead", "fast");
        assert_eq!(decision, "include");
    }

    #[test]
    fn test_qa_always_include() {
        let (decision, _) = route_agent("qa", "balanced");
        assert_eq!(decision, "include");
    }

    #[test]
    fn test_execute_missing_args() {
        let args: Vec<String> = vec!["yolo".into(), "smart-route".into()];
        let cwd = std::path::PathBuf::from(".");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
        assert_eq!(parsed["agent"], "unknown");
        assert_eq!(parsed["decision"], "include");
    }

    #[test]
    fn test_execute_routing_disabled() {
        // No config.json → smart_routing=false → always include
        let args: Vec<String> = vec![
            "yolo".into(),
            "smart-route".into(),
            "scout".into(),
            "turbo".into(),
        ];
        let cwd = std::path::PathBuf::from("/tmp/nonexistent-dir-smart-route-test");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
        assert_eq!(parsed["decision"], "include");
        assert_eq!(parsed["reason"], "smart_routing disabled");
    }
}
