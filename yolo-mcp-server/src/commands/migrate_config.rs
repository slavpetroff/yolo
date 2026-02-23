use serde_json::Value;
use std::fs;
use std::path::Path;

/// Migrate a YOLO config.json: rename legacy keys, ensure required keys, merge defaults.
/// Returns Ok(added_count) on success, Err on failure.
pub fn migrate_config(config_path: &Path, defaults_path: &Path) -> Result<usize, String> {
    // No project initialized yet — nothing to migrate.
    if !config_path.exists() {
        return Ok(0);
    }

    if !defaults_path.exists() {
        return Err(format!(
            "defaults.json not found: {}",
            defaults_path.display()
        ));
    }

    let defaults: Value = read_json(defaults_path)?;
    let mut config: Value = read_json(config_path)?;

    let defaults_obj = defaults
        .as_object()
        .ok_or("defaults.json is not a JSON object")?;
    let config_obj = config
        .as_object_mut()
        .ok_or("config.json is not a JSON object")?;

    // Count missing keys before merge
    let missing_before = defaults_obj
        .keys()
        .filter(|k| !config_obj.contains_key(*k))
        .count();

    // Rename legacy key: agent_teams -> prefer_teams
    if config_obj.contains_key("agent_teams") {
        if !config_obj.contains_key("prefer_teams") {
            let new_val = match config_obj.get("agent_teams") {
                Some(Value::Bool(true)) => Value::String("always".to_string()),
                _ => Value::String("auto".to_string()),
            };
            config_obj.insert("prefer_teams".to_string(), new_val);
        }
        config_obj.remove("agent_teams");
    }

    // Ensure required top-level keys
    if !config_obj.contains_key("model_profile") {
        config_obj.insert(
            "model_profile".to_string(),
            Value::String("quality".to_string()),
        );
    }
    if !config_obj.contains_key("model_overrides") {
        config_obj.insert(
            "model_overrides".to_string(),
            Value::Object(serde_json::Map::new()),
        );
    }
    if !config_obj.contains_key("prefer_teams") {
        config_obj.insert(
            "prefer_teams".to_string(),
            Value::String("always".to_string()),
        );
    }

    // Generic brownfield merge: defaults + config (config wins)
    let mut merged = defaults_obj.clone();
    for (k, v) in config_obj.iter() {
        merged.insert(k.clone(), v.clone());
    }

    let missing_after = defaults_obj
        .keys()
        .filter(|k| !merged.contains_key(*k))
        .count();
    let added = missing_before.saturating_sub(missing_after);

    let merged_val = Value::Object(merged);

    // Schema validation: validate merged config against config.schema.json
    let schema_path = defaults_path.with_file_name("config.schema.json");
    if schema_path.exists() {
        let schema = read_json(&schema_path)?;
        let validator = jsonschema::validator_for(&schema)
            .map_err(|e| format!("Invalid config schema: {e}"))?;
        let errors: Vec<String> = validator
            .iter_errors(&merged_val)
            .map(|e| format!("  - {}: {}", e.instance_path, e))
            .collect();
        if !errors.is_empty() {
            return Err(format!(
                "Config validation failed:\n{}",
                errors.join("\n")
            ));
        }
    } else {
        eprintln!(
            "WARNING: config.schema.json not found at {}, skipping validation",
            schema_path.display()
        );
    }

    // Warn if key enforcement flags are disabled
    let enforcement_flags = [
        "v2_typed_protocol",
        "v3_schema_validation",
        "v2_hard_gates",
        "v2_hard_contracts",
    ];
    for flag in &enforcement_flags {
        let enabled = merged_val.get(*flag).and_then(|v| v.as_bool()).unwrap_or(false);
        if !enabled {
            eprintln!("WARNING: enforcement flag '{}' is disabled", flag);
        }
    }

    // Atomic write via temp file
    let tmp = config_path.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_string_pretty(&merged_val).unwrap())
        .map_err(|e| format!("Failed to write temp config: {e}"))?;
    fs::rename(&tmp, config_path)
        .map_err(|e| format!("Failed to rename temp config: {e}"))?;

    Ok(added)
}

