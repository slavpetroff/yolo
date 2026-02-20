pub mod mcp;
pub mod cli;
pub mod commands;
pub mod telemetry;

use std::error::Error;
use std::sync::Arc;
use tokio::io::BufReader;
use crate::telemetry::db::TelemetryDb;
use crate::mcp::tools::ToolState;

#[cfg(not(test))]
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = std::env::args().collect();
    let db_path = std::path::PathBuf::from(".yolo-telemetry.db");

    // Route to CLI
    if args.len() > 1 {
        match cli::router::run_cli(args, db_path) {
            Ok((output, code)) => {
                print!("{}", output);
                std::process::exit(code);
            }
            Err(e) => {
                eprintln!("Error: {}", e);
                std::process::exit(1);
            }
        }
    }

    // Default: Route to MCP Server
    let telemetry = Arc::new(TelemetryDb::new(db_path)?);
    let tool_state = Arc::new(ToolState::new());

    let stdin = tokio::io::stdin();
    let reader = BufReader::new(stdin);
    let stdout = tokio::io::stdout();

    mcp::server::run_server(reader, stdout, telemetry, tool_state).await
}
