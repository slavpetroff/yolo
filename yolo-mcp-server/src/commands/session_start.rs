use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};
use sysinfo::System;
use reqwest::blocking::Client;
use std::time::Duration;

pub fn execute_session_start(cwd: &Path) -> Result<(String, i32), String> {
    let planning_dir = cwd.join(".yolo-planning");
    let script_dir = cwd.join("scripts");
    let claude_dir = get_claude_dir(cwd);

    // 1. Dependency check (jq)
    // We actually don't NEED jq in Rust, but if bash scripts still run, maybe?
    // Rust doesn't need jq. So we can skip it, OR check it just to warn.
    if Command::new("jq").arg("--version").output().is_err() {
        let out = json!({
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": "YOLO: jq not found. Install: brew install jq (macOS) / apt install jq (Linux). All 17 YOLO quality gates are disabled until jq is installed -- no commit validation, no security filtering, no file guarding."
            }
        });
        return Ok((out.to_string(), 0));
    }

    // 2. Compaction check
    let cm_path = planning_dir.join(".compaction-marker");
    if cm_path.exists() {
        if let Ok(content) = fs::read_to_string(&cm_path) {
            let ts_str = content.trim();
            if let Ok(ts) = ts_str.parse::<u64>() {
                let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
                let age = now.saturating_sub(ts);
                if age < 60 {
                    return Ok(("".to_string(), 0));
                }
            }
        }
        let _ = fs::remove_file(&cm_path);
    }

    // 3. Config migration (native Rust)
    let config_path = planning_dir.join("config.json");
    if planning_dir.exists() && config_path.exists() {
        let defaults_path = cwd.join("config").join("defaults.json");
        let _ = super::migrate_config::migrate_config(&config_path, &defaults_path);
    }

    // 4. CLAUDE.md migration
    let claude_md_migrated = planning_dir.join(".claude-md-migrated");
    if planning_dir.exists() && !claude_md_migrated.exists() {
        let guard = cwd.join(".claude").join("CLAUDE.md");
        let root_claude = cwd.join("CLAUDE.md");
        if guard.exists() {
            if !root_claude.exists() {
                let _ = fs::rename(&guard, &root_claude);
            } else {
                let _ = fs::remove_file(&guard);
            }
        }
        let _ = fs::write(&claude_md_migrated, "1");
    }

    // 5. Todos hierarchy migration
    flatten_todos_migration(&planning_dir);

    // 6. Orphaned state migration (native Rust)
    let _ = super::migrate_orphaned_state::migrate_orphaned_state(&planning_dir);

    // 7. Config Cache & Warnings
    let (config_cache_done, flag_warnings) = write_config_cache_and_validate(&planning_dir);

    // 8. First run welcome
    let welcome_msg = check_first_run(&claude_dir);

    // 9. Update Check
    let update_msg = check_for_updates(&script_dir);

    // 10. StatusLine & Tmux migration
    migrate_statusline_and_tmux(&claude_dir, &planning_dir);

    // 11. Cache cleanup and syncing
    cleanup_and_sync_cache(&claude_dir);

    // 12. Hook installation & stale team cleanup (native Rust)
    let _ = super::install_hooks::install_hooks();
    {
        let log_file = planning_dir.join(".hook-errors.log");
        super::clean_stale_teams::clean_stale_teams(&claude_dir, &log_file);
    }
    
    // 13. Reconcile execution state & Orphan Agents
    let state_msg = reconcile_execution_state(&planning_dir);
    
    cleanup_orphaned_agents(&planning_dir);

    // 14. Tmux watchdog (native Rust)
    if let Some(session) = super::tmux_watchdog::get_tmux_session() {
        let _ = super::tmux_watchdog::spawn_watchdog(&planning_dir, &session);
    }

    // 15. Determine Next Action & Build Context
    let ctx = build_context(&cwd, &planning_dir, &state_msg);

    let out = json!({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": format!("{}{}{}{}", welcome_msg, ctx, update_msg, flag_warnings)
        }
    });

    Ok((out.to_string(), 0))
}

