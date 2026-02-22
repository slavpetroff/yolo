use rusqlite::Connection;
use std::env;
use std::io::Read;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use crate::commands::{state_updater, statusline, hard_gate, session_start, metrics_report, token_baseline, token_budget, token_economics_report, lock_lite, lease_lock, two_phase_complete, bootstrap_claude, bootstrap_project, bootstrap_requirements, bootstrap_roadmap, bootstrap_state, suggest_next, list_todos, phase_detect, detect_stack, infer_project_context, planning_git, resolve_model, resolve_turns, log_event, collect_metrics, compress_context, prune_completed, generate_contract, contract_revision, assess_plan_risk, resolve_gate_policy, smart_route, route_monorepo, snapshot_resume, persist_state, recover_state, compile_rolling_summary, generate_gsd_index, generate_incidents, artifact_registry, infer_gsd_summary, cache_context, cache_nuke, delta_files, help_output, bump_version, doctor_cleanup, auto_repair, rollout_stage, verify, install_hooks, migrate_config, migrate_orphaned_state, tier_context, clean_stale_teams, tmux_watchdog, verify_init_todo, verify_vibe, verify_claude_bootstrap, pre_push_hook, validate_plan, review_plan, check_regression, commit_lint, diff_against_plan, validate_requirements, verify_plan_completion};
use crate::hooks;
pub fn generate_report(total_calls: i64, compile_calls: i64, avg_output_length: f64, unique_sessions: Option<i64>) -> String {
    let mut out = String::new();
    out.push_str("============================================================\n");
    out.push_str("             YOLO EXPERT ROI & TELEMETRY DASHBOARD           \n");
    out.push_str("============================================================\n");
    out.push_str(&format!("Total Intercepted Tool Calls: {}\n", total_calls));
    out.push_str(&format!("Context Compilations (Cache hits): {}\n", compile_calls));

    let prefix_size = avg_output_length;
    let is_measured = avg_output_length != 80_000.0;
    let cold_cost_per_m = 3.00;
    let caching_write_cost_per_m = 3.75;
    let caching_read_cost_per_m = 0.30;

    let total_tokens_pushed = compile_calls as f64 * prefix_size;
    let expected_cold_cost = (total_tokens_pushed / 1_000_000.0) * cold_cost_per_m;

    // Session-based write/read split when available, else fallback to 1:10
    let (writes, reads) = if let Some(sessions) = unique_sessions {
        let w = (sessions as f64).max(1.0);
        let r = (compile_calls as f64 - w).max(0.0);
        (w, r)
    } else {
        let w = (compile_calls as f64 / 10.0).max(1.0);
        let r = compile_calls as f64 - w;
        (w, r)
    };

    let actual_hot_cost = ((writes * prefix_size) / 1_000_000.0) * caching_write_cost_per_m +
                          ((reads * prefix_size) / 1_000_000.0) * caching_read_cost_per_m;
    let savings = expected_cold_cost - actual_hot_cost;

    let label = if is_measured { "Measured" } else { "Projected (no data)" };
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("Token Efficiency Analysis ({})\n", label));
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("Avg Prefix Size (tokens):        {:.0}\n", prefix_size));
    out.push_str(&format!("Estimated Total Tokens Pushed:   {:.0} million\n", total_tokens_pushed / 1_000_000.0));
    out.push_str(&format!("Expected Cold Cache Cost:        ${:.2}\n", expected_cold_cost));
    out.push_str(&format!("Actual Hot Cache Cost (with Prefix): ${:.2}\n", actual_hot_cost));
    out.push_str(&format!("Cache Writes / Reads:            {:.0} / {:.0}\n", writes, reads));
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("TOTAL SAVINGS:                   +${:.2}\n", savings));
    out.push_str("============================================================\n");
    out
}