fn read_json(path: &Path) -> Result<Value, String> {
    let content =
        fs::read_to_string(path).map_err(|e| format!("Failed to read {}: {e}", path.display()))?;
    serde_json::from_str(&content)
        .map_err(|e| format!("Malformed JSON in {}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tempfile::tempdir;

    #[test]
    fn test_missing_config_returns_zero() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, "{}").unwrap();
        assert_eq!(migrate_config(&config, &defaults).unwrap(), 0);
    }

    #[test]
    fn test_missing_defaults_returns_error() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&config, "{}").unwrap();
        assert!(migrate_config(&config, &defaults).is_err());
    }

    #[test]
    fn test_rename_agent_teams_true() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(&config, json!({"agent_teams": true}).to_string()).unwrap();

        migrate_config(&config, &defaults).unwrap();

        let result: Value = serde_json::from_str(&fs::read_to_string(&config).unwrap()).unwrap();
        assert_eq!(result["prefer_teams"], "always");
        assert!(result.get("agent_teams").is_none());
    }

    #[test]
    fn test_rename_agent_teams_false() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(&config, json!({"agent_teams": false}).to_string()).unwrap();

        migrate_config(&config, &defaults).unwrap();

        let result: Value = serde_json::from_str(&fs::read_to_string(&config).unwrap()).unwrap();
        assert_eq!(result["prefer_teams"], "auto");
    }

    #[test]
    fn test_prefer_teams_already_exists_drops_agent_teams() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, "{}").unwrap();
        fs::write(
            &config,
            json!({"agent_teams": true, "prefer_teams": "never"}).to_string(),
        )
        .unwrap();

        migrate_config(&config, &defaults).unwrap();

        let result: Value = serde_json::from_str(&fs::read_to_string(&config).unwrap()).unwrap();
        assert_eq!(result["prefer_teams"], "never"); // existing value preserved
        assert!(result.get("agent_teams").is_none());
    }

    #[test]
    fn test_ensures_required_keys() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(&config, "{}").unwrap();

        migrate_config(&config, &defaults).unwrap();

        let result: Value = serde_json::from_str(&fs::read_to_string(&config).unwrap()).unwrap();
        assert_eq!(result["model_profile"], "quality");
        assert!(result.get("model_overrides").unwrap().is_object());
        assert_eq!(result["prefer_teams"], "always");
    }

    #[test]
    fn test_defaults_merge_config_wins() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(
            &defaults,
            json!({"effort": "balanced", "auto_push": "never"}).to_string(),
        )
        .unwrap();
        fs::write(&config, json!({"effort": "thorough"}).to_string()).unwrap();

        migrate_config(&config, &defaults).unwrap();

        let result: Value = serde_json::from_str(&fs::read_to_string(&config).unwrap()).unwrap();
        assert_eq!(result["effort"], "thorough"); // config wins
        assert_eq!(result["auto_push"], "never"); // default backfilled
    }

    #[test]
    fn test_added_count() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(
            &defaults,
            json!({"effort": "balanced", "auto_push": "never", "autonomy": "standard"}).to_string(),
        )
        .unwrap();
        fs::write(&config, json!({"effort": "thorough"}).to_string()).unwrap();

        let added = migrate_config(&config, &defaults).unwrap();
        assert_eq!(added, 2); // auto_push + autonomy were missing
    }

    #[test]
    fn test_malformed_config_returns_error() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, "{}").unwrap();
        fs::write(&config, "not json").unwrap();
        assert!(migrate_config(&config, &defaults).is_err());
    }

    fn write_minimal_schema(dir: &Path) {
        let schema = json!({
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "properties": {
                "effort": { "type": "string", "enum": ["minimal", "balanced", "thorough"] },
                "auto_commit": { "type": "boolean" },
                "max_tasks_per_plan": { "type": "integer", "minimum": 1, "maximum": 10 },
                "v2_typed_protocol": { "type": "boolean" },
                "v3_schema_validation": { "type": "boolean" },
                "v2_hard_gates": { "type": "boolean" },
                "v2_hard_contracts": { "type": "boolean" }
            },
            "additionalProperties": false
        });
        fs::write(dir.join("config.schema.json"), schema.to_string()).unwrap();
    }

    #[test]
    fn test_schema_validation_rejects_invalid_type() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        write_minimal_schema(dir.path());
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(&config, json!({"effort": 123}).to_string()).unwrap();

        let result = migrate_config(&config, &defaults);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("Config validation failed"), "got: {err}");
    }

    #[test]
    fn test_schema_validation_rejects_unknown_key() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        write_minimal_schema(dir.path());
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(
            &config,
            json!({"effort": "balanced", "bogus_key": true}).to_string(),
        )
        .unwrap();

        let result = migrate_config(&config, &defaults);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("Config validation failed"), "got: {err}");
    }

    #[test]
    fn test_schema_validation_accepts_valid_config() {
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        write_minimal_schema(dir.path());
        fs::write(
            &defaults,
            json!({"effort": "balanced", "auto_commit": true}).to_string(),
        )
        .unwrap();
        fs::write(&config, json!({"effort": "thorough"}).to_string()).unwrap();

        assert!(migrate_config(&config, &defaults).is_ok());
    }

    #[test]
    fn test_schema_missing_degrades_gracefully() {
        // No schema file written — validation should be skipped, not error
        let dir = tempdir().unwrap();
        let config = dir.path().join("config.json");
        let defaults = dir.path().join("defaults.json");
        fs::write(&defaults, json!({"effort": "balanced"}).to_string()).unwrap();
        fs::write(&config, json!({"effort": "thorough"}).to_string()).unwrap();

        assert!(migrate_config(&config, &defaults).is_ok());
    }

    #[test]
    fn test_enforcement_flag_warnings() {
        // Test the logic: when enforcement flags are false, they should be detected
        let merged = json!({
            "v2_typed_protocol": false,
            "v3_schema_validation": true,
            "v2_hard_gates": false,
            "v2_hard_contracts": true
        });
        let flags = ["v2_typed_protocol", "v3_schema_validation", "v2_hard_gates", "v2_hard_contracts"];
        let disabled: Vec<&str> = flags
            .iter()
            .filter(|f| !merged.get(**f).and_then(|v| v.as_bool()).unwrap_or(false))
            .copied()
            .collect();
        assert_eq!(disabled, vec!["v2_typed_protocol", "v2_hard_gates"]);
    }
}
