use serde_json::json;
use std::path::Path;

/// Resolve validation gate policy from effort level, plan risk, and autonomy.
/// Gate matrix determines QA tier, approval requirements, communication level, and two-phase.
/// Fail-open: defaults to balanced/medium/standard on any error.
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    // args: ["yolo", "gate-policy", "<effort>", "<risk>", "<autonomy>"]
    if args.len() < 5 {
        let default = json!({
            "qa_tier": "standard",
            "approval_required": false,
            "communication_level": "blockers",
            "two_phase": false
        });
        return Ok((format!("{}\n", default), 0));
    }

    let effort = &args[2];
    let risk = &args[3];
    let autonomy = &args[4];

    let result = resolve_policy(effort, risk, autonomy);
    Ok((format!("{}\n", result), 0))
}

/// Core gate policy resolution logic.
pub fn resolve_policy(effort: &str, risk: &str, autonomy: &str) -> serde_json::Value {
    let qa_tier = match effort {
        "turbo" => "skip",
        "fast" => "quick",
        "balanced" => "standard",
        "thorough" => "deep",
        _ => "standard",
    };

    let communication_level = match effort {
        "turbo" => "none",
        "fast" => "blockers",
        "balanced" => "blockers_findings",
        "thorough" => "full",
        _ => "blockers",
    };

    let mut approval_required = false;
    let mut two_phase = false;

    match effort {
        "turbo" => {
            // Turbo never requires approval
        }
        "fast" => {
            if risk == "high" {
                match autonomy {
                    "cautious" | "standard" => {
                        approval_required = true;
                        two_phase = true;
                    }
                    _ => {}
                }
            }
        }
        "balanced" => {
            if risk == "high" {
                match autonomy {
                    "cautious" | "standard" => {
                        approval_required = true;
                        two_phase = true;
                    }
                    _ => {}
                }
            } else if risk == "medium" {
                if autonomy == "cautious" {
                    approval_required = true;
                }
            }
        }
        "thorough" => {
            match autonomy {
                "cautious" | "standard" => {
                    approval_required = true;
                    two_phase = true;
                }
                _ => {}
            }
        }
        _ => {}
    }

    json!({
        "qa_tier": qa_tier,
        "approval_required": approval_required,
        "communication_level": communication_level,
        "two_phase": two_phase
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_turbo_always_skip() {
        let result = resolve_policy("turbo", "high", "cautious");
        assert_eq!(result["qa_tier"], "skip");
        assert_eq!(result["approval_required"], false);
        assert_eq!(result["communication_level"], "none");
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_fast_low_no_approval() {
        let result = resolve_policy("fast", "low", "standard");
        assert_eq!(result["qa_tier"], "quick");
        assert_eq!(result["approval_required"], false);
        assert_eq!(result["communication_level"], "blockers");
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_fast_high_cautious_approval() {
        let result = resolve_policy("fast", "high", "cautious");
        assert_eq!(result["qa_tier"], "quick");
        assert_eq!(result["approval_required"], true);
        assert_eq!(result["two_phase"], true);
    }

    #[test]
    fn test_fast_high_confident_no_approval() {
        let result = resolve_policy("fast", "high", "confident");
        assert_eq!(result["approval_required"], false);
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_balanced_medium_cautious_approval() {
        let result = resolve_policy("balanced", "medium", "cautious");
        assert_eq!(result["qa_tier"], "standard");
        assert_eq!(result["approval_required"], true);
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_balanced_medium_standard_no_approval() {
        let result = resolve_policy("balanced", "medium", "standard");
        assert_eq!(result["approval_required"], false);
    }

    #[test]
    fn test_balanced_high_standard_approval() {
        let result = resolve_policy("balanced", "high", "standard");
        assert_eq!(result["qa_tier"], "standard");
        assert_eq!(result["approval_required"], true);
        assert_eq!(result["two_phase"], true);
        assert_eq!(result["communication_level"], "blockers_findings");
    }

    #[test]
    fn test_thorough_cautious_full() {
        let result = resolve_policy("thorough", "low", "cautious");
        assert_eq!(result["qa_tier"], "deep");
        assert_eq!(result["approval_required"], true);
        assert_eq!(result["communication_level"], "full");
        assert_eq!(result["two_phase"], true);
    }

    #[test]
    fn test_thorough_confident_no_approval() {
        let result = resolve_policy("thorough", "low", "confident");
        assert_eq!(result["qa_tier"], "deep");
        assert_eq!(result["approval_required"], false);
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_thorough_pure_vibe_no_approval() {
        let result = resolve_policy("thorough", "high", "pure-vibe");
        assert_eq!(result["approval_required"], false);
        assert_eq!(result["two_phase"], false);
    }

    #[test]
    fn test_unknown_effort_defaults() {
        let result = resolve_policy("unknown", "low", "standard");
        assert_eq!(result["qa_tier"], "standard");
        assert_eq!(result["communication_level"], "blockers");
    }

    #[test]
    fn test_execute_missing_args() {
        let args: Vec<String> = vec!["yolo".into(), "gate-policy".into()];
        let cwd = std::path::PathBuf::from(".");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(out.trim()).unwrap();
        assert_eq!(parsed["qa_tier"], "standard");
        assert_eq!(parsed["approval_required"], false);
    }
}
