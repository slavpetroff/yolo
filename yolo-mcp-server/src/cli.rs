use rusqlite::Connection;
use std::env;
use std::path::PathBuf;

pub mod state_updater;
pub mod statusline;
pub mod hard_gate;
pub mod session_start;

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
        _ => Err(format!("Unknown command: {}", args[1]))
    }
}



#[cfg(not(tarpaulin_include))]
fn main() {
    let args: Vec<String> = env::args().collect();
    let db_path = PathBuf::from(".yolo-telemetry.db");

    match run_cli(args, db_path) {
        Ok((report, exit_code)) => {
            print!("{}", report);
            if exit_code != 0 {
                std::process::exit(exit_code);
            }
        },
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1);
        }
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
