use std::fs;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime};

use serde_json::Value;

use super::agent_pid_tracker;
use super::types::{HookInput, HookOutput};

/// Handle SubagentStop event.
pub fn handle(input: &HookInput, planning_dir: &Path) -> Result<HookOutput, String> {
    let lock_dir = planning_dir.join(".active-agent-count.lock");
    let locked = acquire_stale_lock(&lock_dir);

    decrement_or_cleanup(planning_dir);

    if locked {
        release_lock(&lock_dir);
    }

    // Unregister agent PID
    let agent_pid = extract_pid(&input.data);
    if agent_pid > 0 {
        let _ = agent_pid_tracker::unregister(agent_pid, planning_dir);

        // Auto-close tmux pane if recorded at start
        if std::env::var("TMUX").is_ok() {
            close_tmux_pane(planning_dir, agent_pid);
        }
    }

    Ok(HookOutput::empty())
}

fn extract_pid(data: &Value) -> u32 {
    data.get("pid")
        .and_then(|v| {
            v.as_u64()
                .map(|n| n as u32)
                .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        })
        .unwrap_or(0)
}

/// Decrement active agent count, cleaning up markers when reaching zero.
fn decrement_or_cleanup(planning_dir: &Path) {
    let count_file = planning_dir.join(".active-agent-count");
    let agent_file = planning_dir.join(".active-agent");

    if count_file.exists() {
        let mut count: i32 = fs::read_to_string(&count_file)
            .unwrap_or_default()
            .trim()
            .parse()
            .unwrap_or(0);

        // Corrupted count + active marker => treat as one active agent left
        if count <= 0 && agent_file.exists() {
            count = 1;
        }

        count -= 1;

        if count <= 0 {
            let _ = fs::remove_file(&agent_file);
            let _ = fs::remove_file(&count_file);
        } else {
            let _ = fs::write(&count_file, format!("{}", count));
        }
    } else if agent_file.exists() {
        // Legacy: no count file but marker exists — remove (single agent case)
        let _ = fs::remove_file(&agent_file);
    }
}

/// Close a tmux pane mapped to this agent PID.
fn close_tmux_pane(planning_dir: &Path, agent_pid: u32) {
    let pane_map = planning_dir.join(".agent-panes");
    if !pane_map.exists() {
        return;
    }

    let content = match fs::read_to_string(&pane_map) {
        Ok(c) => c,
        Err(_) => return,
    };

    let pid_str = agent_pid.to_string();
    let mut pane_id = None;

    // Find matching PID line
    for line in content.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && parts[0] == pid_str {
            pane_id = Some(parts[1].to_string());
            break;
        }
    }

    if let Some(pane) = pane_id {
        // Remove entry from map
        let remaining: Vec<&str> = content
            .lines()
            .filter(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                parts.first() != Some(&pid_str.as_str())
            })
            .collect();
        let mut output = remaining.join("\n");
        if !output.is_empty() {
            output.push('\n');
        }
        let _ = fs::write(&pane_map, output);

        // Kill pane after 1s delay so agent process exits cleanly first
        thread::spawn(move || {
            thread::sleep(Duration::from_secs(1));
            let _ = Command::new("tmux")
                .args(["kill-pane", "-t", &pane])
                .output();
        });
    }
}

/// Acquire a mkdir-based lock with stale lock guard (>5s age check).
fn acquire_stale_lock(lock_dir: &Path) -> bool {
    for attempt in 0..100 {
        if fs::create_dir(lock_dir).is_ok() {
            return true;
        }

        if attempt == 50 && lock_dir.exists()
            && let Ok(metadata) = fs::metadata(lock_dir)
            && let Ok(modified) = metadata.modified()
            && let Ok(age) = SystemTime::now().duration_since(modified)
            && age.as_secs() > 5
        {
            let _ = fs::remove_dir(lock_dir);
        }

        thread::sleep(Duration::from_millis(10));
    }
    false
}

fn release_lock(lock_dir: &Path) {
    let _ = fs::remove_dir(lock_dir);
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_input(json: &str) -> HookInput {
        HookInput {
            data: serde_json::from_str(json).unwrap(),
        }
    }

    #[test]
    fn test_decrement_from_two_to_one() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        fs::write(planning.join(".active-agent-count"), "2").unwrap();
        fs::write(planning.join(".active-agent"), "dev").unwrap();

        decrement_or_cleanup(&planning);

        let count = fs::read_to_string(planning.join(".active-agent-count")).unwrap();
        assert_eq!(count.trim(), "1");
        assert!(planning.join(".active-agent").exists());
    }

    #[test]
    fn test_decrement_to_zero_cleans_up() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        fs::write(planning.join(".active-agent-count"), "1").unwrap();
        fs::write(planning.join(".active-agent"), "dev").unwrap();

        decrement_or_cleanup(&planning);

        assert!(!planning.join(".active-agent-count").exists());
        assert!(!planning.join(".active-agent").exists());
    }

    #[test]
    fn test_corrupted_count_with_marker() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        fs::write(planning.join(".active-agent-count"), "0").unwrap();
        fs::write(planning.join(".active-agent"), "dev").unwrap();

        decrement_or_cleanup(&planning);

        // Corrupted count + marker => treat as 1, decrement to 0 => cleanup
        assert!(!planning.join(".active-agent-count").exists());
        assert!(!planning.join(".active-agent").exists());
    }

    #[test]
    fn test_legacy_no_count_file() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        fs::write(planning.join(".active-agent"), "dev").unwrap();

        decrement_or_cleanup(&planning);

        assert!(!planning.join(".active-agent").exists());
    }

    #[test]
    fn test_handle_with_pid() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);
        let _ = fs::remove_dir("/tmp/yolo-agent-pid-lock");

        fs::write(planning.join(".active-agent-count"), "1").unwrap();
        fs::write(planning.join(".active-agent"), "dev").unwrap();

        let input = make_input(r#"{"pid":999994}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());

        // Should have cleaned up
        assert!(!planning.join(".active-agent-count").exists());
    }

    #[test]
    fn test_handle_no_pid() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);

        fs::write(planning.join(".active-agent-count"), "2").unwrap();
        fs::write(planning.join(".active-agent"), "lead").unwrap();

        let input = make_input(r#"{}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());

        let count = fs::read_to_string(planning.join(".active-agent-count")).unwrap();
        assert_eq!(count.trim(), "1");
    }

    #[test]
    fn test_handle_nothing_to_decrement() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);

        let input = make_input(r#"{}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().exit_code, 0);
    }
}
