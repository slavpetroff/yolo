use chrono::Utc;
use serde_json::{json, Value};
use std::fs;
use std::io::Write;
use std::path::Path;

use super::utils;

/// PreCompact handler: inject agent-specific summarization priorities.
///
/// - Extracts agent_name and matcher from input
/// - Maps role to priority string
/// - Writes `.compaction-marker` with timestamp
/// - Returns hookSpecificOutput with priorities
/// - Always exit 0
pub fn handle_pre_compact(input: &Value) -> (Value, i32) {
    let agent_name = input
        .get("agent_name")
        .or_else(|| input.get("agentName"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let matcher = input
        .get("matcher")
        .and_then(|v| v.as_str())
        .unwrap_or("auto");

    let role = utils::normalize_agent_role(agent_name);
    let priorities = role_priorities(&role);

    let manual_suffix = if matcher == "manual" {
        " User requested compaction."
    } else {
        " This is an automatic compaction at context limit."
    };

    let full_priorities = format!("{}{}", priorities, manual_suffix);

    // Write compaction marker
    write_compaction_marker();

    // Save agent state snapshot
    save_snapshot(input, agent_name, matcher);

    let output = json!({
        "hookEventName": "PreCompact",
        "hookSpecificOutput": {
            "hookEventName": "PreCompact",
            "additionalContext": format!("Compaction priorities: {} Re-read assigned files from disk after compaction.", full_priorities)
        }
    });

    (output, 0)
}

/// Map normalized agent role to compaction priority strings.
fn role_priorities(role: &str) -> &'static str {
    match role {
        "scout" => "Preserve research findings, URLs, confidence assessments",
        "dev" => "Preserve commit hashes, file paths modified, deviation decisions, current task number. After compaction, if .yolo-planning/codebase/META.md exists, re-read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from .yolo-planning/codebase/",
        "qa" => "Preserve pass/fail status, gap descriptions, verification results. After compaction, if .yolo-planning/codebase/META.md exists, re-read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from .yolo-planning/codebase/",
        "lead" => "Preserve phase status, plan structure, coordination decisions. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, and STRUCTURE.md (whichever exist) from .yolo-planning/codebase/",
        "architect" => "Preserve requirement IDs, phase structure, success criteria, key decisions. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md and STACK.md (whichever exist) from .yolo-planning/codebase/",
        "debugger" => "Preserve reproduction steps, hypotheses, evidence gathered, diagnosis. After compaction, if .yolo-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from .yolo-planning/codebase/",
        _ => "Preserve active command being executed, user's original request, current phase/plan context, file modification paths, any pending user decisions. Discard: tool output details, reference file contents (re-read from disk), previous command results",
    }
}

/// Write `.compaction-marker` with Unix timestamp into `.yolo-planning/`.
fn write_compaction_marker() {
    let planning = Path::new(".yolo-planning");
    if !planning.is_dir() {
        return;
    }
    let marker = planning.join(".compaction-marker");
    let ts = Utc::now().timestamp().to_string();
    let _ = fs::write(&marker, ts);
}

/// Save agent state snapshot (mirrors bash snapshot-resume.sh save).
/// Best-effort: failures are logged but do not affect exit code.
fn save_snapshot(input: &Value, agent_name: &str, matcher: &str) {
    let planning = Path::new(".yolo-planning");
    let exec_state_path = planning.join(".execution-state.json");
    if !exec_state_path.is_file() {
        return;
    }

    let exec_state_content = match fs::read_to_string(&exec_state_path) {
        Ok(c) => c,
        Err(_) => return,
    };
    let exec_state: Value = match serde_json::from_str(&exec_state_content) {
        Ok(v) => v,
        Err(_) => return,
    };

    let phase = exec_state
        .get("phase")
        .and_then(|v| v.as_str())
        .or_else(|| exec_state.get("phase").and_then(|v| v.as_i64()).map(|_| ""))
        .unwrap_or("");

    if phase.is_empty() {
        // Try numeric phase
        let phase_num = exec_state.get("phase").and_then(|v| v.as_i64());
        if let Some(p) = phase_num {
            save_snapshot_for_phase(&p.to_string(), &exec_state, agent_name, matcher, planning);
        }
        return;
    }

    save_snapshot_for_phase(phase, &exec_state, agent_name, matcher, planning);
}

fn save_snapshot_for_phase(
    phase: &str,
    exec_state: &Value,
    agent_name: &str,
    matcher: &str,
    planning: &Path,
) {
    let snapshots_dir = planning.join("snapshots");
    let _ = fs::create_dir_all(&snapshots_dir);

    let ts = Utc::now().format("%Y%m%d%H%M%S").to_string();
    let snap_filename = format!("snap-{}-{}.json", phase, ts);
    let snap_path = snapshots_dir.join(&snap_filename);

    let snapshot = json!({
        "timestamp": Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "phase": phase,
        "agent_name": agent_name,
        "matcher": matcher,
        "execution_state": exec_state,
    });

    if let Ok(json_str) = serde_json::to_string_pretty(&snapshot) {
        let _ = fs::write(&snap_path, json_str);
    }

    // Log snapshot
    let log_path = planning.join(".hook-errors.log");
    let ts_iso = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let msg = format!(
        "[{}] Snapshot saved: phase={} agent={}\n",
        ts_iso, phase, agent_name
    );
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
    {
        let _ = f.write_all(msg.as_bytes());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_role_priorities_dev() {
        let p = role_priorities("dev");
        assert!(p.contains("commit hashes"));
        assert!(p.contains("CONVENTIONS.md"));
    }

    #[test]
    fn test_role_priorities_scout() {
        let p = role_priorities("scout");
        assert!(p.contains("research findings"));
    }

    #[test]
    fn test_role_priorities_qa() {
        let p = role_priorities("qa");
        assert!(p.contains("pass/fail"));
        assert!(p.contains("TESTING.md"));
    }

    #[test]
    fn test_role_priorities_lead() {
        let p = role_priorities("lead");
        assert!(p.contains("phase status"));
    }

    #[test]
    fn test_role_priorities_architect() {
        let p = role_priorities("architect");
        assert!(p.contains("requirement IDs"));
    }

    #[test]
    fn test_role_priorities_debugger() {
        let p = role_priorities("debugger");
        assert!(p.contains("reproduction steps"));
    }

    #[test]
    fn test_role_priorities_default() {
        let p = role_priorities("unknown");
        assert!(p.contains("original request"));
    }

    #[test]
    fn test_handle_pre_compact_dev_agent() {
        let input = json!({"agent_name": "yolo-dev-1", "matcher": "auto"});
        let (output, code) = handle_pre_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("Compaction priorities:"));
        assert!(ctx.contains("commit hashes"));
        assert!(ctx.contains("automatic compaction"));
        assert!(ctx.contains("Re-read assigned files"));
    }

    #[test]
    fn test_handle_pre_compact_manual_trigger() {
        let input = json!({"agent_name": "yolo-lead", "matcher": "manual"});
        let (output, code) = handle_pre_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("User requested compaction"));
    }

    #[test]
    fn test_handle_pre_compact_unknown_agent() {
        let input = json!({"matcher": "auto"});
        let (output, code) = handle_pre_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("original request"));
    }

    #[test]
    fn test_handle_pre_compact_camel_case_agent_name() {
        let input = json!({"agentName": "yolo-qa", "matcher": "auto"});
        let (output, code) = handle_pre_compact(&input);
        assert_eq!(code, 0);

        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("pass/fail"));
    }

    #[test]
    fn test_handle_pre_compact_output_structure() {
        let input = json!({"agent_name": "yolo-scout"});
        let (output, code) = handle_pre_compact(&input);
        assert_eq!(code, 0);
        assert!(output.get("hookSpecificOutput").is_some());
        assert_eq!(
            output["hookSpecificOutput"]["hookEventName"],
            "PreCompact"
        );
    }
}
