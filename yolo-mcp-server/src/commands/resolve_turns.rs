use std::fs;
use std::path::Path;

const VALID_AGENTS: &[&str] = &["lead", "dev", "qa", "scout", "debugger", "architect", "docs"];

fn default_base_turns(agent: &str) -> u32 {
    match agent {
        "scout" => 15,
        "qa" => 25,
        "architect" => 30,
        "debugger" => 80,
        "lead" => 50,
        "dev" => 75,
        "docs" => 30,
        _ => 0,
    }
}

fn normalize_effort(raw: &str) -> Option<String> {
    let lower = raw.to_lowercase();
    match lower.as_str() {
        "thorough" | "balanced" | "fast" | "turbo" => Some(lower),
        "high" => Some("thorough".to_string()),
        "medium" => Some("balanced".to_string()),
        "low" => Some("turbo".to_string()),
        "" => None,
        _ => None, // invalid effort silently returns None (matches bash behavior: returns 1 -> empty)
    }
}

fn legacy_effort_alias(effort: &str) -> &str {
    match effort {
        "thorough" => "high",
        "balanced" => "medium",
        "fast" => "medium",
        "turbo" => "low",
        _ => "medium",
    }
}

fn multiplier(effort: &str) -> (u32, u32) {
    match effort {
        "thorough" => (3, 2), // 1.5x
        "balanced" => (1, 1), // 1.0x
        "fast" => (4, 5),     // 0.8x
        "turbo" => (3, 5),    // 0.6x
        _ => (1, 1),
    }
}

