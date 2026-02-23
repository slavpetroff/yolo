use std::fs;
use std::path::Path;

const VALID_AGENTS: &[&str] = &["lead", "dev", "qa", "scout", "debugger", "architect", "docs", "researcher", "reviewer"];
const VALID_MODELS: &[&str] = &["opus", "sonnet", "haiku"];

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    // Detect flags
    let with_cost = args.iter().any(|a| a == "--with-cost");
    let all_agents = args.iter().any(|a| a == "--all");
    // Filter out flags for positional arg parsing
    let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();

    // args[0] = "yolo", args[1] = "resolve-model"
    // --all mode: positional[2] = config-path, positional[3] = profiles-path
    // normal mode: positional[2] = agent, positional[3] = config-path, positional[4] = profiles-path
    let required = if all_agents { 4 } else { 5 };
    if positional.len() < required {
        if all_agents {
            return Err("Usage: yolo resolve-model --all <config-path> <profiles-path>".to_string());
        }
        return Err("Usage: yolo resolve-model <agent-name> <config-path> <profiles-path>".to_string());
    }

    let (config_path, profiles_path) = if all_agents {
        (Path::new(positional[2].as_str()), Path::new(positional[3].as_str()))
    } else {
        (Path::new(positional[3].as_str()), Path::new(positional[4].as_str()))
    };

    // Validate single agent name (non --all mode)
    if !all_agents {
        let agent = positional[2].as_str();
        if !VALID_AGENTS.contains(&agent) {
            return Err(format!(
                "Invalid agent name '{}'. Valid: lead, dev, qa, scout, debugger, architect, docs, researcher, reviewer",
                agent
            ));
        }
    }

    // Validate config file exists
    if !config_path.exists() {
        return Err(format!(
            "Config not found at {}. Run /yolo:init first.",
            config_path.display()
        ));
    }

    // Validate profiles file exists
    if !profiles_path.exists() {
        return Err(format!(
            "Model profiles not found at {}. Plugin installation issue.",
            profiles_path.display()
        ));
    }

    // Session-level cache using file mtime + path hash for isolation
    let config_mtime = get_mtime(config_path);
    let path_hash = simple_hash(&config_path.to_string_lossy());

    if all_agents {
        let cache_tag = if with_cost { "ALL-COST" } else { "ALL" };
        let cache_file = format!("/tmp/yolo-model-{}-{}-{}", cache_tag, config_mtime, path_hash);
        if let Ok(cached) = fs::read_to_string(&cache_file) {
            let trimmed = cached.trim().to_string();
            if !trimmed.is_empty() {
                return Ok((format!("{}\n", trimmed), 0));
            }
        }

        // Read config + profiles
        let (config, profiles, profile_name) = load_config_and_profiles(config_path, profiles_path)?;

        // Build JSON object for all agents
        let mut map = serde_json::Map::new();
        for &agent in VALID_AGENTS {
            let model = resolve_agent_model(agent, &config, &profiles, &profile_name)?;
            if with_cost {
                let mut inner = serde_json::Map::new();
                inner.insert("model".to_string(), serde_json::Value::String(model.clone()));
                inner.insert("cost_weight".to_string(), serde_json::Value::Number(cost_weight(&model).into()));
                map.insert(agent.to_string(), serde_json::Value::Object(inner));
            } else {
                map.insert(agent.to_string(), serde_json::Value::String(model));
            }
        }
        let result = serde_json::to_string(&serde_json::Value::Object(map))
            .map_err(|e| format!("JSON serialization error: {}", e))?;
        let _ = fs::write(&cache_file, &result);
        return Ok((format!("{}\n", result), 0));
    }

    // Single agent mode
    let agent = positional[2].as_str();
    let cache_tag = if with_cost { format!("{}-COST", agent) } else { agent.to_string() };
    let cache_file = format!("/tmp/yolo-model-{}-{}-{}", cache_tag, config_mtime, path_hash);
    if let Ok(cached) = fs::read_to_string(&cache_file) {
        let trimmed = cached.trim().to_string();
        if !trimmed.is_empty() {
            return Ok((format!("{}\n", trimmed), 0));
        }
    }

    let (config, profiles, profile_name) = load_config_and_profiles(config_path, profiles_path)?;
    let model = resolve_agent_model(agent, &config, &profiles, &profile_name)?;

    if with_cost {
        let mut map = serde_json::Map::new();
        map.insert("model".to_string(), serde_json::Value::String(model.clone()));
        map.insert("cost_weight".to_string(), serde_json::Value::Number(cost_weight(&model).into()));
        let result = serde_json::to_string(&serde_json::Value::Object(map))
            .map_err(|e| format!("JSON serialization error: {}", e))?;
        let _ = fs::write(&cache_file, &result);
        Ok((format!("{}\n", result), 0))
    } else {
        let _ = fs::write(&cache_file, &model);
        Ok((format!("{}\n", model), 0))
    }
}

fn load_config_and_profiles<'a>(
    config_path: &Path,
    profiles_path: &Path,
) -> Result<(serde_json::Value, serde_json::Value, String), String> {
    let config_content = fs::read_to_string(config_path)
        .map_err(|e| format!("Failed to read config: {}", e))?;
    let config: serde_json::Value = serde_json::from_str(&config_content)
        .map_err(|e| format!("Failed to parse config: {}", e))?;

    let profiles_content = fs::read_to_string(profiles_path)
        .map_err(|e| format!("Failed to read profiles: {}", e))?;
    let profiles: serde_json::Value = serde_json::from_str(&profiles_content)
        .map_err(|e| format!("Failed to parse profiles: {}", e))?;

    let profile_name = config
        .get("model_profile")
        .and_then(|v| v.as_str())
        .unwrap_or("quality")
        .to_string();

    if profiles.get(&profile_name).is_none() {
        return Err(format!(
            "Invalid model_profile '{}'. Valid: quality, balanced, budget",
            profile_name
        ));
    }

    Ok((config, profiles, profile_name))
}

