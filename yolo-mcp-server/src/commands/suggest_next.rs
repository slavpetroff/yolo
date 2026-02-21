use std::fs;
use std::path::{Path, PathBuf};
use serde_json::{json, Value};
use std::process::Command;
use std::time::Instant;

pub struct Context {
    pub has_project: bool,
    pub next_unplanned: Option<String>,
    pub next_unbuilt: Option<String>,
    pub all_done: bool,
    pub last_qa_result: Option<String>,
    pub map_exists: bool,
    pub effort: String,
    pub active_phase_dir: Option<PathBuf>,
    pub active_phase_num: Option<String>,
    pub active_phase_name: Option<String>,
    pub active_phase_plans: usize,
    pub deviation_count: usize,
    pub failing_plan_ids: Vec<String>,
    pub map_staleness: i64,
    pub cfg_autonomy: String,
    pub has_uat: bool,
    pub phase_count: usize,
}

impl Default for Context {
    fn default() -> Self {
        Self {
            has_project: false,
            next_unplanned: None,
            next_unbuilt: None,
            all_done: false,
            last_qa_result: None,
            map_exists: false,
            effort: "balanced".to_string(),
            active_phase_dir: None,
            active_phase_num: None,
            active_phase_name: None,
            active_phase_plans: 0,
            deviation_count: 0,
            failing_plan_ids: Vec::new(),
            map_staleness: -1,
            cfg_autonomy: "standard".to_string(),
            has_uat: false,
            phase_count: 0,
        }
    }
}