/// Normalize a turn value. Returns:
/// - Some(0) for false/FALSE/False/0/negative
/// - Some(n) for valid positive integer
/// - None for null/empty/non-numeric
fn normalize_turn_value(value: &serde_json::Value) -> Option<u32> {
    match value {
        serde_json::Value::Bool(false) => Some(0),
        serde_json::Value::String(s) => {
            let s = s.trim();
            match s {
                "false" | "FALSE" | "False" => Some(0),
                "null" | "" => None,
                _ => {
                    if let Ok(n) = s.parse::<i64>() {
                        if n <= 0 { Some(0) } else { Some(n as u32) }
                    } else {
                        None
                    }
                }
            }
        }
        serde_json::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                if i <= 0 { Some(0) } else { Some(i as u32) }
            } else if let Some(f) = n.as_f64() {
                if f <= 0.0 { Some(0) } else { Some(f as u32) }
            } else {
                None
            }
        }
        serde_json::Value::Bool(true) => None,
        serde_json::Value::Null => None,
        _ => None,
    }
}

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    // args[0] = "yolo", args[1] = "resolve-turns", args[2..] = actual args
    // Required: agent-name, config-path. Optional: effort
    if args.len() < 4 || args.len() > 5 {
        return Err("Usage: yolo resolve-turns <agent-name> <config-path> [effort]".to_string());
    }

    let agent = &args[2];
    let config_path = Path::new(&args[3]);
    let effort_input = if args.len() > 4 { &args[4] } else { "" };

    // Validate agent
    if !VALID_AGENTS.contains(&agent.as_str()) {
        return Err(format!(
            "Invalid agent name '{}'. Valid: lead, dev, qa, scout, debugger, architect, docs",
            agent
        ));
    }

    // Read config if valid
    let config: Option<serde_json::Value> = if config_path.exists() {
        fs::read_to_string(config_path)
            .ok()
            .and_then(|c| serde_json::from_str(&c).ok())
    } else {
        None
    };

    // Resolve effort: explicit arg -> config.effort -> "balanced"
    let mut effort = normalize_effort(effort_input);

    if effort.is_none()
        && let Some(ref cfg) = config
        && let Some(cfg_effort) = cfg.get("effort").and_then(|v| v.as_str())
    {
        effort = normalize_effort(cfg_effort);
    }

    let effort = effort.unwrap_or_else(|| "balanced".to_string());
    let legacy = legacy_effort_alias(&effort);

    // Check for configured value
    if let Some(ref cfg) = config {
        // Try agent_max_turns first, then max_turns
        let configured_node = cfg
            .get("agent_max_turns")
            .and_then(|v| v.get(agent.as_str()))
            .or_else(|| cfg.get("max_turns").and_then(|v| v.get(agent.as_str())));

        if let Some(node) = configured_node {
            // Object mode: per-effort values (no multiplier applied)
            if node.is_object() {
                // Try: effort, legacy, balanced, medium (fallback chain)
                let candidates = [effort.as_str(), legacy, "balanced", "medium"];
                for key in &candidates {
                    if let Some(val) = node.get(*key)
                        && let Some(turns) = normalize_turn_value(val)
                    {
                        return Ok((format!("{}\n", turns), 0));
                    }
                }
                // Object exists but no matching key — fall through to scalar/default
            } else {
                // Scalar mode: apply multiplier
                if let Some(base) = normalize_turn_value(node) {
                    if base == 0 {
                        return Ok(("0\n".to_string(), 0));
                    }
                    let (num, den) = multiplier(&effort);
                    let resolved = (base * num + den / 2) / den;
                    let resolved = resolved.max(1);
                    return Ok((format!("{}\n", resolved), 0));
                }
                // null/empty — fall through to default
            }
        }
    }

    // Default base turns
    let base = default_base_turns(agent);
    if base == 0 {
        return Ok(("0\n".to_string(), 0));
    }

    let (num, den) = multiplier(&effort);
    let resolved = (base * num + den / 2) / den;
    let resolved = resolved.max(1);

    Ok((format!("{}\n", resolved), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn write_config(dir: &Path, content: &str) -> String {
        let path = dir.join("config.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_default_turns_dev_balanced() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        let (out, code) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "75");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_default_turns_scout() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "scout".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "15");
    }

    #[test]
    fn test_thorough_multiplier() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // dev=75, thorough=1.5x -> (75*3 + 1) / 2 = 113
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "thorough".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "113");
    }

    #[test]
    fn test_turbo_multiplier() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // dev=75, turbo=0.6x -> (75*3 + 2) / 5 = 45
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "turbo".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "45");
    }

    #[test]
    fn test_fast_multiplier() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // dev=75, fast=0.8x -> (75*4 + 2) / 5 = 60
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "fast".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "60");
    }

    #[test]
    fn test_legacy_effort_high() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // high -> thorough -> 1.5x on scout=15 -> (15*3+1)/2 = 23
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "scout".into(), config, "high".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "23");
    }

    #[test]
    fn test_object_mode() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": {
                "dev": { "thorough": 200, "balanced": 100, "fast": 50, "turbo": 25 }
            }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config.clone(), "thorough".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "200");

        let (out2, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "turbo".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out2.trim(), "25");
    }

    #[test]
    fn test_false_unlimited() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": { "dev": false }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "0");
    }

    #[test]
    fn test_invalid_agent() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        let result = execute(
            &["yolo".into(), "resolve-turns".into(), "invalid".into(), config],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid agent name"));
    }

    #[test]
    fn test_effort_fallback_to_config() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{"effort": "thorough"}"#);

        // No explicit effort -> reads config.effort -> thorough
        // scout=15, thorough=1.5x -> 23
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "scout".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "23");
    }

    #[test]
    fn test_config_scalar_with_multiplier() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": { "dev": 100 }
        }"#);

        // dev overridden to 100, balanced=1.0x -> 100
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config.clone()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "100");

        // turbo=0.6x on 100 -> (100*3+2)/5 = 60
        let (out2, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "turbo".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out2.trim(), "60");
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_min_1_clamp() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": { "scout": 1 }
        }"#);

        // scout=1, turbo=0.6x -> (1*3+2)/5 = 1 (clamped to 1)
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "scout".into(), config, "turbo".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "1");
    }

    #[test]
    fn test_all_agents_have_defaults() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        for agent in VALID_AGENTS {
            let (out, code) = execute(
                &["yolo".into(), "resolve-turns".into(), agent.to_string(), config.clone()],
                dir.path(),
            ).unwrap();
            assert_eq!(code, 0);
            let turns: u32 = out.trim().parse().unwrap();
            assert!(turns > 0, "Agent {} should have positive default turns", agent);
        }
    }

    #[test]
    fn test_max_turns_fallback_key() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "max_turns": { "dev": 50 }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "50");
    }

    #[test]
    fn test_zero_scalar_unlimited() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": { "dev": 0 }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "0");
    }

    #[test]
    fn test_legacy_effort_low_maps_to_turbo() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // low -> turbo -> 0.6x on dev=75 -> 45
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "low".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "45");
    }

    #[test]
    fn test_legacy_effort_medium_maps_to_balanced() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // medium -> balanced -> 1.0x on dev=75 -> 75
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "medium".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "75");
    }

    #[test]
    fn test_missing_config_uses_defaults() {
        let dir = tempdir().unwrap();

        // Config file doesn't exist - should still work with defaults
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), "/nonexistent/config.json".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "75");
    }

    #[test]
    fn test_empty_config_effort_falls_back_to_balanced() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{"effort": ""}"#);

        // Empty effort -> falls back to balanced -> 1.0x on dev=75 -> 75
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "75");
    }

    #[test]
    fn test_object_mode_legacy_fallback() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{
            "agent_max_turns": {
                "dev": { "high": 200, "medium": 100, "low": 50 }
            }
        }"#);

        // thorough -> tries "thorough" (miss) -> tries legacy "high" (hit) -> 200
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "dev".into(), config, "thorough".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "200");
    }

    #[test]
    fn test_thorough_rounding_architect() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        // architect=30, thorough=1.5x -> (30*3 + 2/2)/2 = (90+1)/2 = 45
        let (out, _) = execute(
            &["yolo".into(), "resolve-turns".into(), "architect".into(), config, "thorough".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "45");
    }
}