fn flatten_todos_migration(planning_dir: &Path) {
    let flag = planning_dir.join(".todo-flat-migrated");
    if !planning_dir.exists() || flag.exists() {
        return;
    }

    let mut files = vec![planning_dir.join("STATE.md")];
    let ms_dir = planning_dir.join("milestones");
    if ms_dir.exists() {
        if let Ok(entries) = fs::read_dir(ms_dir) {
            for entry in entries.flatten() {
                let state_file = entry.path().join("STATE.md");
                if state_file.exists() {
                    files.push(state_file);
                }
            }
        }
    }

    let mut all_ok = true;
    for file in files {
        if let Ok(content) = fs::read_to_string(&file) {
            if content.contains("### Pending Todos") {
                let new_content = content.replace("### Pending Todos\n", "").replace("### Pending Todos", "");
                if fs::write(&file, new_content).is_err() {
                    all_ok = false;
                }
            }
        }
    }

    if all_ok {
        let _ = fs::write(flag, "1");
    }
}

fn write_config_cache_and_validate(planning_dir: &Path) -> (bool, String) {
    let mut config_val: Value = json!({});
    let mut warnings = String::new();

    let config_path = planning_dir.join("config.json");
    if let Ok(content) = fs::read_to_string(&config_path) {
        if let Ok(val) = serde_json::from_str(&content) {
            config_val = val;
        }
    }

    // Write Cache (native uid)
    let uid = unsafe { libc::getuid() };
    let cache_path = format!("/tmp/yolo-config-cache-{}", uid);
    let get_str = |key: &str, def: &str| -> String {
        config_val.get(key).and_then(|v| v.as_str()).unwrap_or(def).to_string()
    };
    let get_bool = |key: &str, def: bool| -> bool {
        config_val.get(key).and_then(|v| v.as_bool()).unwrap_or(def)
    };
    
    // Convert context_compiler to bool: if null then true else .context_compiler
    let ctx_compiler = match config_val.get("context_compiler") {
        Some(Value::Bool(b)) => *b,
        _ => true,
    };

    let cache_content = format!(
        "YOLO_EFFORT={}\nYOLO_AUTONOMY={}\nYOLO_PLANNING_TRACKING={}\nYOLO_AUTO_PUSH={}\nYOLO_CONTEXT_COMPILER={}\n\
         YOLO_V3_DELTA_CONTEXT={}\nYOLO_V3_CONTEXT_CACHE={}\nYOLO_V3_PLAN_RESEARCH_PERSIST={}\nYOLO_V3_METRICS={}\n\
         YOLO_V3_CONTRACT_LITE={}\nYOLO_V3_LOCK_LITE={}\nYOLO_V3_VALIDATION_GATES={}\nYOLO_V3_SMART_ROUTING={}\n\
         YOLO_V3_EVENT_LOG={}\nYOLO_V3_SCHEMA_VALIDATION={}\nYOLO_V3_SNAPSHOT_RESUME={}\nYOLO_V3_LEASE_LOCKS={}\n\
         YOLO_V3_EVENT_RECOVERY={}\nYOLO_V3_MONOREPO_ROUTING={}\nYOLO_V2_HARD_CONTRACTS={}\nYOLO_V2_HARD_GATES={}\n\
         YOLO_V2_TYPED_PROTOCOL={}\nYOLO_V2_ROLE_ISOLATION={}\nYOLO_V2_TWO_PHASE_COMPLETION={}\nYOLO_V2_TOKEN_BUDGETS={}\n",
         get_str("effort", "balanced"), get_str("autonomy", "standard"), get_str("planning_tracking", "manual"),
         get_str("auto_push", "never"), ctx_compiler, get_bool("v3_delta_context", false), get_bool("v3_context_cache", false),
         get_bool("v3_plan_research_persist", false), get_bool("v3_metrics", false), get_bool("v3_contract_lite", false),
         get_bool("v3_lock_lite", false), get_bool("v3_validation_gates", false), get_bool("v3_smart_routing", false),
         get_bool("v3_event_log", false), get_bool("v3_schema_validation", false), get_bool("v3_snapshot_resume", false),
         get_bool("v3_lease_locks", false), get_bool("v3_event_recovery", false), get_bool("v3_monorepo_routing", false),
         get_bool("v2_hard_contracts", false), get_bool("v2_hard_gates", false), get_bool("v2_typed_protocol", false),
         get_bool("v2_role_isolation", false), get_bool("v2_two_phase_completion", false), get_bool("v2_token_budgets", false)
    );

    let cache_done = fs::write(&cache_path, cache_content).is_ok();

    // Flag validations
    let v2_hard_gates = get_bool("v2_hard_gates", false);
    let v2_hard_contracts = get_bool("v2_hard_contracts", false);
    let v3_event_recovery = get_bool("v3_event_recovery", false);
    let v3_event_log = get_bool("v3_event_log", false);
    let v2_two_phase = get_bool("v2_two_phase_completion", false);

    if v2_hard_gates && !v2_hard_contracts {
        warnings.push_str(" WARNING: v2_hard_gates requires v2_hard_contracts -- enable v2_hard_contracts first or contract_compliance gate will fail.");
    }
    if v3_event_recovery && !v3_event_log {
        warnings.push_str(" WARNING: v3_event_recovery requires v3_event_log -- enable v3_event_log first or event recovery will find no events.");
    }
    if v2_two_phase && !v3_event_log {
        warnings.push_str(" WARNING: v2_two_phase_completion requires v3_event_log -- enable v3_event_log first or completion events will be lost.");
    }

    (cache_done, warnings)
}