fn gather_context(cwd: &Path) -> Context {
    let mut ctx = Context::default();
    let planning_dir = cwd.join(".yolo-planning");

    if !planning_dir.exists() {
        return ctx;
    }

    let mut phases_dir = planning_dir.join("phases");
    let active_file = planning_dir.join("ACTIVE");
    if active_file.exists() {
        if let Ok(active_ms) = fs::read_to_string(&active_file) {
            let active_ms = active_ms.trim();
            if !active_ms.is_empty() {
                let ms_phases = planning_dir.join("milestones").join(active_ms).join("phases");
                if ms_phases.exists() {
                    phases_dir = ms_phases;
                }
            }
        }
    }

    let project_md = planning_dir.join("PROJECT.md");
    if project_md.exists() {
        if let Ok(content) = fs::read_to_string(&project_md) {
            if !content.contains("{project-name}") {
                ctx.has_project = true;
            }
        }
    }

    let config_json = planning_dir.join("config.json");
    if config_json.exists() {
        if let Ok(content) = fs::read_to_string(&config_json) {
            if let Ok(json) = serde_json::from_str::<Value>(&content) {
                if let Some(effort) = json.get("effort").and_then(|v| v.as_str()) {
                    ctx.effort = effort.to_string();
                }
                if let Some(autonomy) = json.get("autonomy").and_then(|v| v.as_str()) {
                    ctx.cfg_autonomy = autonomy.to_string();
                }
            }
        }
    }

    let mut last_phase_dir = None;
    let mut last_phase_num = None;
    let mut last_phase_name = None;
    let mut last_phase_plans = 0;

    if phases_dir.exists() {
        if let Ok(entries) = fs::read_dir(&phases_dir) {
            let mut dirs: Vec<_> = entries.filter_map(|e| e.ok()).filter(|e| e.path().is_dir()).collect();
            dirs.sort_by_key(|e| e.path());

            for entry in dirs {
                ctx.phase_count += 1;
                let dir_path = entry.path();
                let dir_name = dir_path.file_name().unwrap_or_default().to_string_lossy();
                let splits: Vec<&str> = dir_name.splitn(2, '-').collect();
                let phase_num = splits.get(0).copied().unwrap_or("").to_string();
                let phase_slug = splits.get(1).copied().unwrap_or("").to_string();

                let mut plans = 0;
                let mut summaries = 0;

                if let Ok(files) = fs::read_dir(&dir_path) {
                    for fe in files.filter_map(|e| e.ok()) {
                        let fn_str = fe.file_name().to_string_lossy().to_string();
                        if fn_str.ends_with("-PLAN.md") { plans += 1; }
                        if fn_str.ends_with("-SUMMARY.md") { summaries += 1; }

                        if fn_str.ends_with("-VERIFICATION.md") {
                            if let Ok(c) = fs::read_to_string(fe.path()) {
                                if let Some(line) = c.lines().find(|l| l.starts_with("result:")) {
                                    ctx.last_qa_result = Some(line.replace("result:", "").trim().to_lowercase());
                                }
                            }
                        }
                    }
                }

                if plans == 0 && ctx.next_unplanned.is_none() {
                    ctx.next_unplanned = Some(phase_num.clone());
                    ctx.active_phase_dir = Some(dir_path.clone());
                    ctx.active_phase_num = Some(phase_num.clone());
                    ctx.active_phase_name = Some(phase_slug.clone());
                    ctx.active_phase_plans = 0;
                } else if plans > 0 && summaries < plans && ctx.next_unbuilt.is_none() {
                    ctx.next_unbuilt = Some(phase_num.clone());
                    ctx.active_phase_dir = Some(dir_path.clone());
                    ctx.active_phase_num = Some(phase_num.clone());
                    ctx.active_phase_name = Some(phase_slug.clone());
                    ctx.active_phase_plans = plans;
                }

                last_phase_dir = Some(dir_path);
                last_phase_num = Some(phase_num);
                last_phase_name = Some(phase_slug);
                last_phase_plans = plans;
            }
        }

        if ctx.active_phase_dir.is_none() && last_phase_dir.is_some() {
            ctx.active_phase_dir = last_phase_dir;
            ctx.active_phase_num = last_phase_num;
            ctx.active_phase_name = last_phase_name;
            ctx.active_phase_plans = last_phase_plans;
        }

        if ctx.phase_count > 0 && ctx.next_unplanned.is_none() && ctx.next_unbuilt.is_none() {
            ctx.all_done = true;
        }

        if let Some(act_dir) = &ctx.active_phase_dir {
            if let Ok(files) = fs::read_dir(act_dir) {
                for fe in files.filter_map(|e| e.ok()) {
                    let path = fe.path();
                    let fn_str = fe.file_name().to_string_lossy().to_string();
                    
                    if fn_str.ends_with("-SUMMARY.md") {
                        if let Ok(c) = fs::read_to_string(&path) {
                            for line in c.lines() {
                                if line.starts_with("deviations:") {
                                    let d_val = line.replace("deviations:", "").trim().to_string();
                                    if d_val != "0" && d_val != "[]" && !d_val.is_empty() {
                                        if let Ok(num) = d_val.parse::<usize>() {
                                            ctx.deviation_count += num;
                                        } else {
                                            ctx.deviation_count += 1;
                                        }
                                    }
                                }
                                if line.starts_with("status:") {
                                    let s_val = line.replace("status:", "").trim().to_lowercase();
                                    if s_val == "failed" || s_val == "partial" {
                                        let plan_id = fn_str.replace("-SUMMARY.md", "");
                                        ctx.failing_plan_ids.push(plan_id);
                                    }
                                }
                            }
                        }
                    }

                    if fn_str.ends_with("-UAT.md") {
                        if let Ok(c) = fs::read_to_string(&path) {
                            if c.lines().any(|l| l.starts_with("status:") && l.replace("status:", "").trim().to_lowercase() == "complete") {
                                ctx.has_uat = true;
                            }
                        }
                    }
                }
            }
        }
    }

    let codebase_dir = planning_dir.join("codebase");
    if codebase_dir.exists() {
        ctx.map_exists = true;
        let meta_file = codebase_dir.join("META.md");
        if meta_file.exists() && Command::new("git").arg("rev-parse").arg("--git-dir").current_dir(cwd).output().is_ok() {
            if let Ok(c) = fs::read_to_string(&meta_file) {
                let mut git_hash = None;
                let mut file_count = None;
                for line in c.lines() {
                    if line.starts_with("git_hash:") {
                        let parts: Vec<&str> = line.split_whitespace().collect();
                        if parts.len() > 1 { git_hash = Some(parts[1].to_string()); }
                    }
                    if line.starts_with("file_count:") {
                        let parts: Vec<&str> = line.split_whitespace().collect();
                        if parts.len() > 1 { file_count = parts[1].parse::<i64>().ok(); }
                    }
                }

                if let (Some(hash), Some(cnt)) = (git_hash, file_count) {
                    if cnt > 0 {
                        let diff_status = Command::new("git").args(&["cat-file", "-e", &hash]).current_dir(cwd).output();
                        if let Ok(out) = diff_status {
                            if out.status.success() {
                                let diff_out = Command::new("git").args(&["diff", "--name-only", &format!("{}..HEAD", hash)]).current_dir(cwd).output();
                                if let Ok(d_o) = diff_out {
                                    if d_o.status.success() {
                                        let changed_str = String::from_utf8_lossy(&d_o.stdout);
                                        let changed: i64 = changed_str.lines().filter(|l| !l.trim().is_empty()).count() as i64;
                                        ctx.map_staleness = (changed * 100) / cnt;
                                    }
                                }
                            } else {
                                ctx.map_staleness = 100;
                            }
                        } else {
                            ctx.map_staleness = 100;
                        }
                    }
                }
            }
        }
    }

    // Sort fail ids to be deterministic
    ctx.failing_plan_ids.sort();

    ctx
}