pub fn run_cli(args: Vec<String>, db_path: PathBuf) -> Result<(String, i32), String> {
    if args.len() < 2 {
        return Err("Usage: yolo <command> [args...]".to_string());
    }

    match args[1].as_str() {
        "report" => {
            if !db_path.exists() {
                return Err("No telemetry data found! Connect the MCP server and run some tasks first.".to_string());
            }

            let conn = Connection::open(&db_path).map_err(|e| format!("Failed to open Telemetry DB: {}", e))?;

            let count_query = "SELECT COUNT(*) FROM tool_usage";
            let total_calls: i64 = conn.query_row(count_query, [], |row| row.get(0)).unwrap_or(0);

            let compile_query = "SELECT COUNT(*) FROM tool_usage WHERE tool_name = 'compile_context'";
            let compile_calls: i64 = conn.query_row(compile_query, [], |row| row.get(0)).unwrap_or(0);

            // Query measured avg output length; fall back to 80K if no data
            let avg_output_length: f64 = conn
                .query_row(
                    "SELECT AVG(output_length) FROM tool_usage WHERE tool_name = 'compile_context' AND output_length > 0",
                    [],
                    |row| row.get::<_, f64>(0),
                )
                .unwrap_or(80_000.0);

            // Query unique sessions for write/read split; None if column missing
            let unique_sessions: Option<i64> = conn
                .query_row(
                    "SELECT COUNT(DISTINCT session_id) FROM tool_usage WHERE tool_name = 'compile_context'",
                    [],
                    |row| row.get(0),
                )
                .ok()
                .filter(|&v: &i64| v > 0);

            Ok((generate_report(total_calls, compile_calls, avg_output_length, unique_sessions), 0))
        }
        "report-tokens" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_economics_report::execute(&args, &cwd, &db_path)
        }
        "update-state" => {
            if args.len() < 3 {
                return Err("Usage: yolo update-state <file_path>".to_string());
            }
            state_updater::update_state(&args[2]).map(|s| (s, 0))
        }
        "statusline" => {
            let mut stdin_json = String::new();
            let _ = std::io::stdin().read_to_string(&mut stdin_json);
            if stdin_json.is_empty() {
                stdin_json = "{}".to_string();
            }
            statusline::render_statusline(&stdin_json).map(|s| (s, 0))
        }
        "hard-gate" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            hard_gate::execute_gate(&args, &cwd)
        }
        "session-start" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            session_start::execute_session_start(&cwd)
        }
        "metrics-report" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            let phase_filter = if args.len() > 2 { Some(args[2].as_str()) } else { None };
            metrics_report::generate_metrics_report(&cwd, phase_filter)
        }
        "token-baseline" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_baseline::execute(&args, &cwd)
        }
        "bootstrap" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            // Dispatch bootstrap subcommands; fall through to bootstrap_claude for CLAUDE.md
            if args.len() > 2 {
                match args[2].as_str() {
                    "project" => return bootstrap_project::execute(&args[2..], &cwd),
                    "requirements" => return bootstrap_requirements::execute(&args[2..], &cwd),
                    "roadmap" => return bootstrap_roadmap::execute(&args[2..], &cwd),
                    "state" => return bootstrap_state::execute(&args[2..], &cwd),
                    _ => {} // Not a known subcommand, fall through to bootstrap_claude
                }
            }
            bootstrap_claude::execute(&args, &cwd)
        }
        "suggest-next" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            suggest_next::execute(&args, &cwd)
        }
        "list-todos" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            list_todos::execute(&args, &cwd)
        }
        "phase-detect" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            phase_detect::execute(&args, &cwd)
        }
        "detect-stack" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            detect_stack::execute(&args, &cwd)
        }
        "infer" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            infer_project_context::execute(&args, &cwd)
        }
        "planning-git" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            planning_git::execute(&args, &cwd)
        }
        "resolve-model" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_model::execute(&args, &cwd)
        }
        "resolve-turns" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_turns::execute(&args, &cwd)
        }
        "log-event" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            log_event::execute(&args, &cwd)
        }
        "collect-metrics" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            collect_metrics::execute(&args, &cwd)
        }
        "generate-contract" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_contract::execute(&args, &cwd)
        }
        "contract-revision" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            contract_revision::execute(&args, &cwd)
        }
        "assess-risk" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            assess_plan_risk::execute(&args, &cwd)
        }
        "gate-policy" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            resolve_gate_policy::execute(&args, &cwd)
        }
        "smart-route" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            smart_route::execute(&args, &cwd)
        }
        "route-monorepo" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            route_monorepo::execute(&args, &cwd)
        }
        "snapshot-resume" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            snapshot_resume::execute(&args[2..].to_vec(), &cwd)
        }
        "persist-state" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            persist_state::execute(&args[2..].to_vec(), &cwd)
        }
        "recover-state" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            recover_state::execute(&args[2..].to_vec(), &cwd)
        }
        "rolling-summary" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            compile_rolling_summary::execute(&args[2..].to_vec(), &cwd)
        }
        "gsd-index" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_gsd_index::execute(&args, &cwd)
        }
        "incidents" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            generate_incidents::execute(&args, &cwd)
        }
        "artifact" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            artifact_registry::execute(&args, &cwd)
        }
        "gsd-summary" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            infer_gsd_summary::execute(&args, &cwd)
        }
        "cache-context" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            cache_context::execute(&args, &cwd)
        }
        "cache-nuke" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            cache_nuke::execute(&args, &cwd)
        }
        "delta-files" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            delta_files::execute(&args, &cwd)
        }
        "map-staleness" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            hooks::map_staleness::execute(&args, &cwd)
        }
        "token-budget" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            token_budget::execute(&args, &cwd)
        }
        "lock" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            lock_lite::execute(&args, &cwd)
        }
        "lease-lock" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            lease_lock::execute(&args, &cwd)
        }
        "two-phase-complete" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            two_phase_complete::execute(&args, &cwd)
        }
        "help-output" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            help_output::execute(&args[1..], &cwd)
        }
        "bump-version" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            bump_version::execute(&args, &cwd)
        }
        "doctor" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            doctor_cleanup::execute(&args, &cwd)
        }
        "auto-repair" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            auto_repair::execute(&args, &cwd)
        }
        "rollout-stage" | "rollout" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            rollout_stage::execute(&args, &cwd)
        }
        "verify" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify::execute(&args, &cwd)
        }
        "hook" => {
            if args.len() < 3 {
                return Err("Usage: yolo hook <event-name>".to_string());
            }
            let event_name = &args[2];

            // Register SIGHUP handler for cleanup
            let sighup_flag = hooks::sighup::register_sighup_handler().ok();

            // Read stdin (hook JSON context from Claude Code)
            let mut stdin_json = String::new();
            let _ = std::io::stdin().read_to_string(&mut stdin_json);
            if stdin_json.is_empty() {
                stdin_json = "{}".to_string();
            }

            let result = hooks::dispatcher::dispatch_from_cli(event_name, &stdin_json);

            // Check if SIGHUP was received during dispatch
            if let Some(ref flag) = sighup_flag {
                if hooks::sighup::check_and_handle_sighup(flag.as_ref()) {
                    return Ok(("".to_string(), 1));
                }
            }

            result
        }
        "install-hooks" => {
            install_hooks::install_hooks().map(|s| (s, 0))
        }
        "migrate-config" => {
            if args.len() < 3 {
                return Err("Usage: yolo migrate-config <config_path> [defaults_path]".to_string());
            }
            let config_path = std::path::Path::new(&args[2]);
            let defaults_path_buf;
            let defaults_path = if args.len() > 3 && !args[3].starts_with("--") {
                std::path::Path::new(&args[3])
            } else {
                // Resolve from CLAUDE_PLUGIN_ROOT or binary location
                let plugin_root = env::var("CLAUDE_PLUGIN_ROOT").unwrap_or_else(|_| {
                    env::current_exe()
                        .ok()
                        .and_then(|p| p.parent().map(|d| d.parent().unwrap_or(d).to_path_buf()))
                        .unwrap_or_else(|| PathBuf::from("."))
                        .to_string_lossy()
                        .to_string()
                });
                defaults_path_buf = PathBuf::from(&plugin_root).join("config").join("defaults.json");
                defaults_path_buf.as_path()
            };
            let print_added = args.iter().any(|a| a == "--print-added");
            match migrate_config::migrate_config(config_path, defaults_path) {
                Ok(added) => {
                    if print_added {
                        Ok((format!("{}", added), 0))
                    } else {
                        Ok((format!("Config migrated ({} keys added)", added), 0))
                    }
                }
                Err(e) => Err(e),
            }
        }
        "invalidate-tier-cache" => {
            match tier_context::invalidate_tier_cache() {
                Ok(()) => Ok(("Tier cache invalidated".to_string(), 0)),
                Err(e) => Ok((format!("Cache invalidation failed (non-fatal): {}", e), 0)),
            }
        }
        "compress-context" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            compress_context::execute(&args, &cwd)
        }
        "prune-completed" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            prune_completed::execute(&args, &cwd)
        }
        "compile-context" => {
            if args.len() < 4 {
                return Err("Usage: yolo compile-context <phase> <role> <phases_dir> [plan_path]".to_string());
            }
            let phase = &args[2];
            let role = &args[3];
            let phases_dir = std::path::Path::new(&args[4]);
            let plan_path_opt = args.get(5).map(|s| std::path::Path::new(s.as_str()));

            let planning_dir = PathBuf::from(".yolo-planning");
            let phase_i64 = phase.parse::<i64>().unwrap_or(0);
            let ctx = tier_context::build_tiered_context(
                &planning_dir, role, phase_i64, Some(phases_dir), plan_path_opt,
            );

            let mut context = ctx.combined;
            context.push_str("\n--- END COMPILED CONTEXT ---\n");

            // Write to .context-{role}.md in phases_dir
            let output_path = phases_dir.join(format!(".context-{}.md", role));
            match std::fs::write(&output_path, &context) {
                Ok(_) => Ok((format!("Wrote {}", output_path.display()), 0)),
                Err(_) => {
                    // Fall back to stdout
                    Ok((context, 0))
                }
            }
        }
        "install-mcp" => {
            // Locate install-yolo-mcp.sh relative to plugin root or binary
            let plugin_root = env::var("CLAUDE_PLUGIN_ROOT").unwrap_or_else(|_| {
                env::current_exe()
                    .ok()
                    .and_then(|p| p.parent().map(|d| d.parent().unwrap_or(d).to_path_buf()))
                    .unwrap_or_else(|| PathBuf::from("."))
                    .to_string_lossy()
                    .to_string()
            });
            let script_path = PathBuf::from(&plugin_root).join("install-yolo-mcp.sh");
            if !script_path.exists() {
                return Err(format!("install-yolo-mcp.sh not found at {}", script_path.display()));
            }
            let mut cmd = std::process::Command::new("bash");
            cmd.arg(&script_path);
            // Pass through any extra args
            for arg in &args[2..] {
                cmd.arg(arg);
            }
            let output = cmd.output().map_err(|e| format!("Failed to run install script: {e}"))?;
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let combined = if stderr.is_empty() { stdout } else { format!("{}\n{}", stdout, stderr) };
            if output.status.success() {
                Ok((combined, 0))
            } else {
                Ok((combined, output.status.code().unwrap_or(1)))
            }
        }
        "migrate-orphaned-state" => {
            if args.len() < 3 {
                return Err("Usage: yolo migrate-orphaned-state <planning_dir>".to_string());
            }
            let planning_dir = std::path::Path::new(&args[2]);
            match migrate_orphaned_state::migrate_orphaned_state(planning_dir) {
                Ok(true) => Ok(("Migrated".to_string(), 0)),
                Ok(false) => Ok(("No migration needed".to_string(), 0)),
                Err(e) => Err(e),
            }
        }
        "clean-stale-teams" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            let claude_dir = cwd.join(".claude");
            let log_file = cwd.join(".yolo-planning").join("clean-stale-teams.log");
            let (teams, tasks) = clean_stale_teams::clean_stale_teams(&claude_dir, &log_file);
            Ok((format!("Cleaned {} teams, {} task dirs", teams, tasks), 0))
        }
        "tmux-watchdog" => {
            match tmux_watchdog::get_tmux_session() {
                Some(session) => Ok((format!("tmux session: {}", session), 0)),
                None => Ok(("Not running in tmux".to_string(), 0)),
            }
        }
        "verify-init-todo" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_init_todo::execute(&args, &cwd)
        }
        "verify-vibe" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_vibe::execute(&args, &cwd)
        }
        "verify-claude-bootstrap" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_claude_bootstrap::execute(&args, &cwd)
        }
        "pre-push" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            pre_push_hook::execute(&args, &cwd)
        }
        "validate-plan" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            validate_plan::execute(&args, &cwd)
        }
        "review-plan" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            review_plan::execute(&args, &cwd)
        }
        "check-regression" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            check_regression::execute(&args, &cwd)
        }
        "commit-lint" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            commit_lint::execute(&args, &cwd)
        }
        "diff-against-plan" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            diff_against_plan::execute(&args, &cwd)
        }
        "validate-requirements" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            validate_requirements::execute(&args, &cwd)
        }
        "verify-plan-completion" => {
            let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            verify_plan_completion::execute(&args, &cwd)
        }
        _ => Err(format!("Unknown command: {}", args[1]))
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_report() {
        let report = generate_report(100, 50, 80_000.0, None);
        assert!(report.contains("Total Intercepted Tool Calls: 100"));
        assert!(report.contains("Context Compilations (Cache hits): 50"));
        assert!(report.contains("TOTAL SAVINGS"));
        assert!(report.contains("Projected (no data)"));
    }

    #[test]
    fn test_generate_report_measured() {
        let report = generate_report(100, 50, 45_000.0, Some(5));
        assert!(report.contains("Total Intercepted Tool Calls: 100"));
        assert!(report.contains("Measured"));
        assert!(!report.contains("Projected"));
        assert!(report.contains("Avg Prefix Size (tokens):        45000"));
        // With 5 sessions: writes=5, reads=45
        assert!(report.contains("Cache Writes / Reads:            5 / 45"));
    }

    #[test]
    fn test_run_cli_errors() {
        let path = std::env::temp_dir().join(format!("yolo-test-cli-missing-{}.db", std::process::id()));
        // missing args
        assert!(run_cli(vec!["yolo".into()], path.clone()).is_err());
        // wrong command
        assert!(run_cli(vec!["yolo".into(), "unknown".into()], path.clone()).is_err());
        // valid command, missing db
        assert!(run_cli(vec!["yolo".into(), "report".into()], path.clone()).is_err());
    }

    #[test]
    fn test_run_cli_success() {
        let path = std::env::temp_dir().join(format!("yolo-test-cli-success-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        let conn = Connection::open(&path).unwrap();
        conn.execute(
            "CREATE TABLE tool_usage (tool_name TEXT, output_length INTEGER, session_id TEXT)",
            [],
        ).unwrap();
        conn.execute(
            "INSERT INTO tool_usage (tool_name, output_length, session_id) VALUES ('compile_context', 50000, 'sess-1')",
            [],
        ).unwrap();

        let (report, code) = run_cli(vec!["yolo".into(), "report".into()], path.clone()).unwrap();
        assert!(report.contains("Total Intercepted Tool Calls: 1"));
        assert!(report.contains("Measured"));
        assert!(report.contains("Avg Prefix Size (tokens):        50000"));
        assert_eq!(code, 0);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn test_routed_verify_commands() {
        let path = std::env::temp_dir().join(format!("yolo-test-route-{}.db", std::process::id()));
        // These should not return "Unknown command" errors
        for cmd in &["verify-init-todo", "verify-vibe", "pre-push", "clean-stale-teams", "tmux-watchdog", "verify-claude-bootstrap"] {
            let result = run_cli(vec!["yolo".into(), cmd.to_string()], path.clone());
            // May fail for other reasons, but should NOT be "Unknown command"
            if let Err(e) = &result {
                assert!(!e.contains("Unknown command"), "Command {} should be routed but got: {}", cmd, e);
            }
        }
        let _ = std::fs::remove_file(&path);
    }
}