fn check_first_run(claude_dir: &Path) -> String {
    let marker = claude_dir.join(".yolo-welcomed");
    if !marker.exists() {
        let _ = fs::create_dir_all(claude_dir);
        let _ = fs::write(&marker, "");
        return "FIRST RUN -- Display this welcome to the user verbatim: Welcome to YOLO -- Vibe Better with Claude Code. You're not an engineer anymore. You're a prompt jockey with commit access. At least do it properly. Quick start: /yolo:vibe -- describe your project and YOLO handles the rest. Type /yolo:help for the full story. --- ".to_string();
    }
    String::new()
}

fn check_for_updates(script_dir: &Path) -> String {
    let uid = unsafe { libc::getuid() };
    let cache_path = format!("/tmp/yolo-update-check-{}", uid);
    let mut local_ver = "0.0.0".to_string();
    let mut remote_ver = "0.0.0".to_string();

    let plugin_json = script_dir.join("..").join(".claude-plugin").join("plugin.json");
    if let Ok(content) = fs::read_to_string(&plugin_json) {
        if let Ok(val) = serde_json::from_str::<Value>(&content) {
            if let Some(v) = val.get("version").and_then(|v| v.as_str()) {
                local_ver = v.to_string();
            }
        }
    }

    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let mut fetch = true;
    
    if let Ok(meta) = fs::metadata(&cache_path) {
        if let Ok(mtime) = meta.modified() {
            let mt = mtime.duration_since(UNIX_EPOCH).unwrap().as_secs();
            if now.saturating_sub(mt) <= 86400 {
                fetch = false;
                if let Ok(content) = fs::read_to_string(&cache_path) {
                    let parts: Vec<&str> = content.split('|').collect();
                    if parts.len() == 2 {
                        local_ver = parts[0].to_string();
                        remote_ver = parts[1].trim().to_string();
                    }
                }
            }
        }
    }

    if fetch {
        let client = Client::builder().timeout(Duration::from_secs(3)).build().unwrap();
        if let Ok(res) = client.get("https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-yolo/main/.claude-plugin/plugin.json").send() {
            if let Ok(content) = res.text() {
                if let Ok(val) = serde_json::from_str::<Value>(&content) {
                    if let Some(v) = val.get("version").and_then(|v| v.as_str()) {
                        remote_ver = v.to_string();
                    }
                }
            }
        }
        let _ = fs::write(&cache_path, format!("{}|{}", local_ver, remote_ver));
    }

    if remote_ver != "0.0.0" && remote_ver != local_ver {
        return format!(" UPDATE AVAILABLE: v{} -> v{}. Run /yolo:update to upgrade.", local_ver, remote_ver);
    }
    String::new()
}

