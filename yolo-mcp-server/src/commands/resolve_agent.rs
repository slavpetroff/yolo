use serde_json::{json, Value};
use std::path::Path;
use std::time::Instant;

use crate::commands::{resolve_model, resolve_turns};

fn s(v: &str) -> String {
    v.to_string()
}

const AGENTS: &[&str] = &[
    "lead", "dev", "qa", "scout", "debugger", "architect", "docs", "researcher", "reviewer",
];

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    let all_flag = args.iter().any(|a| a == "--all");
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();

    if all_flag {
        // --all mode: yolo resolve-agent --all <config> <profiles> [effort]
        if positional.len() < 4 {
            return Err(
                "Usage: yolo resolve-agent --all <config-path> <profiles-path> [effort]"
                    .to_string(),
            );
        }
        let config_path = positional[2].clone();
        let profiles_path = positional[3].clone();
        let effort = if positional.len() > 4 {
            positional[4].clone()
        } else {
            "balanced".to_string()
        };

        let mut agents_map = serde_json::Map::new();
        let mut all_ok = true;

        for &agent in AGENTS {
            let model_result = resolve_model::execute(
                &[s("yolo"), s("resolve-model"), s(agent), config_path.clone(), profiles_path.clone()],
                cwd,
            );
            let turns_result = resolve_turns::execute(
                &[s("yolo"), s("resolve-turns"), s(agent), config_path.clone(), effort.clone()],
                cwd,
            );

            match (model_result, turns_result) {
                (Ok((model_out, 0)), Ok((turns_out, 0))) => {
                    let model = model_out.trim().to_string();
                    let turns: u64 = turns_out.trim().parse().unwrap_or(0);
                    agents_map.insert(
                        agent.to_string(),
                        json!({"model": model, "turns": turns}),
                    );
                }
                (model_r, turns_r) => {
                    all_ok = false;
                    let model_err = match model_r {
                        Ok((_, code)) if code != 0 => format!("exit code {}", code),
                        Err(e) => e,
                        _ => String::new(),
                    };
                    let turns_err = match turns_r {
                        Ok((_, code)) if code != 0 => format!("exit code {}", code),
                        Err(e) => e,
                        _ => String::new(),
                    };
                    let mut errs = Vec::new();
                    if !model_err.is_empty() {
                        errs.push(format!("model: {}", model_err));
                    }
                    if !turns_err.is_empty() {
                        errs.push(format!("turns: {}", turns_err));
                    }
                    agents_map.insert(
                        agent.to_string(),
                        json!({"error": errs.join("; ")}),
                    );
                }
            }
        }

        let response = json!({
            "ok": all_ok,
            "cmd": "resolve-agent",
            "delta": {
                "agents": Value::Object(agents_map),
                "count": AGENTS.len()
            },
            "elapsed_ms": start.elapsed().as_millis() as u64
        });

        return Ok((response.to_string(), if all_ok { 0 } else { 1 }));
    }

    // Single agent mode: yolo resolve-agent <agent> <config> <profiles> [effort]
    if positional.len() < 5 {
        return Err(
            "Usage: yolo resolve-agent <agent> <config-path> <profiles-path> [effort]".to_string(),
        );
    }

    let agent = positional[2].as_str();
    let config_path = positional[3].clone();
    let profiles_path = positional[4].clone();
    let effort = if positional.len() > 5 {
        positional[5].clone()
    } else {
        "balanced".to_string()
    };

    let (model_out, model_code) = resolve_model::execute(
        &[s("yolo"), s("resolve-model"), s(agent), config_path.clone(), profiles_path],
        cwd,
    )?;

    if model_code != 0 {
        let response = json!({
            "ok": false,
            "cmd": "resolve-agent",
            "error": format!("resolve-model failed for agent '{}'", agent),
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let (turns_out, turns_code) = resolve_turns::execute(
        &[s("yolo"), s("resolve-turns"), s(agent), config_path, effort],
        cwd,
    )?;

    if turns_code != 0 {
        let response = json!({
            "ok": false,
            "cmd": "resolve-agent",
            "error": format!("resolve-turns failed for agent '{}'", agent),
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let model = model_out.trim().to_string();
    let turns: u64 = turns_out.trim().parse().unwrap_or(0);

    let response = json!({
        "ok": true,
        "cmd": "resolve-agent",
        "delta": {
            "agent": agent,
            "model": model,
            "turns": turns
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn write_profiles(dir: &std::path::Path) -> String {
        let profiles = r#"{
  "quality": {
    "lead": "opus", "dev": "opus", "qa": "sonnet",
    "scout": "haiku", "debugger": "opus", "architect": "opus",
    "docs": "sonnet", "researcher": "sonnet", "reviewer": "opus"
  },
  "balanced": {
    "lead": "sonnet", "dev": "sonnet", "qa": "sonnet",
    "scout": "haiku", "debugger": "sonnet", "architect": "sonnet",
    "docs": "sonnet", "researcher": "haiku", "reviewer": "sonnet"
  }
}"#;
        let path = dir.join("profiles.json");
        fs::write(&path, profiles).unwrap();
        path.to_string_lossy().to_string()
    }

    fn write_config(dir: &std::path::Path, content: &str) -> String {
        let path = dir.join("config.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_single_agent() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let (out, code) = execute(
            &[s("yolo"), s("resolve-agent"), s("dev"), config, profiles],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["cmd"], "resolve-agent");
        assert_eq!(parsed["delta"]["agent"], "dev");
        assert_eq!(parsed["delta"]["model"], "opus");
        assert!(parsed["delta"]["turns"].is_number());
        assert!(parsed["elapsed_ms"].is_number());
    }

    #[test]
    fn test_all_agents() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let (out, code) = execute(
            &[s("yolo"), s("resolve-agent"), s("--all"), config, profiles],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["delta"]["count"], AGENTS.len());
        let agents = parsed["delta"]["agents"].as_object().unwrap();
        assert_eq!(agents.len(), AGENTS.len());
        for &agent in AGENTS {
            assert!(agents.contains_key(agent), "Missing agent: {}", agent);
            assert!(agents[agent]["model"].is_string());
            assert!(agents[agent]["turns"].is_number());
        }
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(&[s("yolo"), s("resolve-agent"), s("dev")], dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_response_schema() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let (out, _) = execute(
            &[s("yolo"), s("resolve-agent"), s("lead"), config, profiles],
            dir.path(),
        )
        .unwrap();
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["cmd"], "resolve-agent");
        assert!(parsed["elapsed_ms"].is_number());
    }

    #[test]
    fn test_effort_parameter() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let (out_balanced, _) = execute(
            &[s("yolo"), s("resolve-agent"), s("dev"), config.clone(), profiles.clone(), s("balanced")],
            dir.path(),
        )
        .unwrap();
        let (out_thorough, _) = execute(
            &[s("yolo"), s("resolve-agent"), s("dev"), config, profiles, s("thorough")],
            dir.path(),
        )
        .unwrap();

        let balanced: Value = serde_json::from_str(&out_balanced).unwrap();
        let thorough: Value = serde_json::from_str(&out_thorough).unwrap();
        // thorough should give more turns than balanced
        assert!(
            thorough["delta"]["turns"].as_u64().unwrap()
                >= balanced["delta"]["turns"].as_u64().unwrap()
        );
    }
}
