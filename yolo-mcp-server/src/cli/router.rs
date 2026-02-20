use rusqlite::Connection;
use std::env;
use std::io::Read;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use crate::commands::{state_updater, statusline, hard_gate, session_start, metrics_report, token_baseline, bootstrap_claude, bootstrap_project, bootstrap_requirements, bootstrap_roadmap, bootstrap_state, suggest_next, list_todos, phase_detect, detect_stack, infer_project_context, planning_git, resolve_model, resolve_turns, log_event, collect_metrics, generate_contract, contract_revision, assess_plan_risk, resolve_gate_policy, smart_route, route_monorepo, snapshot_resume, persist_state, recover_state, compile_rolling_summary, generate_gsd_index, generate_incidents, artifact_registry, infer_gsd_summary, cache_context, cache_nuke, delta_files};
use crate::hooks;
pub fn generate_report(total_calls: i64, compile_calls: i64) -> String {
    let mut out = String::new();
    out.push_str("============================================================\n");
    out.push_str("             YOLO EXPERT ROI & TELEMETRY DASHBOARD           \n");
    out.push_str("============================================================\n");
    out.push_str(&format!("Total Intercepted Tool Calls: {}\n", total_calls));
    out.push_str(&format!("Context Compilations (Cache hits): {}\n", compile_calls));

    let assumed_prefix_size = 80_000_f64;
    let cold_cost_per_m = 3.00;
    let caching_write_cost_per_m = 3.75;
    let caching_read_cost_per_m = 0.30;

    let total_tokens_pushed = compile_calls as f64 * assumed_prefix_size;
    let expected_cold_cost = (total_tokens_pushed / 1_000_000.0) * cold_cost_per_m;

    let writes = (compile_calls as f64 / 10.0).max(1.0);
    let reads = compile_calls as f64 - writes;
    
    let actual_hot_cost = ((writes * assumed_prefix_size) / 1_000_000.0) * caching_write_cost_per_m + 
                          ((reads * assumed_prefix_size) / 1_000_000.0) * caching_read_cost_per_m;
    let savings = expected_cold_cost - actual_hot_cost;

    out.push_str("------------------------------------------------------------\n");
    out.push_str("📊 Token Efficiency Analysis (Projected vs Actual)\n");
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("Estimated Total Tokens Pushed:   {:.0} million\n", total_tokens_pushed / 1_000_000.0));
    out.push_str(&format!("Expected Cold Cache Cost:        ${:.2}\n", expected_cold_cost));
    out.push_str(&format!("Actual Hot Cache Cost (with Prefix): ${:.2}\n", actual_hot_cost));
    out.push_str("------------------------------------------------------------\n");
    out.push_str(&format!("💲 TOTAL SAVINGS:                 +${:.2}\n", savings));
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

            Ok((generate_report(total_calls, compile_calls), 0))
        }
        "update-state" => {
            if args.len() < 3 {
                return Err("Usage: yolo update-state <file_path>".to_string());
            }
            state_updater::update_state(&args[2]).map(|s| (s, 0))
        }
        "statusline" => {
            statusline::render_statusline(&db_path).map(|s| (s, 0))
        }
        "fetch-limits" => {
            let _ = statusline::execute_fetch_limits();
            Ok("".to_string()).map(|s| (s, 0))
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
        _ => Err(format!("Unknown command: {}", args[1]))
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_report() {
        let report = generate_report(100, 50);
        assert!(report.contains("Total Intercepted Tool Calls: 100"));
        assert!(report.contains("Context Compilations (Cache hits): 50"));
        assert!(report.contains("TOTAL SAVINGS"));
    }

    #[test]
    fn test_run_cli_errors() {
        let path = PathBuf::from(".test-cli-missing.db");
        // missing args
        assert!(run_cli(vec!["yolo".into()], path.clone()).is_err());
        // wrong command
        assert!(run_cli(vec!["yolo".into(), "unknown".into()], path.clone()).is_err());
        // valid command, missing db
        assert!(run_cli(vec!["yolo".into(), "report".into()], path.clone()).is_err());
    }

    #[test]
    fn test_run_cli_success() {
        let path = PathBuf::from(".test-cli-success.db");
        let _ = std::fs::remove_file(&path);
        let conn = Connection::open(&path).unwrap();
        conn.execute(
            "CREATE TABLE tool_usage (tool_name TEXT)",
            [],
        ).unwrap();
        conn.execute("INSERT INTO tool_usage (tool_name) VALUES ('compile_context')", []).unwrap();
        
        let (report, code) = run_cli(vec!["yolo".into(), "report".into()], path.clone()).unwrap();
        assert!(report.contains("Total Intercepted Tool Calls: 1"));
        assert_eq!(code, 0);

        let _ = std::fs::remove_file(&path);
    }
}