fn migrate_statusline_and_tmux(claude_dir: &Path, planning_dir: &Path) {
    let settings = claude_dir.join("settings.json");
    if settings.exists() {
        if let Ok(content) = fs::read_to_string(&settings) {
            if let Ok(mut val) = serde_json::from_str::<Value>(&content) {
                let mut changed = false;
                
                // migrate statusLine
                let mut sl_val = None;
                if let Some(sl) = val.get("statusLine") {
                    sl_val = Some(sl.clone());
                }
                
                if let Some(sl) = sl_val {
                    let cmd_str = sl.get("command").and_then(|v| v.as_str()).unwrap_or("");
                    if cmd_str.contains("for f in") && cmd_str.contains("yolo-statusline") {
                        let new_cmd = "bash -c 'f=$(ls -1 \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/yolo-marketplace/yolo/*/scripts/yolo-statusline.sh 2>/dev/null | sort -V | tail -1) && [ -f \"$f\" ] && exec bash \"$f\"'";
                        
                        if let Some(obj) = val.as_object_mut() {
                            obj.insert("statusLine".to_string(), json!({
                                "type": "command",
                                "command": new_cmd
                            }));
                            changed = true;
                        }
                    }
                }
                
                // tmux mode
                if let Some(mode) = val.get("teammateMode").and_then(|v| v.as_str()) {
                    if mode == "in-process" {
                        if let Some(obj) = val.as_object_mut() {
                            obj.insert("teammateMode".to_string(), json!("auto"));
                            changed = true;
                        }
                    }
                }
                
                if changed {
                    let _ = fs::write(&settings, serde_json::to_string_pretty(&val).unwrap());
                }
            }
        }
    }
    
    // clean stale marker
    let marker = planning_dir.join(".tmux-mode-patched");
    let _ = fs::remove_file(marker);
}