fn fmt_phase_name(name: &str) -> String {
    name.replace('-', " ")
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    let cmd = args.get(2).map(|s| s.as_str()).unwrap_or("");
    let result_arg = args.get(3).map(|s| s.as_str()).unwrap_or("");

    let ctx = gather_context(cwd);
    let effective_result = if !result_arg.is_empty() {
        result_arg.to_string()
    } else {
        ctx.last_qa_result.clone().unwrap_or_default()
    };

    let mut suggestions: Vec<Value> = Vec::new();
    let mut add_suggestion = |command: &str, reason: &str| {
        suggestions.push(json!({"command": command, "reason": reason}));
    };

    match cmd {
        "init" => {
            add_suggestion("/yolo:vibe", "Define your project and start building");
        }
        "vibe" | "implement" | "execute" => {
            match effective_result.as_str() {
                "fail" => {
                    if let Some(first_fail) = ctx.failing_plan_ids.first() {
                        add_suggestion("/yolo:fix", &format!("Fix plan {} (failed verification)", first_fail));
                    } else {
                        add_suggestion("/yolo:fix", "Fix the failing checks");
                    }
                    add_suggestion("/yolo:qa", "Re-run verification after fixing");
                }
                "partial" => {
                    if let Some(first_fail) = ctx.failing_plan_ids.first() {
                        add_suggestion("/yolo:fix", &format!("Fix plan {} (partial failure)", first_fail));
                    } else {
                        add_suggestion("/yolo:fix", "Address partial failures");
                    }
                    if !ctx.all_done {
                        add_suggestion("/yolo:vibe", "Continue to next phase");
                    }
                }
                _ => {
                    if !ctx.has_uat && (ctx.cfg_autonomy == "cautious" || ctx.cfg_autonomy == "standard") {
                        add_suggestion("/yolo:verify", "Walk through changes before continuing");
                    }
                    if ctx.all_done {
                        if ctx.deviation_count == 0 {
                            add_suggestion("/yolo:vibe --archive", "All phases complete, zero deviations");
                        } else {
                            add_suggestion("/yolo:vibe --archive", &format!("Archive completed work ({} deviation(s) logged)", ctx.deviation_count));
                            add_suggestion("/yolo:qa", "Review before archiving");
                        }
                    } else if ctx.next_unbuilt.is_some() || ctx.next_unplanned.is_some() {
                        let target = ctx.next_unbuilt.as_ref().or(ctx.next_unplanned.as_ref()).unwrap();
                        let target_is_active = ctx.active_phase_num.as_ref() == Some(target);
                        if ctx.active_phase_name.is_some() && !target_is_active {
                            add_suggestion("/yolo:vibe", &format!("Continue to Phase {}: {}", target, fmt_phase_name(ctx.active_phase_name.as_deref().unwrap_or("unknown"))));
                        } else {
                            add_suggestion("/yolo:vibe", "Continue to next phase");
                        }
                    }
                    if effective_result == "skipped" {
                        add_suggestion("/yolo:qa", "Verify completed work");
                    }
                }
            }
        }
        "plan" => {
            if ctx.active_phase_plans > 0 {
                add_suggestion("/yolo:vibe", &format!("Execute {} plans ({} effort)", ctx.active_phase_plans, ctx.effort));
            } else {
                add_suggestion("/yolo:vibe", "Execute the planned phase");
            }
        }
        "qa" => {
            match effective_result.as_str() {
                "pass" => {
                    if !ctx.has_uat && (ctx.cfg_autonomy == "cautious" || ctx.cfg_autonomy == "standard") {
                        add_suggestion("/yolo:verify", "Walk through changes manually");
                    }
                    if ctx.all_done {
                        if ctx.deviation_count == 0 {
                            add_suggestion("/yolo:vibe --archive", "All phases complete, zero deviations");
                        } else {
                            add_suggestion("/yolo:vibe --archive", &format!("Archive completed work ({} deviation(s) logged)", ctx.deviation_count));
                        }
                    } else if let Some(target) = ctx.next_unbuilt.as_ref().or(ctx.next_unplanned.as_ref()) {
                        add_suggestion("/yolo:vibe", &format!("Continue to Phase {}: {}", target, fmt_phase_name(ctx.active_phase_name.as_deref().unwrap_or("unknown"))));
                    } else {
                        add_suggestion("/yolo:vibe", "Continue to next phase");
                    }
                }
                "fail" => {
                    if let Some(first_fail) = ctx.failing_plan_ids.first() {
                        add_suggestion("/yolo:fix", &format!("Fix plan {} (failed QA)", first_fail));
                    } else {
                        add_suggestion("/yolo:fix", "Fix the failing checks");
                    }
                }
                "partial" => {
                    if let Some(first_fail) = ctx.failing_plan_ids.first() {
                        add_suggestion("/yolo:fix", &format!("Fix plan {} (partial failure)", first_fail));
                    } else {
                        add_suggestion("/yolo:fix", "Address partial failures");
                    }
                    add_suggestion("/yolo:vibe", "Continue despite warnings");
                }
                _ => {
                    add_suggestion("/yolo:vibe", "Continue building");
                }
            }
        }
        "fix" => {
            add_suggestion("/yolo:qa", "Verify the fix");
            add_suggestion("/yolo:vibe", "Continue building");
        }
        "verify" => {
            match effective_result.as_str() {
                "pass" => {
                    if ctx.all_done {
                        add_suggestion("/yolo:vibe --archive", "All verified, ready to ship");
                    } else {
                        add_suggestion("/yolo:vibe", "Continue to next phase");
                    }
                }
                "issues_found" => {
                    add_suggestion("/yolo:fix", "Fix the issues found during UAT");
                    add_suggestion("/yolo:verify --resume", "Continue testing after fix");
                }
                _ => {
                    add_suggestion("/yolo:vibe", "Continue building");
                }
            }
        }
        "debug" => {
            add_suggestion("/yolo:fix", "Apply the fix");
            add_suggestion("/yolo:vibe", "Continue building");
        }
        "config" => {
            if ctx.has_project {
                add_suggestion("/yolo:status", "View project state");
            } else {
                add_suggestion("/yolo:vibe", "Define your project and start building");
            }
        }
        "archive" => {
            add_suggestion("/yolo:vibe", "Start new work");
        }
        "status" => {
            if ctx.all_done {
                if ctx.deviation_count == 0 {
                    add_suggestion("/yolo:vibe --archive", "All phases complete, zero deviations");
                } else {
                    add_suggestion("/yolo:vibe --archive", "Archive completed work");
                }
            } else if let Some(target) = ctx.next_unbuilt.as_ref().or(ctx.next_unplanned.as_ref()) {
                add_suggestion("/yolo:vibe", &format!("Continue Phase {}: {}", target, fmt_phase_name(ctx.active_phase_name.as_deref().unwrap_or("unknown"))));
            } else {
                add_suggestion("/yolo:vibe", "Start building");
            }
        }
        "map" => {
            add_suggestion("/yolo:vibe", "Start building");
            add_suggestion("/yolo:status", "View project state");
        }
        "discuss" | "assumptions" => {
            add_suggestion("/yolo:vibe --plan", "Plan this phase");
            add_suggestion("/yolo:vibe", "Plan and execute in one flow");
        }
        "resume" => {
            add_suggestion("/yolo:vibe", "Continue building");
            add_suggestion("/yolo:status", "View current progress");
        }
        _ => {
            if ctx.has_project {
                add_suggestion("/yolo:vibe", "Continue building");
                add_suggestion("/yolo:status", "View project progress");
            } else {
                add_suggestion("/yolo:vibe", "Start a new project");
            }
        }
    }

    match cmd {
        "map" | "init" | "help" | "update" | "whats-new" | "uninstall" => {}
        _ => {
            if ctx.has_project && ctx.phase_count > 0 {
                if !ctx.map_exists {
                    add_suggestion("/yolo:map", "Map your codebase for better planning");
                } else if ctx.map_staleness > 30 {
                    add_suggestion("/yolo:map --incremental", &format!("Codebase map is {}% stale", ctx.map_staleness));
                }
            }
        }
    }

    // Build legacy text output for backward compatibility
    let mut text = String::from("➜ Next Up\n");
    for s in &suggestions {
        let command = s["command"].as_str().unwrap_or("");
        let reason = s["reason"].as_str().unwrap_or("");
        text.push_str(&format!("  {} -- {}\n", command, reason));
    }

    let response = json!({
        "ok": true,
        "cmd": "suggest-next",
        "delta": {
            "context_cmd": cmd,
            "suggestions": suggestions,
            "phase_num": ctx.active_phase_num,
            "phase_name": ctx.active_phase_name,
            "all_done": ctx.all_done,
            "deviation_count": ctx.deviation_count,
            "effort": ctx.effort,
            "has_project": ctx.has_project,
            "map_staleness": ctx.map_staleness,
            "text": text
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });

    Ok((response.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn run_suggest(args: &[&str], cwd: &Path) -> Result<(String, i32), String> {
        let mut string_args = Vec::new();
        string_args.push("yolo".to_string());
        string_args.push("suggest-next".to_string());
        for a in args {
            string_args.push(a.to_string());
        }
        execute(&string_args, cwd)
    }

    #[test]
    fn test_empty_workspace_init() {
        let dir = tempdir().unwrap();
        let (out, code) = run_suggest(&["init"], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["cmd"], "suggest-next");
        let suggestions = j["delta"]["suggestions"].as_array().unwrap();
        assert!(suggestions.iter().any(|s| s["command"].as_str().unwrap().contains("/yolo:vibe")));
        // Legacy text preserved in delta
        let text = j["delta"]["text"].as_str().unwrap();
        assert!(text.contains("/yolo:vibe -- Define your project and start building"));
    }

    #[test]
    fn test_vibe_fail_no_plans() {
        let dir = tempdir().unwrap();
        let (out, code) = run_suggest(&["vibe", "fail"], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(j["ok"], true);
        let suggestions = j["delta"]["suggestions"].as_array().unwrap();
        assert!(suggestions.iter().any(|s| s["command"] == "/yolo:fix" && s["reason"].as_str().unwrap().contains("failing checks")));
        assert!(suggestions.iter().any(|s| s["command"] == "/yolo:qa"));
    }

    #[test]
    fn test_vibe_fail_with_plans() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let active = plan_dir.join("phases").join("1-setup");
        fs::create_dir_all(&active).unwrap();
        fs::write(active.join("auth-SUMMARY.md"), "status: failed\n").unwrap();

        let (out, code) = run_suggest(&["vibe", "fail"], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&out).unwrap();
        let suggestions = j["delta"]["suggestions"].as_array().unwrap();
        assert!(suggestions.iter().any(|s| s["reason"].as_str().unwrap().contains("Fix plan auth (failed verification)")));
    }

    #[test]
    fn test_all_done() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let active = plan_dir.join("phases").join("1-setup");
        fs::create_dir_all(&active).unwrap();
        fs::write(active.join("auth-PLAN.md"), "plan").unwrap();
        fs::write(active.join("auth-SUMMARY.md"), "status: complete\n").unwrap();

        let (out, code) = run_suggest(&["status"], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(j["delta"]["all_done"], true);
        let suggestions = j["delta"]["suggestions"].as_array().unwrap();
        assert!(suggestions.iter().any(|s| s["command"] == "/yolo:vibe --archive"));
    }

    #[test]
    fn test_json_envelope_fields() {
        let dir = tempdir().unwrap();
        let (out, code) = run_suggest(&["init"], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["cmd"], "suggest-next");
        assert!(j["elapsed_ms"].is_number());
        assert_eq!(j["delta"]["context_cmd"], "init");
        assert_eq!(j["delta"]["has_project"], false);
        assert!(j["delta"]["effort"].is_string());
    }
}
