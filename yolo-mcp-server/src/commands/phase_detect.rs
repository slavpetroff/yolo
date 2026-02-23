use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Clone, Copy)]
enum PhaseState {
    NoPhases,
    NeedsPlanAndExecute,
    NeedsExecute,
    AllDone,
}

impl PhaseState {
    fn as_str(&self) -> &'static str {
        match self {
            PhaseState::NoPhases => "no_phases",
            PhaseState::NeedsPlanAndExecute => "needs_plan_and_execute",
            PhaseState::NeedsExecute => "needs_execute",
            PhaseState::AllDone => "all_done",
        }
    }
}

enum Route {
    Init,
    Bootstrap,
    Resume,
    Plan,
    Execute,
    Archive,
}

impl Route {
    fn as_str(&self) -> &'static str {
        match self {
            Route::Init => "init",
            Route::Bootstrap => "bootstrap",
            Route::Resume => "resume",
            Route::Plan => "plan",
            Route::Execute => "execute",
            Route::Archive => "archive",
        }
    }
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let suggest_route = args.iter().any(|a| a == "--suggest-route");
    let planning_dir = cwd.join(".yolo-planning");

    let mut out = String::new();

    // --- jq availability (simulated for backward compat output shape) ---
    out.push_str("jq_available=true\n");

    // --- Planning directory ---
    if !planning_dir.exists() {
        out.push_str("planning_dir_exists=false\n");
        out.push_str("project_exists=false\n");
        out.push_str("active_milestone=none\n");
        out.push_str("phases_dir=none\n");
        out.push_str("phase_count=0\n");
        out.push_str("next_phase=none\n");
        out.push_str("next_phase_slug=none\n");
        out.push_str(&format!("next_phase_state={}\n", PhaseState::NoPhases.as_str()));
        out.push_str("next_phase_plans=0\n");
        out.push_str("next_phase_summaries=0\n");
        out.push_str("config_effort=balanced\n");
        out.push_str("config_autonomy=standard\n");
        out.push_str("config_auto_commit=true\n");
        out.push_str("config_planning_tracking=manual\n");
        out.push_str("config_auto_push=never\n");
        out.push_str("config_verification_tier=standard\n");
        out.push_str("config_prefer_teams=always\n");
        out.push_str("config_max_tasks_per_plan=5\n");
        out.push_str("config_context_compiler=true\n");
        out.push_str("has_codebase_map=false\n");
        out.push_str("brownfield=false\n");
        out.push_str("execution_state=none\n");
        if suggest_route {
            out.push_str(&format!("suggested_route={}\n", Route::Init.as_str()));
        }
        return Ok((out, 0));
    }
    out.push_str("planning_dir_exists=true\n");

    // --- Project existence ---
    let mut project_exists = false;
    let project_md = planning_dir.join("PROJECT.md");
    if project_md.exists() {
        if let Ok(content) = fs::read_to_string(&project_md) {
            if !content.contains("{project-description}") {
                project_exists = true;
            }
        }
    }
    out.push_str(&format!("project_exists={}\n", project_exists));

    // --- Active milestone resolution ---
    let mut active_milestone = "none".to_string();
    let mut active_milestone_error = false;
    let mut phases_dir = planning_dir.join("phases");

    let active_file = planning_dir.join("ACTIVE");
    if active_file.exists() {
        if let Ok(content) = fs::read_to_string(&active_file) {
            let slug = content.trim();
            if !slug.is_empty() {
                let candidate = planning_dir.join("milestones").join(slug).join("phases");
                if candidate.exists() && candidate.is_dir() {
                    active_milestone = slug.to_string();
                    phases_dir = candidate;
                } else {
                    active_milestone_error = true;
                }
            }
        }
    }
    out.push_str(&format!("active_milestone={}\n", active_milestone));
    out.push_str(&format!("active_milestone_error={}\n", active_milestone_error));
    out.push_str(&format!("phases_dir={}\n", phases_dir.to_string_lossy()));

    // --- Phase scanning ---
    let mut phase_count = 0;
    let mut next_phase = "none".to_string();
    let mut next_phase_slug = "none".to_string();
    let mut next_phase_state = PhaseState::NoPhases;
    let mut next_phase_plans = 0;
    let mut next_phase_summaries = 0;

    let mut all_done = true;

    if phases_dir.exists() && phases_dir.is_dir() {
        if let Ok(mut entries) = fs::read_dir(&phases_dir) {
            let mut dirs = Vec::new();
            while let Some(Ok(entry)) = entries.next() {
                let path = entry.path();
                if path.is_dir() {
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        dirs.push((name.to_string(), path));
                    }
                }
            }
            dirs.sort_by(|a, b| a.0.cmp(&b.0));
            phase_count = dirs.len();

            if phase_count > 0 {
                for (dirname, path) in dirs {
                    let re = regex::Regex::new(r"^(\d+).*").unwrap();
                    let num = if let Some(caps) = re.captures(&dirname) {
                        caps.get(1).map(|m| m.as_str()).unwrap_or("")
                    } else {
                        ""
                    };

                    // Count PLAN and SUMMARY files
                    let mut p_count = 0;
                    let mut s_count = 0;
                    if let Ok(files) = fs::read_dir(&path) {
                        for f in files.filter_map(|e| e.ok()) {
                            let fname = f.file_name();
                            let fn_str = fname.to_string_lossy();
                            if fn_str.ends_with("-PLAN.md") {
                                p_count += 1;
                            } else if fn_str.ends_with("-SUMMARY.md") {
                                s_count += 1;
                            }
                        }
                    }

                    if p_count == 0 {
                        if next_phase == "none" {
                            next_phase = num.to_string();
                            next_phase_slug = dirname.clone();
                            next_phase_state = PhaseState::NeedsPlanAndExecute;
                            next_phase_plans = p_count;
                            next_phase_summaries = s_count;
                        }
                        all_done = false;
                        break;
                    } else if s_count < p_count {
                        if next_phase == "none" {
                            next_phase = num.to_string();
                            next_phase_slug = dirname.clone();
                            next_phase_state = PhaseState::NeedsExecute;
                            next_phase_plans = p_count;
                            next_phase_summaries = s_count;
                        }
                        all_done = false;
                        break;
                    }
                }
                
                if all_done && next_phase == "none" {
                    next_phase_state = PhaseState::AllDone;
                }
            }
        }
    }

    out.push_str(&format!("phase_count={}\n", phase_count));
    out.push_str(&format!("next_phase={}\n", next_phase));
    out.push_str(&format!("next_phase_slug={}\n", next_phase_slug));
    out.push_str(&format!("next_phase_state={}\n", next_phase_state.as_str()));
    out.push_str(&format!("next_phase_plans={}\n", next_phase_plans));
    out.push_str(&format!("next_phase_summaries={}\n", next_phase_summaries));

    // --- Config values ---
    let config_file = planning_dir.join("config.json");
    
    let mut cfg_effort = "balanced".to_string();
    let mut cfg_autonomy = "standard".to_string();
    let mut cfg_auto_commit = "true".to_string();
    let mut cfg_planning_tracking = "manual".to_string();
    let mut cfg_auto_push = "never".to_string();
    let mut cfg_verification_tier = "standard".to_string();
    let mut cfg_prefer_teams = "always".to_string();
    let mut cfg_max_tasks = "5".to_string();
    let mut cfg_context_compiler = "true".to_string();
    let mut cfg_compaction = "130000".to_string();

    if config_file.exists() {
        if let Ok(content) = fs::read_to_string(&config_file) {
            if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(v) = parsed.get("effort").and_then(|v| v.as_str()) { cfg_effort = v.to_string(); }
                if let Some(v) = parsed.get("autonomy").and_then(|v| v.as_str()) { cfg_autonomy = v.to_string(); }
                if let Some(v) = parsed.get("auto_commit").and_then(|v| v.as_bool()) { cfg_auto_commit = v.to_string(); }
                if let Some(v) = parsed.get("planning_tracking").and_then(|v| v.as_str()) { cfg_planning_tracking = v.to_string(); }
                if let Some(v) = parsed.get("auto_push").and_then(|v| v.as_str()) { cfg_auto_push = v.to_string(); }
                if let Some(v) = parsed.get("verification_tier").and_then(|v| v.as_str()) { cfg_verification_tier = v.to_string(); }
                if let Some(v) = parsed.get("prefer_teams").and_then(|v| v.as_str()) { cfg_prefer_teams = v.to_string(); }
                if let Some(v) = parsed.get("max_tasks_per_plan").and_then(|v| v.as_i64()) { cfg_max_tasks = v.to_string(); }
                if let Some(v) = parsed.get("context_compiler").and_then(|v| v.as_bool()) { cfg_context_compiler = v.to_string(); }
                if let Some(v) = parsed.get("compaction_threshold").and_then(|v| v.as_i64()) { cfg_compaction = v.to_string(); }
            }
        }
    }

    out.push_str(&format!("config_effort={}\n", cfg_effort));
    out.push_str(&format!("config_autonomy={}\n", cfg_autonomy));
    out.push_str(&format!("config_auto_commit={}\n", cfg_auto_commit));
    out.push_str(&format!("config_planning_tracking={}\n", cfg_planning_tracking));
    out.push_str(&format!("config_auto_push={}\n", cfg_auto_push));
    out.push_str(&format!("config_verification_tier={}\n", cfg_verification_tier));
    out.push_str(&format!("config_prefer_teams={}\n", cfg_prefer_teams));
    out.push_str(&format!("config_max_tasks_per_plan={}\n", cfg_max_tasks));
    out.push_str(&format!("config_context_compiler={}\n", cfg_context_compiler));
    out.push_str(&format!("config_compaction_threshold={}\n", cfg_compaction));

    // --- Codebase map status ---
    let has_codebase_map = planning_dir.join("codebase").join("META.md").exists();
    out.push_str(&format!("has_codebase_map={}\n", has_codebase_map));

    // --- Brownfield detection ---
    let mut brownfield = false;
    let git_output = Command::new("git")
        .args(["ls-files", "."])
        .current_dir(cwd)
        .output();
    if let Ok(output) = git_output {
        let stdout = String::from_utf8_lossy(&output.stdout);
        if !stdout.trim().is_empty() {
            brownfield = true;
        }
    }
    out.push_str(&format!("brownfield={}\n", brownfield));

    // --- Execution state ---
    let exec_state_file = planning_dir.join(".execution-state.json");
    let mut exec_state = "none".to_string();
    if exec_state_file.exists() {
        if let Ok(content) = fs::read_to_string(&exec_state_file) {
            if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(s) = parsed.get("status").and_then(|v| v.as_str()) {
                    exec_state = s.to_string();
                }
            }
        }
    }
    out.push_str(&format!("execution_state={}\n", exec_state));

    if suggest_route {
        let route = suggest_route_mode(
            next_phase_state, project_exists, &exec_state, brownfield, phase_count,
        );
        out.push_str(&format!("suggested_route={}\n", route.as_str()));
    }

    Ok((out.trim_end().to_string() + "\n", 0))
}

