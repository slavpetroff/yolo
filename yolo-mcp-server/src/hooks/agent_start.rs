use std::env;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime};

use serde_json::Value;

use super::agent_pid_tracker;
use super::types::{HookInput, HookOutput};
use super::utils;

/// Handle SubagentStart event.
pub fn handle(input: &HookInput, planning_dir: &Path) -> Result<HookOutput, String> {
    let agent_type = extract_agent_type(&input.data);
    if agent_type.is_empty() {
        return Ok(HookOutput::empty());
    }

    let role = utils::normalize_agent_role(&agent_type);
    if role.is_empty() {
        return Ok(HookOutput::empty());
    }

    // Only track YOLO agents: require explicit yolo prefix OR existing YOLO context
    if !is_explicit_yolo_agent(&agent_type) && !has_yolo_context(planning_dir) {
        return Ok(HookOutput::empty());
    }

    // Reference counting with mkdir-based lock
    let lock_dir = planning_dir.join(".active-agent-count.lock");
    let locked = acquire_stale_lock(&lock_dir);

    update_agent_markers(planning_dir, &role);

    if locked {
        release_lock(&lock_dir);
    }

    // Register agent PID
    let agent_pid = extract_pid(&input.data);
    if agent_pid > 0 {
        let _ = agent_pid_tracker::register(agent_pid, planning_dir);

        // Tmux pane mapping
        if env::var("TMUX").is_ok() {
            map_tmux_pane(planning_dir, agent_pid);
        }
    }

    Ok(HookOutput::empty())
}

fn extract_agent_type(data: &Value) -> String {
    data.get("agent_type")
        .or_else(|| data.get("agent_name"))
        .or_else(|| data.get("name"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
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

/// Check if agent name has explicit yolo prefix.
fn is_explicit_yolo_agent(name: &str) -> bool {
    let lower = name.to_lowercase();
    let stripped = lower.strip_prefix('@').unwrap_or(&lower);
    stripped.starts_with("yolo:") || stripped.starts_with("yolo-")
}

/// Check if YOLO context exists (session file, active-agent, or count file).
fn has_yolo_context(planning_dir: &Path) -> bool {
    planning_dir.join(".yolo-session").exists()
        || planning_dir.join(".active-agent").exists()
        || planning_dir.join(".active-agent-count").exists()
}

/// Acquire a mkdir-based lock with stale lock guard (>5s age check).
fn acquire_stale_lock(lock_dir: &Path) -> bool {
    for attempt in 0..100 {
        if fs::create_dir(lock_dir).is_ok() {
            return true;
        }

        // Stale lock guard at attempt 50
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
    // Could not acquire lock — proceed best-effort
    false
}

fn release_lock(lock_dir: &Path) {
    let _ = fs::remove_dir(lock_dir);
}

fn read_count(planning_dir: &Path) -> u32 {
    let count_file = planning_dir.join(".active-agent-count");
    if !count_file.exists() {
        return 0;
    }
    fs::read_to_string(&count_file)
        .unwrap_or_default()
        .trim()
        .parse()
        .unwrap_or(0)
}

fn update_agent_markers(planning_dir: &Path, role: &str) {
    let _ = fs::create_dir_all(planning_dir);

    let count = read_count(planning_dir);
    let count_file = planning_dir.join(".active-agent-count");
    let agent_file = planning_dir.join(".active-agent");

    // Write count first: if crash between writes, an elevated count is safer
    let _ = fs::write(&count_file, format!("{}", count + 1));
    let _ = fs::write(&agent_file, role);
}

/// Map agent PID to a tmux pane by walking the parent chain.
fn map_tmux_pane(planning_dir: &Path, agent_pid: u32) {
    let pane_list = match Command::new("tmux")
        .args(["list-panes", "-a", "-F", "#{pane_pid} #{pane_id}"])
        .output()
    {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).to_string()
        }
        _ => return,
    };

    if pane_list.is_empty() {
        return;
    }

    // Walk parent chain to find which tmux pane owns this PID
    let mut pid = agent_pid;
    let mut found_pane = None;

    while pid > 1 {
        for line in pane_list.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2
                && let Ok(pane_pid) = parts[0].parse::<u32>()
                && pane_pid == pid
            {
                found_pane = Some(parts[1].to_string());
                break;
            }
        }
        if found_pane.is_some() {
            break;
        }
        // Get parent PID
        pid = match get_parent_pid(pid) {
            Some(ppid) => ppid,
            None => break,
        };
    }

    if let Some(pane_id) = found_pane {
        let pane_map = planning_dir.join(".agent-panes");
        if let Ok(mut f) = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&pane_map)
        {
            let _ = writeln!(f, "{} {}", agent_pid, pane_id);
        }
    }
}

