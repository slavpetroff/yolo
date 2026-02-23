use std::fs;
use std::io::Write;
use std::path::Path;
use std::thread;
use std::time::Duration;

const PID_FILENAME: &str = ".agent-pids";
const LOCK_DIR: &str = "/tmp/yolo-agent-pid-lock";
const MAX_RETRIES: u32 = 50;
const RETRY_DELAY_MS: u64 = 100;

/// Acquire a mkdir-based lock (macOS-compatible, no flock needed).
fn acquire_lock() -> Result<(), String> {
    for _ in 0..MAX_RETRIES {
        if fs::create_dir(LOCK_DIR).is_ok() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(RETRY_DELAY_MS));
    }
    Err("Failed to acquire PID lock after 50 attempts".to_string())
}

/// Release the mkdir-based lock.
fn release_lock() {
    let _ = fs::remove_dir(LOCK_DIR);
}

/// Register a PID in the agent PID file.
/// Creates `.yolo-planning/` if needed.
pub fn register(pid: u32, planning_dir: &Path) -> Result<String, String> {
    validate_pid(pid)?;

    acquire_lock()?;
    let result = do_register(pid, planning_dir);
    release_lock();
    result
}

fn do_register(pid: u32, planning_dir: &Path) -> Result<String, String> {
    fs::create_dir_all(planning_dir)
        .map_err(|e| format!("Failed to create planning dir: {}", e))?;

    let pid_file = planning_dir.join(PID_FILENAME);
    let pid_str = pid.to_string();

    // Check if already registered
    if pid_file.exists() {
        let content = fs::read_to_string(&pid_file).unwrap_or_default();
        for line in content.lines() {
            if line.trim() == pid_str {
                return Ok(format!("PID {} already registered", pid));
            }
        }
    }

    // Append PID
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&pid_file)
        .map_err(|e| format!("Failed to open PID file: {}", e))?;

    writeln!(f, "{}", pid).map_err(|e| format!("Failed to write PID: {}", e))?;

    Ok(format!("Registered PID {}", pid))
}

/// Unregister a PID from the agent PID file.
pub fn unregister(pid: u32, planning_dir: &Path) -> Result<String, String> {
    validate_pid(pid)?;

    acquire_lock()?;
    let result = do_unregister(pid, planning_dir);
    release_lock();
    result
}

fn do_unregister(pid: u32, planning_dir: &Path) -> Result<String, String> {
    let pid_file = planning_dir.join(PID_FILENAME);
    if !pid_file.exists() {
        return Ok("PID file not found, nothing to unregister".to_string());
    }

    let content = fs::read_to_string(&pid_file).unwrap_or_default();
    let pid_str = pid.to_string();

    let remaining: Vec<&str> = content
        .lines()
        .filter(|line| line.trim() != pid_str)
        .collect();

    let mut output = remaining.join("\n");
    if !output.is_empty() {
        output.push('\n');
    }

    fs::write(&pid_file, output).map_err(|e| format!("Failed to write PID file: {}", e))?;

    Ok(format!("Unregistered PID {}", pid))
}

/// List active PIDs, filtering out dead processes.
pub fn list(planning_dir: &Path) -> Result<Vec<u32>, String> {
    let pid_file = planning_dir.join(PID_FILENAME);
    if !pid_file.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&pid_file).unwrap_or_default();
    let mut alive = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let pid: u32 = match trimmed.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };
        if is_pid_alive(pid as i32) {
            alive.push(pid);
        }
    }

    Ok(alive)
}

/// Check if a PID is alive using kill(pid, 0).
pub fn is_pid_alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

fn validate_pid(pid: u32) -> Result<(), String> {
    if pid == 0 {
        return Err("Invalid PID: 0".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_register_creates_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");

        // Clean up any stale lock from a prior test run
        let _ = fs::remove_dir(LOCK_DIR);

        let result = register(12345, &planning);
        assert!(result.is_ok());

        let pid_file = planning.join(PID_FILENAME);
        assert!(pid_file.exists());

        let content = fs::read_to_string(&pid_file).unwrap();
        assert!(content.contains("12345"));
    }

    #[test]
    fn test_register_dedup() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let _ = fs::remove_dir(LOCK_DIR);

        let _ = register(12345, &planning);
        let _ = register(12345, &planning);

        let pid_file = planning.join(PID_FILENAME);
        let content = fs::read_to_string(&pid_file).unwrap();
        let count = content.lines().filter(|l| l.trim() == "12345").count();
        assert_eq!(count, 1);
    }

    #[test]
    fn test_unregister_removes_pid() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let _ = fs::remove_dir(LOCK_DIR);

        let _ = register(11111, &planning);
        let _ = register(22222, &planning);
        let _ = unregister(11111, &planning);

        let pid_file = planning.join(PID_FILENAME);
        let content = fs::read_to_string(&pid_file).unwrap();
        assert!(!content.contains("11111"));
        assert!(content.contains("22222"));
    }

    #[test]
    fn test_unregister_nonexistent_pid() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        let _ = fs::remove_dir(LOCK_DIR);

        let result = unregister(99999, &planning);
        assert!(result.is_ok());
    }

    #[test]
    fn test_unregister_no_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let _ = fs::remove_dir(LOCK_DIR);

        let result = unregister(99999, &planning);
        assert!(result.is_ok());
    }

    #[test]
    fn test_list_filters_dead_pids() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Write PIDs that definitely don't exist
        let pid_file = planning.join(PID_FILENAME);
        fs::write(&pid_file, "999997\n999998\n999999\n").unwrap();

        let alive = list(&planning).unwrap();
        assert!(alive.is_empty(), "Dead PIDs should be filtered out");
    }

    #[test]
    fn test_list_includes_current_process() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Use our own PID which is definitely alive
        let my_pid = std::process::id();
        let pid_file = planning.join(PID_FILENAME);
        fs::write(&pid_file, format!("{}\n", my_pid)).unwrap();

        let alive = list(&planning).unwrap();
        assert_eq!(alive, vec![my_pid]);
    }

    #[test]
    fn test_list_empty_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let pid_file = planning.join(PID_FILENAME);
        fs::write(&pid_file, "").unwrap();

        let alive = list(&planning).unwrap();
        assert!(alive.is_empty());
    }

    #[test]
    fn test_list_no_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");

        let alive = list(&planning).unwrap();
        assert!(alive.is_empty());
    }

    #[test]
    fn test_validate_pid_zero() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        let _ = fs::remove_dir(LOCK_DIR);

        let result = register(0, &planning);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid PID"));
    }

    #[test]
    fn test_is_pid_alive_current_process() {
        let my_pid = std::process::id() as i32;
        assert!(is_pid_alive(my_pid));
    }

    #[test]
    fn test_is_pid_alive_dead_process() {
        assert!(!is_pid_alive(999999));
    }

    #[test]
    fn test_list_skips_invalid_lines() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let my_pid = std::process::id();
        let pid_file = planning.join(PID_FILENAME);
        fs::write(&pid_file, format!("not-a-pid\n{}\n\n", my_pid)).unwrap();

        let alive = list(&planning).unwrap();
        assert_eq!(alive, vec![my_pid]);
    }
}