fn suggest_route_mode(
    next_phase_state: PhaseState,
    project_exists: bool,
    execution_state: &str,
    brownfield: bool,
    _phase_count: usize,
) -> Route {
    // Resume interrupted execution
    if execution_state == "running" {
        return Route::Resume;
    }
    // No project yet
    if !project_exists {
        if brownfield {
            return Route::Bootstrap;
        }
        return Route::Init;
    }
    // Match on PhaseState enum
    match next_phase_state {
        PhaseState::AllDone => Route::Archive,
        PhaseState::NeedsExecute => Route::Execute,
        PhaseState::NeedsPlanAndExecute | PhaseState::NoPhases => Route::Plan,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_phase_detect_empty() {
        let dir = tempdir().unwrap();
        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("planning_dir_exists=false"));
        assert!(out.contains("phase_count=0"));
        assert!(out.contains("brownfield=false"));
    }

    #[test]
    fn test_phase_detect_with_planning() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        
        let project_md = plan_dir.join("PROJECT.md");
        fs::write(&project_md, "Real project info").unwrap();

        let config_file = plan_dir.join("config.json");
        fs::write(&config_file, r#"{"effort":"low","auto_commit":false,"max_tasks_per_plan":3}"#).unwrap();

        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("planning_dir_exists=true"));
        assert!(out.contains("project_exists=true"));
        assert!(out.contains("config_effort=low"));
        assert!(out.contains("config_auto_commit=false"));
        assert!(out.contains("config_max_tasks_per_plan=3"));
        assert!(out.contains("next_phase_state=no_phases"));
    }

    #[test]
    fn test_phase_detect_active_milestone() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        
        let active_file = plan_dir.join("ACTIVE");
        fs::write(&active_file, "v2-launch").unwrap();
        
        // Before creating milestone dir
        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("active_milestone_error=true"));
        
        // Create milestone dir
        let phases_dir = plan_dir.join("milestones").join("v2-launch").join("phases");
        fs::create_dir_all(&phases_dir).unwrap();
        
        let (out2, _) = execute(&[], dir.path()).unwrap();
        assert!(out2.contains("active_milestone=v2-launch"));
        assert!(out2.contains("active_milestone_error=false"));
    }

    #[test]
    fn test_phase_detect_phases_needs_plan() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let phases_dir = plan_dir.join("phases");
        fs::create_dir_all(phases_dir.join("01-init")).unwrap();
        fs::create_dir_all(phases_dir.join("02-build")).unwrap();
        
        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("phase_count=2"));
        assert!(out.contains("next_phase=01"));
        assert!(out.contains("next_phase_state=needs_plan_and_execute"));
    }

    #[test]
    fn test_phase_detect_phases_needs_execute() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let phases_dir = plan_dir.join("phases");
        let p1 = phases_dir.join("01-init");
        fs::create_dir_all(&p1).unwrap();
        
        fs::write(p1.join("01-init-PLAN.md"), "plan").unwrap();
        
        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("next_phase=01"));
        assert!(out.contains("next_phase_state=needs_execute"));
        assert!(out.contains("next_phase_plans=1"));
        assert!(out.contains("next_phase_summaries=0"));
    }

    #[test]
    fn test_phase_detect_phases_all_done() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let phases_dir = plan_dir.join("phases");
        let p1 = phases_dir.join("01-init");
        fs::create_dir_all(&p1).unwrap();

        fs::write(p1.join("01-init-PLAN.md"), "plan").unwrap();
        fs::write(p1.join("01-init-SUMMARY.md"), "summary").unwrap();

        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(out.contains("phase_count=1"));
        assert!(out.contains("next_phase_state=all_done"));
    }

    #[test]
    fn test_suggest_route_no_planning() {
        let dir = tempdir().unwrap();
        let (out, _) = execute(&["--suggest-route".into()], dir.path()).unwrap();
        assert!(out.contains("suggested_route=init"), "Expected suggested_route=init, got: {}", out);
    }

    #[test]
    fn test_suggest_route_needs_plan() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        fs::write(plan_dir.join("PROJECT.md"), "Real project").unwrap();
        let phases_dir = plan_dir.join("phases");
        fs::create_dir_all(phases_dir.join("01-test")).unwrap();

        let (out, _) = execute(&["--suggest-route".into()], dir.path()).unwrap();
        assert!(out.contains("suggested_route=plan"), "Expected suggested_route=plan, got: {}", out);
    }

    #[test]
    fn test_suggest_route_needs_execute() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let phases_dir = plan_dir.join("phases");
        let p1 = phases_dir.join("01-init");
        fs::create_dir_all(&p1).unwrap();
        fs::write(plan_dir.join("PROJECT.md"), "Real project").unwrap();
        fs::write(p1.join("01-init-PLAN.md"), "plan").unwrap();

        let (out, _) = execute(&["--suggest-route".into()], dir.path()).unwrap();
        assert!(out.contains("suggested_route=execute"), "Expected suggested_route=execute, got: {}", out);
    }

    #[test]
    fn test_suggest_route_all_done() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        let phases_dir = plan_dir.join("phases");
        let p1 = phases_dir.join("01-init");
        fs::create_dir_all(&p1).unwrap();
        fs::write(plan_dir.join("PROJECT.md"), "Real project").unwrap();
        fs::write(p1.join("01-init-PLAN.md"), "plan").unwrap();
        fs::write(p1.join("01-init-SUMMARY.md"), "summary").unwrap();

        let (out, _) = execute(&["--suggest-route".into()], dir.path()).unwrap();
        assert!(out.contains("suggested_route=archive"), "Expected suggested_route=archive, got: {}", out);
    }

    #[test]
    fn test_suggest_route_execution_running() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        fs::write(plan_dir.join("PROJECT.md"), "Real project").unwrap();
        fs::write(plan_dir.join(".execution-state.json"), r#"{"status":"running"}"#).unwrap();

        let (out, _) = execute(&["--suggest-route".into()], dir.path()).unwrap();
        assert!(out.contains("suggested_route=resume"), "Expected suggested_route=resume, got: {}", out);
    }

    #[test]
    fn test_no_suggest_route_without_flag() {
        let dir = tempdir().unwrap();
        let (out, _) = execute(&[], dir.path()).unwrap();
        assert!(!out.contains("suggested_route"), "Output should not contain suggested_route without flag");
    }

    #[test]
    fn test_phase_state_as_str() {
        assert_eq!(PhaseState::NoPhases.as_str(), "no_phases");
        assert_eq!(PhaseState::NeedsPlanAndExecute.as_str(), "needs_plan_and_execute");
        assert_eq!(PhaseState::NeedsExecute.as_str(), "needs_execute");
        assert_eq!(PhaseState::AllDone.as_str(), "all_done");
    }

    #[test]
    fn test_route_as_str() {
        assert_eq!(Route::Init.as_str(), "init");
        assert_eq!(Route::Bootstrap.as_str(), "bootstrap");
        assert_eq!(Route::Resume.as_str(), "resume");
        assert_eq!(Route::Plan.as_str(), "plan");
        assert_eq!(Route::Execute.as_str(), "execute");
        assert_eq!(Route::Archive.as_str(), "archive");
    }
}
