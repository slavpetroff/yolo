use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

/// Spawn the tmux watchdog as a background thread.
/// The watchdog polls for detached tmux clients and terminates orphaned agents.
///
/// Returns Ok(true) if spawned, Ok(false) if skipped (already running, not in tmux, etc).
pub fn spawn_watchdog(planning_dir: &Path, session: &str) -> Result<bool, String> {
    if session.is_empty() {
        return Err("No tmux session name provided".to_string());
    }

    if !planning_dir.exists() {
        return Ok(false);
    }

    let pid_file = planning_dir.join(".watchdog-pid");

    // Check if watchdog already running
    if pid_file.exists()
        && let Ok(content) = fs::read_to_string(&pid_file)
        && let Ok(pid_u32) = content.trim().parse::<u32>()
    {
        let mut sys = sysinfo::System::new();
        sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
        if sys.process(sysinfo::Pid::from_u32(pid_u32)).is_some() {
            return Ok(false); // Already running
        }
        let _ = fs::remove_file(&pid_file);
    }

    // Spawn watchdog in background thread
    let pd = planning_dir.to_path_buf();
    let sess = session.to_string();

    std::thread::spawn(move || {
        run_watchdog_loop(&pd, &sess);
    });

    // Write our thread's parent PID as a rough approximation
    // (thread PID is same as process PID on most systems)
    let _ = fs::write(&pid_file, std::process::id().to_string());

    Ok(true)
}

/// Get the current tmux session name, if running inside tmux.
pub fn get_tmux_session() -> Option<String> {
    let tmux_env = std::env::var("TMUX").ok()?;
    if tmux_env.is_empty() {
        return None;
    }

    let output = Command::new("tmux")
        .args(["display-message", "-p", "#S"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let session = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if session.is_empty() {
        None
    } else {
        Some(session)
    }
}

fn run_watchdog_loop(planning_dir: &Path, session: &str) {
    let log_path = planning_dir.join(".watchdog.log");

    log_msg(&log_path, &format!("Watchdog started for session: {session} (PID={})", std::process::id()));

    let mut consecutive_empty = 0u32;

    loop {
        // Check if session still exists
        let has_session = Command::new("tmux")
            .args(["has-session", "-t", session])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);

        if !has_session {
            log_msg(&log_path, &format!("Session {session} no longer exists, exiting"));
            break;
        }

        // Poll for attached clients
        let client_count = Command::new("tmux")
            .args(["list-clients", "-t", session])
            .output()
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .count()
            })
            .unwrap_or(0);

        if client_count == 0 {
            consecutive_empty += 1;
            log_msg(&log_path, &format!("No clients attached (consecutive: {consecutive_empty})"));

            if consecutive_empty >= 2 {
                log_msg(&log_path, "Session detached (2 consecutive polls), cleaning up agents");
                cleanup_agents(planning_dir, &log_path);
                log_msg(&log_path, "Watchdog exiting");
                break;
            }
        } else {
            if consecutive_empty > 0 {
                log_msg(&log_path, "Client attached, resetting empty counter");
            }
            consecutive_empty = 0;
        }

        std::thread::sleep(std::time::Duration::from_secs(5));
    }

    // Clean up pid file
    let _ = fs::remove_file(planning_dir.join(".watchdog-pid"));
}

fn cleanup_agents(planning_dir: &Path, log_path: &Path) {
    let pid_file = planning_dir.join(".agent-pids");

    if !pid_file.exists() {
        log_msg(log_path, "No active agent PIDs to terminate");
        return;
    }

    let content = match fs::read_to_string(&pid_file) {
        Ok(c) => c,
        Err(_) => {
            log_msg(log_path, "Failed to read .agent-pids");
            return;
        }
    };

    let pids: Vec<u32> = content
        .lines()
        .filter_map(|line| line.trim().parse::<u32>().ok())
        .collect();

    if pids.is_empty() {
        log_msg(log_path, "No active agent PIDs to terminate");
        return;
    }

    // SIGTERM pass
    for pid in &pids {
        if signal_alive(*pid) {
            log_msg(log_path, &format!("Sending SIGTERM to agent PID {pid}"));
            let _ = unsafe { libc::kill(*pid as i32, libc::SIGTERM) };
        }
    }

    // Wait 3 seconds
    std::thread::sleep(std::time::Duration::from_secs(3));

    // SIGKILL fallback
    for pid in &pids {
        if signal_alive(*pid) {
            log_msg(log_path, &format!("Agent PID {pid} survived SIGTERM, sending SIGKILL"));
            let _ = unsafe { libc::kill(*pid as i32, libc::SIGKILL) };
        }
    }

    // Clean up PID file
    let _ = fs::remove_file(&pid_file);
    log_msg(log_path, "Removed .agent-pids file");
    log_msg(log_path, "Agent cleanup complete");
}

/// Check if a process is still alive via kill(pid, 0).
fn signal_alive(pid: u32) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

fn log_msg(log_path: &Path, msg: &str) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path)
    {
        let _ = writeln!(f, "[{ts}] {msg}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_signal_alive_self() {
        // Our own PID should be alive
        assert!(signal_alive(std::process::id()));
    }

    #[test]
    fn test_signal_alive_nonexistent() {
        // Very unlikely PID should not be alive
        assert!(!signal_alive(4_000_000));
    }

    #[test]
    fn test_cleanup_agents_no_pid_file() {
        let dir = tempdir().unwrap();
        let log = dir.path().join("watchdog.log");
        cleanup_agents(dir.path(), &log);
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("No active agent PIDs to terminate"));
    }

    #[test]
    fn test_cleanup_agents_empty_pid_file() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join(".agent-pids"), "").unwrap();
        let log = dir.path().join("watchdog.log");
        cleanup_agents(dir.path(), &log);
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("No active agent PIDs to terminate"));
    }

    #[test]
    fn test_cleanup_agents_with_dead_pids() {
        let dir = tempdir().unwrap();
        // Use PIDs that definitely don't exist
        fs::write(dir.path().join(".agent-pids"), "4000001\n4000002\n").unwrap();
        let log = dir.path().join("watchdog.log");
        cleanup_agents(dir.path(), &log);
        // Should have cleaned up the file
        assert!(!dir.path().join(".agent-pids").exists());
        let content = fs::read_to_string(&log).unwrap();
        assert!(content.contains("Agent cleanup complete"));
    }

    #[test]
    fn test_spawn_watchdog_empty_session() {
        let dir = tempdir().unwrap();
        let result = spawn_watchdog(dir.path(), "");
        assert!(result.is_err());
    }

    #[test]
    fn test_spawn_watchdog_nonexistent_dir() {
        let dir = tempdir().unwrap();
        let fake = dir.path().join("nonexistent");
        let result = spawn_watchdog(&fake, "test-session");
        assert_eq!(result.unwrap(), false);
    }
}
