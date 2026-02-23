use serde_json::Value;
use std::fs;
use std::path::Path;

/// All feature flags in the system. Adding a new flag here forces
/// exhaustive handling at compile time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureFlag {
    V2HardContracts,
    V2HardGates,
    V2TypedProtocol,
    V2RoleIsolation,
    V2TwoPhaseCompletion,
    V2TokenBudgets,
    V3DeltaContext,
    V3ContextCache,
    V3PlanResearchPersist,
    V3Metrics,
    V3ContractLite,
    V3LockLite,
    V3ValidationGates,
    V3SmartRouting,
    V3EventLog,
    V3SchemaValidation,
    V3SnapshotResume,
    V3LeaseLocks,
    V3EventRecovery,
    V3MonorepoRouting,
    V4PostEditTestCheck,
    V4SessionCacheWarm,
}

impl FeatureFlag {
    /// The JSON key in config.json for this flag.
    pub fn key(&self) -> &'static str {
        match self {
            Self::V2HardContracts => "v2_hard_contracts",
            Self::V2HardGates => "v2_hard_gates",
            Self::V2TypedProtocol => "v2_typed_protocol",
            Self::V2RoleIsolation => "v2_role_isolation",
            Self::V2TwoPhaseCompletion => "v2_two_phase_completion",
            Self::V2TokenBudgets => "v2_token_budgets",
            Self::V3DeltaContext => "v3_delta_context",
            Self::V3ContextCache => "v3_context_cache",
            Self::V3PlanResearchPersist => "v3_plan_research_persist",
            Self::V3Metrics => "v3_metrics",
            Self::V3ContractLite => "v3_contract_lite",
            Self::V3LockLite => "v3_lock_lite",
            Self::V3ValidationGates => "v3_validation_gates",
            Self::V3SmartRouting => "v3_smart_routing",
            Self::V3EventLog => "v3_event_log",
            Self::V3SchemaValidation => "v3_schema_validation",
            Self::V3SnapshotResume => "v3_snapshot_resume",
            Self::V3LeaseLocks => "v3_lease_locks",
            Self::V3EventRecovery => "v3_event_recovery",
            Self::V3MonorepoRouting => "v3_monorepo_routing",
            Self::V4PostEditTestCheck => "v4_post_edit_test_check",
            Self::V4SessionCacheWarm => "v4_session_cache_warm",
        }
    }

    /// All variants of FeatureFlag.
    pub const ALL: &'static [FeatureFlag] = &[
        Self::V2HardContracts,
        Self::V2HardGates,
        Self::V2TypedProtocol,
        Self::V2RoleIsolation,
        Self::V2TwoPhaseCompletion,
        Self::V2TokenBudgets,
        Self::V3DeltaContext,
        Self::V3ContextCache,
        Self::V3PlanResearchPersist,
        Self::V3Metrics,
        Self::V3ContractLite,
        Self::V3LockLite,
        Self::V3ValidationGates,
        Self::V3SmartRouting,
        Self::V3EventLog,
        Self::V3SchemaValidation,
        Self::V3SnapshotResume,
        Self::V3LeaseLocks,
        Self::V3EventRecovery,
        Self::V3MonorepoRouting,
        Self::V4PostEditTestCheck,
        Self::V4SessionCacheWarm,
    ];
}

/// Read a feature flag from the project config.
/// Returns false if config is missing, unreadable, or flag is absent.
pub fn is_enabled(flag: FeatureFlag, cwd: &Path) -> bool {
    let config_path = cwd.join(".yolo-planning").join("config.json");
    read_flag_from_path(flag, &config_path)
}

/// Read a feature flag from a specific config file path.
pub fn read_flag_from_path(flag: FeatureFlag, config_path: &Path) -> bool {
    if !config_path.exists() {
        return false;
    }
    let content = match fs::read_to_string(config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };
    let config: Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };
    config
        .get(flag.key())
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn test_all_flags_have_unique_keys() {
        let mut keys = HashSet::new();
        for flag in FeatureFlag::ALL {
            assert!(keys.insert(flag.key()), "duplicate key: {}", flag.key());
        }
        assert_eq!(keys.len(), FeatureFlag::ALL.len());
    }

    #[test]
    fn test_flag_key_matches_defaults() {
        let defaults_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("config")
            .join("defaults.json");
        let content = fs::read_to_string(&defaults_path).expect("defaults.json must exist");
        let config: Value = serde_json::from_str(&content).expect("valid JSON");

        for flag in FeatureFlag::ALL {
            assert!(
                config.get(flag.key()).is_some(),
                "FeatureFlag::{:?} key '{}' not found in defaults.json",
                flag,
                flag.key()
            );
        }
    }

    #[test]
    fn test_is_enabled_true() {
        let dir = tempfile::tempdir().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = serde_json::json!({"v3_lock_lite": true});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();

        assert!(is_enabled(FeatureFlag::V3LockLite, dir.path()));
    }

    #[test]
    fn test_is_enabled_false() {
        let dir = tempfile::tempdir().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = serde_json::json!({"v3_lock_lite": false});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();

        assert!(!is_enabled(FeatureFlag::V3LockLite, dir.path()));
    }

    #[test]
    fn test_is_enabled_missing_config() {
        let dir = tempfile::tempdir().unwrap();
        assert!(!is_enabled(FeatureFlag::V3LockLite, dir.path()));
    }

    #[test]
    fn test_is_enabled_missing_key() {
        let dir = tempfile::tempdir().unwrap();
        let planning_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning_dir).unwrap();
        let config = serde_json::json!({"v3_event_log": true});
        fs::write(planning_dir.join("config.json"), config.to_string()).unwrap();

        assert!(!is_enabled(FeatureFlag::V3LockLite, dir.path()));
    }
}
