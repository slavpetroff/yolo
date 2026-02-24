use rusqlite::{Connection, Result};
use chrono::Utc;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Mutex;

pub struct TelemetryDb {
    conn: Mutex<Connection>,
}

impl TelemetryDb {
    pub fn new(path: PathBuf) -> Result<Self> {
        let conn = Connection::open(&path)?;

        let db = Self { conn: Mutex::new(conn) };
        db.init()?;
        Ok(db)
    }

    fn init(&self) -> Result<()> {
        let conn = self.conn.lock()
            .map_err(|e| rusqlite::Error::InvalidParameterName(format!("Mutex poisoned: {}", e)))?;
        conn.execute(
            "CREATE TABLE IF NOT EXISTS tool_usage (
                id INTEGER PRIMARY KEY,
                tool_name TEXT NOT NULL,
                agent_role TEXT,
                session_id TEXT,
                input_length INTEGER,
                output_length INTEGER,
                execution_time_ms INTEGER,
                success BOOLEAN,
                timestamp TEXT NOT NULL
            )",
            [],
        )?;
        // Add retry_count column if missing (backward-compat migration)
        let _ = conn.execute("ALTER TABLE tool_usage ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0", []);
        conn.execute(
            "CREATE TABLE IF NOT EXISTS agent_token_usage (
                id INTEGER PRIMARY KEY,
                agent_role TEXT NOT NULL,
                phase INTEGER,
                session_id TEXT,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_write_tokens INTEGER NOT NULL DEFAULT 0,
                timestamp TEXT NOT NULL
            )",
            [],
        )?;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_agent_tokens(
        &self,
        agent_role: &str,
        phase: Option<i64>,
        session_id: Option<&str>,
        input_tokens: i64,
        output_tokens: i64,
        cache_read_tokens: i64,
        cache_write_tokens: i64,
    ) -> Result<()> {
        let ts = Utc::now().to_rfc3339();
        let conn = self.conn.lock()
            .map_err(|e| rusqlite::Error::InvalidParameterName(format!("Mutex poisoned: {}", e)))?;
        conn.execute(
            "INSERT INTO agent_token_usage (agent_role, phase, session_id, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, timestamp)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            (
                agent_role,
                phase,
                session_id,
                input_tokens,
                output_tokens,
                cache_read_tokens,
                cache_write_tokens,
                &ts,
            ),
        )?;
        Ok(())
    }

    pub fn query_agent_token_summary(&self) -> Result<Vec<Value>> {
        let conn = self.conn.lock()
            .map_err(|e| rusqlite::Error::InvalidParameterName(format!("Mutex poisoned: {}", e)))?;
        let mut stmt = conn.prepare(
            "SELECT agent_role, phase,
                    SUM(input_tokens) as total_input,
                    SUM(output_tokens) as total_output,
                    SUM(cache_read_tokens) as total_cache_read,
                    SUM(cache_write_tokens) as total_cache_write
             FROM agent_token_usage
             GROUP BY agent_role, phase
             ORDER BY agent_role, phase"
        )?;
        let rows = stmt.query_map([], |row| {
            let role: String = row.get(0)?;
            let phase: Option<i64> = row.get(1)?;
            let input: i64 = row.get(2)?;
            let output: i64 = row.get(3)?;
            let cache_read: i64 = row.get(4)?;
            let cache_write: i64 = row.get(5)?;
            Ok(json!({
                "agent_role": role,
                "phase": phase,
                "input_tokens": input,
                "output_tokens": output,
                "cache_read_tokens": cache_read,
                "cache_write_tokens": cache_write,
            }))
        })?;
        let mut results = Vec::new();
        for row in rows {
            results.push(row?);
        }
        Ok(results)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_tool_call(
        &self,
        tool_name: &str,
        agent_role: Option<&str>,
        session_id: Option<&str>,
        input_length: usize,
        output_length: usize,
        execution_time_ms: u64,
        success: bool,
    ) -> Result<()> {
        self.record_tool_call_with_retry(tool_name, agent_role, session_id, input_length, output_length, execution_time_ms, success, 0)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_tool_call_with_retry(
        &self,
        tool_name: &str,
        agent_role: Option<&str>,
        session_id: Option<&str>,
        input_length: usize,
        output_length: usize,
        execution_time_ms: u64,
        success: bool,
        retry_count: u32,
    ) -> Result<()> {
        let ts = Utc::now().to_rfc3339();
        let conn = self.conn.lock()
            .map_err(|e| rusqlite::Error::InvalidParameterName(format!("Mutex poisoned: {}", e)))?;
        conn.execute(
            "INSERT INTO tool_usage (tool_name, agent_role, session_id, input_length, output_length, execution_time_ms, success, retry_count, timestamp)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            (
                tool_name,
                agent_role,
                session_id,
                input_length as i64,
                output_length as i64,
                execution_time_ms as i64,
                success,
                retry_count as i64,
                &ts,
            ),
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_telemetry_db_creation_and_insertion() {
        let db_path = std::env::temp_dir().join(format!("yolo-test-telemetry-{}.db", std::process::id()));

        // Clean up from previous failed test if necessary
        let _ = std::fs::remove_file(&db_path);

        let db = TelemetryDb::new(db_path.clone()).expect("Failed to create test DB");

        // Insert a record
        let result = db.record_tool_call(
            "test_tool",
            Some("architect"),
            Some("session-123"),
            100,
            200,
            150,
            true,
        );
        assert!(result.is_ok());

        // Verify insertion
        let conn = db.conn.lock().unwrap();
        let count: i64 = conn.query_row("SELECT COUNT(*) FROM tool_usage", [], |row| row.get(0)).unwrap();
        assert_eq!(count, 1);

        // Clean up
        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn test_agent_token_usage_insert_and_summary() {
        let db_path = std::env::temp_dir().join(format!("yolo-test-agent-tokens-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let db = TelemetryDb::new(db_path.clone()).expect("Failed to create test DB");

        // Insert 3 records for different roles/phases
        db.record_agent_tokens("dev", Some(1), Some("s1"), 5000, 1200, 3000, 800).unwrap();
        db.record_agent_tokens("dev", Some(1), Some("s1"), 2000, 500, 1000, 200).unwrap();
        db.record_agent_tokens("architect", Some(2), Some("s1"), 8000, 3000, 5000, 1500).unwrap();

        let summary = db.query_agent_token_summary().unwrap();
        assert_eq!(summary.len(), 2); // 2 groups: (architect, 2) and (dev, 1)

        // architect,2 should be first (alphabetical)
        assert_eq!(summary[0]["agent_role"], "architect");
        assert_eq!(summary[0]["phase"], 2);
        assert_eq!(summary[0]["input_tokens"], 8000);
        assert_eq!(summary[0]["output_tokens"], 3000);
        assert_eq!(summary[0]["cache_read_tokens"], 5000);
        assert_eq!(summary[0]["cache_write_tokens"], 1500);

        // dev,1 — aggregated from 2 rows
        assert_eq!(summary[1]["agent_role"], "dev");
        assert_eq!(summary[1]["phase"], 1);
        assert_eq!(summary[1]["input_tokens"], 7000);
        assert_eq!(summary[1]["output_tokens"], 1700);
        assert_eq!(summary[1]["cache_read_tokens"], 4000);
        assert_eq!(summary[1]["cache_write_tokens"], 1000);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn test_init_idempotent() {
        let db_path = std::env::temp_dir().join(format!("yolo-test-idempotent-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let db = TelemetryDb::new(db_path.clone()).expect("First init");
        // Call init again — should not fail
        db.init().expect("Second init should be idempotent");

        // Insert should still work
        db.record_agent_tokens("dev", Some(1), None, 100, 50, 0, 0).unwrap();
        let summary = db.query_agent_token_summary().unwrap();
        assert_eq!(summary.len(), 1);

        let _ = std::fs::remove_file(&db_path);
    }
}