fn resolve_agent_model(
    agent: &str,
    config: &serde_json::Value,
    profiles: &serde_json::Value,
    profile_name: &str,
) -> Result<String, String> {
    let mut model = profiles
        .get(profile_name)
        .and_then(|p| p.get(agent))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // Check for per-agent override in config.json
    if let Some(overrides) = config.get("model_overrides") {
        if let Some(override_val) = overrides.get(agent) {
            if let Some(s) = override_val.as_str() {
                if !s.is_empty() {
                    model = s.to_string();
                }
            }
        }
    }

    // Validate final model
    if !VALID_MODELS.contains(&model.as_str()) {
        return Err(format!(
            "Invalid model '{}' for {}. Valid: opus, sonnet, haiku",
            model, agent
        ));
    }

    Ok(model)
}

fn cost_weight(model: &str) -> u32 {
    match model {
        "opus" => 100,
        "sonnet" => 20,
        "haiku" => 2,
        _ => 0,
    }
}

fn simple_hash(s: &str) -> u64 {
    // FNV-1a hash for cache key uniqueness
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in s.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn get_mtime(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .map(|t| {
            t.duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0)
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn write_profiles(dir: &Path) -> String {
        let profiles = r#"{
  "quality": {
    "lead": "opus", "dev": "opus", "qa": "sonnet",
    "scout": "haiku", "debugger": "opus", "architect": "opus", "docs": "sonnet", "researcher": "sonnet", "reviewer": "opus"
  },
  "balanced": {
    "lead": "sonnet", "dev": "sonnet", "qa": "sonnet",
    "scout": "haiku", "debugger": "sonnet", "architect": "sonnet", "docs": "sonnet", "researcher": "haiku", "reviewer": "sonnet"
  },
  "budget": {
    "lead": "sonnet", "dev": "sonnet", "qa": "haiku",
    "scout": "haiku", "debugger": "sonnet", "architect": "sonnet", "docs": "sonnet", "researcher": "haiku", "reviewer": "sonnet"
  }
}"#;
        let path = dir.join("profiles.json");
        fs::write(&path, profiles).unwrap();
        path.to_string_lossy().to_string()
    }

    fn write_config(dir: &Path, content: &str) -> String {
        let path = dir.join("config.json");
        fs::write(&path, content).unwrap();
        path.to_string_lossy().to_string()
    }

    #[test]
    fn test_valid_agent_quality_profile() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let (out, code) = execute(
            &["yolo".into(), "resolve-model".into(), "lead".into(), config, profiles],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "opus");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_valid_agent_balanced_profile() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "balanced"}"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), config, profiles],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "sonnet");
    }

    #[test]
    fn test_default_profile_is_quality() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{}"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), config, profiles],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "opus");
    }

    #[test]
    fn test_invalid_agent() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{}"#);

        let result = execute(
            &["yolo".into(), "resolve-model".into(), "invalid".into(), config, profiles],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid agent name"));
    }

    #[test]
    fn test_missing_config() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());

        let result = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), "/nonexistent/config.json".into(), profiles],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Config not found"));
    }

    #[test]
    fn test_override_takes_precedence() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{
            "model_profile": "budget",
            "model_overrides": { "scout": "opus" }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-model".into(), "scout".into(), config, profiles],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "opus");
    }

    #[test]
    fn test_invalid_profile() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "nonexistent"}"#);

        let result = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), config, profiles],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid model_profile"));
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_budget_profile() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "budget"}"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-model".into(), "qa".into(), config, profiles],
            dir.path(),
        ).unwrap();
        assert_eq!(out.trim(), "haiku");
    }

    #[test]
    fn test_all_9_agents_quality() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{"model_profile": "quality"}"#);

        let expected = [
            ("lead", "opus"), ("dev", "opus"), ("qa", "sonnet"),
            ("scout", "haiku"), ("debugger", "opus"), ("architect", "opus"), ("docs", "sonnet"),
            ("researcher", "sonnet"), ("reviewer", "opus"),
        ];
        for (agent, model) in &expected {
            let (out, code) = execute(
                &["yolo".into(), "resolve-model".into(), agent.to_string(), config.clone(), profiles.clone()],
                dir.path(),
            ).unwrap();
            assert_eq!(out.trim(), *model, "Agent {} should resolve to {}", agent, model);
            assert_eq!(code, 0);
        }
    }

    #[test]
    fn test_missing_profiles_file() {
        let dir = tempdir().unwrap();
        let config = write_config(dir.path(), r#"{}"#);

        let result = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), config, "/nonexistent/profiles.json".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Model profiles not found"));
    }

    #[test]
    fn test_empty_override_ignored() {
        let dir = tempdir().unwrap();
        let profiles = write_profiles(dir.path());
        let config = write_config(dir.path(), r#"{
            "model_profile": "quality",
            "model_overrides": { "dev": "" }
        }"#);

        let (out, _) = execute(
            &["yolo".into(), "resolve-model".into(), "dev".into(), config, profiles],
            dir.path(),
        ).unwrap();
        // Empty override should be ignored, falls through to profile value
        assert_eq!(out.trim(), "opus");
    }
}