fn cleanup_and_sync_cache(claude_dir: &Path) {
    let cache_dir = claude_dir.join("plugins/cache/yolo-marketplace/yolo");
    let cleanup_lock = PathBuf::from("/tmp/yolo-cache-cleanup-lock");
    
    // Clean old caches
    if cache_dir.exists() && fs::create_dir(&cleanup_lock).is_ok() {
        let mut dirs: Vec<PathBuf> = Vec::new();
        if let Ok(entries) = fs::read_dir(&cache_dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    dirs.push(entry.path());
                }
            }
        }
        dirs.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
        
        if dirs.len() > 1 {
            for dir in dirs.iter().take(dirs.len() - 1) {
                let _ = fs::remove_dir_all(dir);
            }
        }
        let _ = fs::remove_dir(&cleanup_lock);
    }
    
    // Integrity check
    if cache_dir.exists() {
        let mut dirs: Vec<PathBuf> = Vec::new();
        if let Ok(entries) = fs::read_dir(&cache_dir) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    dirs.push(entry.path());
                }
            }
        }
        dirs.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
        
        if let Some(latest) = dirs.last() {
            let required = vec![
                "commands/init.md",
                ".claude-plugin/plugin.json",
                "VERSION",
                "config/defaults.json"
            ];
            
            let mut ok = true;
            for req in required {
                if !latest.join(req).exists() {
                    ok = false;
                    break;
                }
            }
            if !ok {
                let _ = fs::remove_dir_all(&cache_dir);
            }
        }
    }
    
    // Auto-sync stale marketplace
    let mkt_dir = claude_dir.join("plugins/marketplaces/yolo-marketplace");
    if mkt_dir.join(".git").exists() && cache_dir.exists() {
        let mut mkt_ver = "0".to_string();
        let mut cache_ver = "0".to_string();
        
        if let Ok(content) = fs::read_to_string(mkt_dir.join(".claude-plugin/plugin.json")) {
            if let Ok(val) = serde_json::from_str::<Value>(&content) {
                mkt_ver = val.get("version").and_then(|v| v.as_str()).unwrap_or("0").to_string();
            }
        }
        
        let mut latest_cache = None;
        if let Ok(entries) = fs::read_dir(&cache_dir) {
            let mut d = Vec::new();
            for e in entries.flatten() {
                if e.path().is_dir() { d.push(e.path()); }
            }
            d.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
            latest_cache = d.last().cloned();
        }
        
        if let Some(lc) = &latest_cache {
            if let Ok(content) = fs::read_to_string(lc.join(".claude-plugin/plugin.json")) {
                if let Ok(val) = serde_json::from_str::<Value>(&content) {
                    cache_ver = val.get("version").and_then(|v| v.as_str()).unwrap_or("0").to_string();
                }
            }
        }
        
        if mkt_ver != cache_ver && cache_ver != "0" {
            // Background git fetch + merge
            let pd = mkt_dir.clone();
            std::thread::spawn(move || {
                let _ = Command::new("git").arg("fetch").arg("origin").arg("--quiet").current_dir(&pd).output();
                if let Ok(diff) = Command::new("git").arg("diff").arg("--quiet").current_dir(&pd).output() {
                    if diff.status.success() {
                        let _ = Command::new("git").arg("merge").arg("--ff-only").arg("origin/main").arg("--quiet").current_dir(&pd).output();
                    }
                }
            });
        }
    }
    
    // Sync global commands mirror
    let yolo_global = claude_dir.join("commands/yolo");
    let mut latest_cache = None;
    if let Ok(entries) = fs::read_dir(&cache_dir) {
        let mut d = Vec::new();
        for e in entries.flatten() { if e.path().is_dir() { d.push(e.path()); } }
        d.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
        latest_cache = d.last().cloned();
    }
    
    if let Some(lc) = latest_cache {
        let cache_cmds = lc.join("commands");
        if cache_cmds.exists() {
            let _ = fs::create_dir_all(&yolo_global);
            if let Ok(entries) = fs::read_dir(&yolo_global) {
                for entry in entries.flatten() {
                    let base = entry.file_name();
                    if entry.path().is_file() && !cache_cmds.join(&base).exists() {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
            if let Ok(entries) = fs::read_dir(&cache_cmds) {
                for entry in entries.flatten() {
                    if entry.path().is_file() {
                        if let Some(name) = entry.file_name().to_str() {
                            if name.ends_with(".md") {
                                let _ = fs::copy(entry.path(), yolo_global.join(name));
                            }
                        }
                    }
                }
            }
        }
    }
}

fn reconcile_execution_state(planning_dir: &Path) -> String {
    let mut msg = String::new();
    let es = planning_dir.join(".execution-state.json");
    if es.exists() {
        if let Ok(content) = fs::read_to_string(&es) {
            if let Ok(mut val) = serde_json::from_str::<Value>(&content) {
                let status = val.get("status").and_then(|v| v.as_str()).unwrap_or("");
                if status == "running" {
                    let phase = val.get("phase").and_then(|v| v.as_str()).unwrap_or("");
                    let mut phase_dir = None;
                    if !phase.is_empty() {
                        let prefix = format!("{}-", phase);
                        if let Ok(entries) = fs::read_dir(planning_dir.join("phases")) {
                            for entry in entries.flatten() {
                                if entry.file_name().to_string_lossy().starts_with(&prefix) {
                                    phase_dir = Some(entry.path());
                                    break;
                                }
                            }
                        }
                    }
                    if let Some(pd) = phase_dir {
                        let plan_count = val.get("plans").and_then(|v| v.as_array()).map(|a| a.len()).unwrap_or(1);
                        let mut summary_count = 0;
                        if let Ok(entries) = fs::read_dir(&pd) {
                            for entry in entries.flatten() {
                                if entry.file_name().to_string_lossy().ends_with("-SUMMARY.md") {
                                    summary_count += 1;
                                }
                            }
                        }
                        if summary_count >= plan_count && plan_count > 0 {
                            if let Some(obj) = val.as_object_mut() {
                                obj.insert("status".to_string(), json!("complete"));
                            }
                            let _ = fs::write(&es, serde_json::to_string_pretty(&val).unwrap());
                            msg.push_str(" Build state: complete (recovered).");
                        } else {
                            msg.push_str(&format!(" Build state: interrupted ({}/{} plans).", summary_count, plan_count));
                        }
                    }
                }
            }
        }
    }
    msg
}

fn cleanup_orphaned_agents(planning_dir: &Path) {
    if !planning_dir.exists() {
        return;
    }
    
    let current_pid = sysinfo::get_current_pid().unwrap_or(sysinfo::Pid::from_u32(0));
    let mut sys = System::new_all();
    sys.refresh_all();
    
    let mut targets = Vec::new();
    for (pid, process) in sys.processes() {
        if *pid == current_pid { continue; }
        
        let ppid = process.parent().map(|p| p.as_u32()).unwrap_or(0);
        if ppid == 1 || ppid == 0 {
            #[allow(unused_imports)]
            use std::borrow::Cow;
            
            // `sysinfo` v0.30+ process.name() returns &OsStr, so we convert.
            #[allow(clippy::unnecessary_cast)]
            let name = process.name().to_string_lossy();
            if name.contains("claude") {
                targets.push(*pid);
            }
        }
    }

    if targets.is_empty() { return; }
    
    let log_file = planning_dir.join(".hook-errors.log");
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let _ = fs::OpenOptions::new().create(true).append(true).open(&log_file).map(|mut f| {
        use std::io::Write;
        let _ = writeln!(f, "[{}] Orphan cleanup: found {} orphaned claude process(es)", ts, targets.len());
    });

    for pid in &targets {
        if let Some(process) = sys.process(*pid) {
            let _ = fs::OpenOptions::new().create(true).append(true).open(&log_file).map(|mut f| {
                use std::io::Write;
                let _ = writeln!(f, "[{}] Terminating orphan claude process PID={} (SIGTERM)", ts, pid);
            });
            process.kill_with(sysinfo::Signal::Term);
        }
    }

    std::thread::sleep(std::time::Duration::from_secs(2));
    sys.refresh_all(); 

    for pid in &targets {
        if let Some(process) = sys.process(*pid) {
            let _ = fs::OpenOptions::new().create(true).append(true).open(&log_file).map(|mut f| {
                use std::io::Write;
                let _ = writeln!(f, "[{}] Orphan claude process PID={} survived SIGTERM, sending SIGKILL", ts, pid);
            });
            process.kill_with(sysinfo::Signal::Kill);
        }
    }
}

fn build_context(cwd: &Path, planning_dir: &Path, state_msg: &str) -> String {
    let mut ctx = String::from("YOLO project detected.");

    let mut config_effort = "balanced".to_string();
    let mut config_autonomy = "standard".to_string();
    let mut config_auto_commit = true;
    let mut config_planning_tracking = "manual".to_string();
    let mut config_auto_push = "never".to_string();
    let mut config_verification = "standard".to_string();
    let mut config_prefer_teams = "always".to_string();
    let mut config_max_tasks = 5;

    let config_file = planning_dir.join("config.json");
    if let Ok(content) = fs::read_to_string(&config_file) {
        if let Ok(val) = serde_json::from_str::<Value>(&content) {
            config_effort = val.get("effort").and_then(|v| v.as_str()).unwrap_or("balanced").to_string();
            config_autonomy = val.get("autonomy").and_then(|v| v.as_str()).unwrap_or("standard").to_string();
            config_auto_commit = match val.get("auto_commit") {
                Some(Value::Bool(b)) => *b,
                _ => true,
            };
            config_planning_tracking = val.get("planning_tracking").and_then(|v| v.as_str()).unwrap_or("manual").to_string();
            config_auto_push = val.get("auto_push").and_then(|v| v.as_str()).unwrap_or("never").to_string();
            config_verification = val.get("verification_tier").and_then(|v| v.as_str()).unwrap_or("standard").to_string();
            config_prefer_teams = val.get("prefer_teams").and_then(|v| v.as_str()).unwrap_or("always").to_string();
            config_max_tasks = val.get("max_tasks_per_plan").and_then(|v| v.as_i64()).unwrap_or(5);
        }
    }

    let mut milestone_slug = "none".to_string();
    let active_file = planning_dir.join("ACTIVE");
    if active_file.exists() {
        if let Ok(content) = fs::read_to_string(&active_file) {
            milestone_slug = content.trim().to_string();
        }
    }

    let milestone_dir = if milestone_slug != "none" {
        let md = planning_dir.join("milestones").join(&milestone_slug);
        if md.exists() { md } else { planning_dir.to_path_buf() }
    } else {
        planning_dir.to_path_buf()
    };
    
    let phases_dir = if milestone_slug != "none" && milestone_dir.join("phases").exists() {
        milestone_dir.join("phases")
    } else {
        planning_dir.join("phases")
    };

    let state_file = milestone_dir.join("STATE.md");
    let mut phase_pos = "unknown".to_string();
    let mut phase_total = "unknown".to_string();
    let mut phase_name = "unknown".to_string();
    let mut phase_status = "unknown".to_string();
    let mut progress_pct = "0".to_string();

    if let Ok(content) = fs::read_to_string(&state_file) {
        for line in content.lines() {
            if line.starts_with("Phase:") {
                let parts: Vec<&str> = line.split("of").collect();
                if parts.len() == 2 {
                    phase_pos = parts[0].replace("Phase:", "").trim().to_string();
                    let right_parts: Vec<&str> = parts[1].split('(').collect();
                    if right_parts.len() == 2 {
                        phase_total = right_parts[0].trim().to_string();
                        phase_name = right_parts[1].replace(")", "").trim().to_string();
                    }
                }
            } else if line.starts_with("Status:") {
                phase_status = line.replace("Status:", "").trim().to_string();
            } else if line.starts_with("Progress:") {
                progress_pct = line.replace("Progress:", "").replace("%", "").trim().to_string();
            }
        }
    }

    ctx.push_str(&format!(" Milestone: {}.", milestone_slug));
    ctx.push_str(&format!(" Phase: {}/{} ({}) -- {}.", phase_pos, phase_total, phase_name, phase_status));
    ctx.push_str(&format!(" Progress: {}%.", progress_pct));
    ctx.push_str(&format!(" Config: effort={}, autonomy={}, auto_commit={}, planning_tracking={}, auto_push={}, verification={}, prefer_teams={}, max_tasks={}.", config_effort, config_autonomy, config_auto_commit, config_planning_tracking, config_auto_push, config_verification, config_prefer_teams, config_max_tasks));
    if !state_msg.is_empty() {
        ctx.push_str(state_msg);
    }

    let mut next_action = String::new();
    if !planning_dir.join("PROJECT.md").exists() {
        next_action = "/yolo:init".to_string();
    } else if !phases_dir.exists() || fs::read_dir(&phases_dir).map(|mut r| r.next().is_none()).unwrap_or(true) {
        next_action = "/yolo:vibe (needs scoping)".to_string();
    } else {
        let mut exec_running = false;
        let es_files = vec![planning_dir.join(".execution-state.json"), milestone_dir.join(".execution-state.json")];
        for es in es_files {
            if let Ok(c) = fs::read_to_string(&es) {
                if let Ok(v) = serde_json::from_str::<Value>(&c) {
                    if v.get("status").and_then(|v| v.as_str()).unwrap_or("") == "running" {
                        exec_running = true;
                        break;
                    }
                }
            }
        }
        if exec_running {
            next_action = "/yolo:vibe (build interrupted, will resume)".to_string();
        } else {
            let mut all_done = true;
            if let Ok(entries) = fs::read_dir(&phases_dir) {
                let mut d = Vec::new();
                for e in entries.flatten() {
                    if e.path().is_dir() { d.push(e.path()); }
                }
                d.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
                
                for pdir in d {
                    let pname = pdir.file_name().unwrap_or_default().to_string_lossy().to_string();
                    let mut plan_c = 0;
                    let mut sum_c = 0;
                    if let Ok(sub) = fs::read_dir(&pdir) {
                        for se in sub.flatten() {
                            let sn = se.file_name().to_string_lossy().to_string();
                            if sn.ends_with("-PLAN.md") { plan_c += 1; }
                            if sn.ends_with("-SUMMARY.md") { sum_c += 1; }
                        }
                    }
                    if plan_c == 0 {
                        let pnum = pname.split('-').next().unwrap_or("?");
                        next_action = format!("/yolo:vibe (Phase {} needs planning)", pnum);
                        all_done = false;
                        break;
                    } else if sum_c < plan_c {
                        let pnum = pname.split('-').next().unwrap_or("?");
                        next_action = format!("/yolo:vibe (Phase {} planned, needs execution)", pnum);
                        all_done = false;
                        break;
                    }
                }
            }
            if all_done {
                next_action = "/yolo:vibe --archive".to_string();
            }
        }
    }

    ctx.push_str(&format!(" Next: {}.", next_action));
    ctx
}

fn get_claude_dir(cwd: &Path) -> PathBuf {
    if let Ok(val) = env::var("CLAUDE_CONFIG_DIR") {
        if !val.is_empty() {
            return PathBuf::from(val);
        }
    }
    if let Ok(val) = env::var("HOME") {
        return PathBuf::from(val).join(".claude");
    }
    cwd.join(".claude") // fallback
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use serde_json::json;

    #[test]
    fn test_flatten_todos() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        
        let state_path = plan_dir.join("STATE.md");
        fs::write(&state_path, "## Todos\n### Pending Todos\n- task 1\n- task 2\n").unwrap();
        
        flatten_todos_migration(&plan_dir);
        
        // Marker should exist
        assert!(plan_dir.join(".todo-flat-migrated").exists());
        
        // File content should be updated
        let content = fs::read_to_string(&state_path).unwrap();
        assert!(!content.contains("### Pending Todos"));
        assert!(content.contains("- task 1"));
    }

    #[test]
    fn test_write_config_cache() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        
        let config_path = plan_dir.join("config.json");
        fs::write(&config_path, json!({
            "v2_hard_gates": true,
            "v2_hard_contracts": false
        }).to_string()).unwrap();
        
        let (done, warnings) = write_config_cache_and_validate(&plan_dir);
        assert!(done);
        assert!(warnings.contains("v2_hard_gates requires v2_hard_contracts"));
    }

    #[test]
    fn test_check_first_run() {
        let dir = tempdir().unwrap();
        let marker = dir.path().join(".yolo-welcomed");
        
        // First run
        let msg = check_first_run(dir.path());
        assert!(msg.contains("FIRST RUN"));
        assert!(marker.exists());
        
        // Second run
        let msg2 = check_first_run(dir.path());
        assert!(msg2.is_empty());
    }

    #[test]
    fn test_reconcile_execution_state() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        fs::create_dir(plan_dir.join("phases")).unwrap();

        let es = plan_dir.join(".execution-state.json");
        fs::write(&es, json!({
            "status": "running",
            "phase": "1",
            "plans": [{}, {}]
        }).to_string()).unwrap();

        let phase_dir = plan_dir.join("phases").join("1-Test");
        fs::create_dir(&phase_dir).unwrap();
        fs::write(phase_dir.join("1-PLAN.md"), "").unwrap();
        fs::write(phase_dir.join("1-SUMMARY.md"), "").unwrap();

        // Only 1 summary, but 2 plans => interrupted
        let msg = reconcile_execution_state(&plan_dir);
        assert!(msg.contains("interrupted (1/2 plans)"));

        // Now add 2nd summary => complete
        fs::write(phase_dir.join("2-PLAN.md"), "").unwrap();
        fs::write(phase_dir.join("2-SUMMARY.md"), "").unwrap();

        let msg2 = reconcile_execution_state(&plan_dir);
        assert!(msg2.contains("Build state: complete (recovered)"));
    }

    #[test]
    fn test_native_config_migration_integration() {
        // Verify session_start's config migration path uses native module
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir(&config_dir).unwrap();

        let defaults = json!({"effort": "balanced", "auto_push": "never"});
        fs::write(config_dir.join("defaults.json"), defaults.to_string()).unwrap();

        let config = json!({"agent_teams": true});
        let config_path = plan_dir.join("config.json");
        fs::write(&config_path, config.to_string()).unwrap();

        // Call the native migration
        let result = super::super::migrate_config::migrate_config(
            &config_path,
            &config_dir.join("defaults.json"),
        );
        assert!(result.is_ok());

        let migrated: Value =
            serde_json::from_str(&fs::read_to_string(&config_path).unwrap()).unwrap();
        assert_eq!(migrated["prefer_teams"], "always");
        assert!(migrated.get("agent_teams").is_none());
        assert_eq!(migrated["effort"], "balanced");
    }

    #[test]
    fn test_native_orphaned_state_integration() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join("planning");
        let ms = plan_dir.join("milestones").join("v1");
        fs::create_dir_all(&ms).unwrap();
        fs::write(
            ms.join("STATE.md"),
            "# State\n\n**Project:** TestApp\n\n## Todos\n- Fix bug\n",
        )
        .unwrap();

        let result = super::super::migrate_orphaned_state::migrate_orphaned_state(&plan_dir);
        assert!(result.unwrap());
        assert!(plan_dir.join("STATE.md").exists());

        let content = fs::read_to_string(plan_dir.join("STATE.md")).unwrap();
        assert!(content.contains("TestApp"));
        assert!(content.contains("Fix bug"));
    }

    #[test]
    fn test_build_context_no_project() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();

        let ctx = build_context(dir.path(), &plan_dir, "");
        assert!(ctx.contains("YOLO project detected"));
        assert!(ctx.contains("Next: /yolo:init"));
    }

    #[test]
    fn test_build_context_with_project_no_phases() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        fs::write(plan_dir.join("PROJECT.md"), "# My Project").unwrap();

        let ctx = build_context(dir.path(), &plan_dir, "");
        assert!(ctx.contains("needs scoping"));
    }

    #[test]
    fn test_uid_is_native() {
        // Verify libc::getuid works (replaces Command::new("id"))
        let uid = unsafe { libc::getuid() };
        assert!(uid < 100_000); // sanity check
    }
}
