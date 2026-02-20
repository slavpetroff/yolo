use rusqlite::{Connection, Result};
use chrono::Utc;
use std::path::PathBuf;

pub struct TelemetryDb {
    conn: Connection,
}

impl TelemetryDb {
    pub fn new(path: PathBuf) -> Result<Self> {
        let conn = Connection::open(&path)?;
        
        let db = Self { conn };
        db.init()?;
        Ok(db)
    }

    fn init(&self) -> Result<()> {
        self.conn.execute(
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
        self.conn.execute(
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
    use std::fs;

    #[test]
    fn test_telemetry_db_creation_and_insertion() {
        let db_path = PathBuf::from(".test-telemetry.db");
        
        // Clean up from previous failed test if necessary
        let _ = fs::remove_file(&db_path);

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
        let count: i64 = db.conn.query_row("SELECT COUNT(*) FROM tool_usage", [], |row| row.get(0)).unwrap();
        assert_eq!(count, 1);

        // Clean up
        let _ = fs::remove_file(&db_path);
    }
}
