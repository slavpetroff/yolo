use rusqlite::{Connection, Result};
use chrono::Utc;
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
        let conn = self.conn.lock().unwrap();
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
        Ok(())
    }

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
        let ts = Utc::now().to_rfc3339();
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO tool_usage (tool_name, agent_role, session_id, input_length, output_length, execution_time_ms, success, timestamp)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            (
                tool_name,
                agent_role,
                session_id,
                input_length as i64,
                output_length as i64,
                execution_time_ms as i64,
                success,
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
}