/// Get parent PID using `ps` command (works on macOS and Linux).
fn get_parent_pid(pid: u32) -> Option<u32> {
    let output = Command::new("ps")
        .args(["-o", "ppid=", "-p", &pid.to_string()])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse()
        .ok()
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
    fn test_extract_agent_type_variants() {
        let data: Value = serde_json::from_str(r#"{"agent_type":"yolo-dev"}"#).unwrap();
        assert_eq!(extract_agent_type(&data), "yolo-dev");

        let data: Value = serde_json::from_str(r#"{"agent_name":"@yolo:lead"}"#).unwrap();
        assert_eq!(extract_agent_type(&data), "@yolo:lead");

        let data: Value = serde_json::from_str(r#"{"name":"team-qa-1"}"#).unwrap();
        assert_eq!(extract_agent_type(&data), "team-qa-1");

        let data: Value = serde_json::from_str(r#"{}"#).unwrap();
        assert_eq!(extract_agent_type(&data), "");
    }

    #[test]
    fn test_extract_pid() {
        let data: Value = serde_json::from_str(r#"{"pid":12345}"#).unwrap();
        assert_eq!(extract_pid(&data), 12345);

        let data: Value = serde_json::from_str(r#"{"pid":"67890"}"#).unwrap();
        assert_eq!(extract_pid(&data), 67890);

        let data: Value = serde_json::from_str(r#"{}"#).unwrap();
        assert_eq!(extract_pid(&data), 0);
    }

    #[test]
    fn test_is_explicit_yolo_agent() {
        assert!(is_explicit_yolo_agent("yolo-dev"));
        assert!(is_explicit_yolo_agent("yolo:lead"));
        assert!(is_explicit_yolo_agent("@yolo-dev"));
        assert!(is_explicit_yolo_agent("@yolo:lead"));
        assert!(is_explicit_yolo_agent("YOLO-Dev"));

        assert!(!is_explicit_yolo_agent("dev"));
        assert!(!is_explicit_yolo_agent("team-dev"));
        assert!(!is_explicit_yolo_agent("scout"));
    }

    #[test]
    fn test_has_yolo_context() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        assert!(!has_yolo_context(&planning));

        fs::write(planning.join(".yolo-session"), "1").unwrap();
        assert!(has_yolo_context(&planning));
    }

    #[test]
    fn test_handle_explicit_yolo_agent() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        // Clean up stale locks
        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);
        let _ = fs::remove_dir("/tmp/yolo-agent-pid-lock");

        let input = make_input(r#"{"agent_type":"yolo-dev","pid":999997}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());

        // Verify reference counting
        let count = fs::read_to_string(planning.join(".active-agent-count")).unwrap();
        assert_eq!(count.trim(), "1");

        let role = fs::read_to_string(planning.join(".active-agent")).unwrap();
        assert_eq!(role.trim(), "dev");
    }

    #[test]
    fn test_handle_non_yolo_agent_no_context() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);

        let input = make_input(r#"{"agent_type":"dev","pid":999996}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());

        // Should NOT create markers (no yolo context)
        assert!(!planning.join(".active-agent-count").exists());
        assert!(!planning.join(".active-agent").exists());
    }

    #[test]
    fn test_handle_non_yolo_agent_with_context() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);
        let _ = fs::remove_dir("/tmp/yolo-agent-pid-lock");

        // Create YOLO context
        fs::write(planning.join(".yolo-session"), "1").unwrap();

        let input = make_input(r#"{"agent_type":"dev","pid":999995}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());

        // Should create markers (yolo context exists)
        assert!(planning.join(".active-agent-count").exists());
    }

    #[test]
    fn test_handle_empty_agent_type() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");

        let input = make_input(r#"{}"#);
        let result = handle(&input, &planning);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().exit_code, 0);
    }

    #[test]
    fn test_reference_counting_increments() {
        let dir = TempDir::new().unwrap();
        let planning = dir.path().join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();

        let lock = planning.join(".active-agent-count.lock");
        let _ = fs::remove_dir(&lock);
        let _ = fs::remove_dir("/tmp/yolo-agent-pid-lock");

        let input1 = make_input(r#"{"agent_type":"yolo-dev","pid":999991}"#);
        let _ = handle(&input1, &planning);

        let _ = fs::remove_dir(&lock);
        let _ = fs::remove_dir("/tmp/yolo-agent-pid-lock");

        let input2 = make_input(r#"{"agent_type":"yolo-lead","pid":999992}"#);
        let _ = handle(&input2, &planning);

        let count = fs::read_to_string(planning.join(".active-agent-count")).unwrap();
        assert_eq!(count.trim(), "2");
    }
}
