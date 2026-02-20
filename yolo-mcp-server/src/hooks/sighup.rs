use std::fs;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use super::utils;

/// Register a SIGHUP handler that cleans up agent PIDs.
/// Returns a flag that is set to `true` when SIGHUP is received.
///
/// The caller should check this flag periodically or after dispatch completes.
/// On SIGHUP: reads `.yolo-planning/.agent-pids`, sends SIGTERM, waits 3s, SIGKILLs survivors.
pub fn register_sighup_handler() -> Result<Arc<AtomicBool>, String> {
    let flag = Arc::new(AtomicBool::new(false));

    // signal-hook requires that we register a signal ID
    signal_hook::flag::register(signal_hook::consts::SIGHUP, Arc::clone(&flag))
        .map_err(|e| format!("Failed to register SIGHUP handler: {}", e))?;

    Ok(flag)
}

/// Execute SIGHUP cleanup: terminate agent PIDs with escalation.
/// Called when the SIGHUP flag is detected as true.
pub fn handle_sighup_cleanup(planning_dir: &Path) {
    utils::log_hook_message(planning_dir, "SIGHUP received, cleaning up agent PIDs");

    let pid_file = planning_dir.join(".agent-pids");
    if !pid_file.exists() {
        utils::log_hook_message(planning_dir, "SIGHUP: no .agent-pids file found");
        return;
    }

    let content = match fs::read_to_string(&pid_file) {
        Ok(c) => c,
        Err(e) => {
            utils::log_hook_message(
                planning_dir,
                &format!("SIGHUP: failed to read .agent-pids: {}", e),
            );
            return;
        }
    };

    let pids: Vec<i32> = content
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                return None;
            }
            trimmed.parse::<i32>().ok()
        })
        .collect();

    if pids.is_empty() {
        utils::log_hook_message(planning_dir, "SIGHUP: no valid PIDs found");
        return;
    }

    utils::log_hook_message(
        planning_dir,
        &format!("SIGHUP: sending SIGTERM to {} PIDs", pids.len()),
    );

    // Send SIGTERM to all
    for &pid in &pids {
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }
    }

    // Wait 3 seconds for graceful shutdown
    thread::sleep(Duration::from_secs(3));

    // SIGKILL survivors
    for &pid in &pids {
        // Check if still alive (kill -0)
        let alive = unsafe { libc::kill(pid, 0) == 0 };
        if alive {
            utils::log_hook_message(
                planning_dir,
                &format!("SIGHUP: PID {} still alive, sending SIGKILL", pid),
            );
            unsafe {
                libc::kill(pid, libc::SIGKILL);
            }
        }
    }

    utils::log_hook_message(planning_dir, "SIGHUP cleanup complete");
}

/// Check the SIGHUP flag and run cleanup if triggered.
/// Returns `true` if SIGHUP was handled (caller should exit 1).
pub fn check_and_handle_sighup(flag: &AtomicBool) -> bool {
    if flag.load(Ordering::Relaxed) {
        if let Some(planning_dir) = find_planning_dir() {
            handle_sighup_cleanup(&planning_dir);
        }
        return true;
    }
    false
}

fn find_planning_dir() -> Option<std::path::PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    utils::get_planning_dir(&cwd)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_handle_sighup_cleanup_no_pid_file() {
        let dir = TempDir::new().unwrap();
        // Should not panic when .agent-pids doesn't exist
        handle_sighup_cleanup(dir.path());

        let log = dir.path().join(".hook-errors.log");
        assert!(log.exists());
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("no .agent-pids file found"));
    }

    #[test]
    fn test_handle_sighup_cleanup_empty_pid_file() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join(".agent-pids"), "").unwrap();

        handle_sighup_cleanup(dir.path());

        let log = dir.path().join(".hook-errors.log");
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("no valid PIDs found"));
    }

    #[test]
    fn test_handle_sighup_cleanup_invalid_pids() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join(".agent-pids"), "not-a-pid\nabc\n").unwrap();

        handle_sighup_cleanup(dir.path());

        let log = dir.path().join(".hook-errors.log");
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("no valid PIDs found"));
    }

    #[test]
    fn test_handle_sighup_cleanup_with_nonexistent_pids() {
        let dir = TempDir::new().unwrap();
        // Use PIDs that almost certainly don't exist
        fs::write(dir.path().join(".agent-pids"), "999999\n999998\n").unwrap();

        handle_sighup_cleanup(dir.path());

        let log = dir.path().join(".hook-errors.log");
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("sending SIGTERM to 2 PIDs"));
    }

    #[test]
    fn test_register_sighup_handler() {
        let result = register_sighup_handler();
        assert!(result.is_ok());
        let flag = result.unwrap();
        assert!(!flag.load(Ordering::Relaxed));
    }

    #[test]
    fn test_check_and_handle_sighup_not_triggered() {
        let flag = AtomicBool::new(false);
        assert!(!check_and_handle_sighup(&flag));
    }
}
