use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const STALE_THRESHOLD_SECS: u64 = 7200; // 2 hours
const COMPACTION_MARKER_MAX_AGE_SECS: u64 = 60;

/// Execute the doctor command.
/// action: "scan" or "cleanup"
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let action = if args.len() > 2 { args[2].as_str() } else { "scan" };

    let planning_dir = std::env::var("YOLO_PLANNING_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| cwd.join(".yolo-planning"));

    let claude_dir = resolve_claude_dir();

    match action {
        "scan" => {
            let findings = run_scan(&planning_dir, &claude_dir);
            Ok((findings.join("\n"), 0))
        }
        "cleanup" => {
            let log_file = planning_dir.join(".hook-errors.log");
            let output = run_cleanup(&planning_dir, &claude_dir, &log_file);
            Ok((output, 0))
        }
        _ => Err("Usage: yolo doctor {scan|cleanup}".to_string()),
    }
}

fn resolve_claude_dir() -> std::path::PathBuf {
    if let Ok(dir) = std::env::var("CLAUDE_CONFIG_DIR") {
        if !dir.is_empty() {
            return std::path::PathBuf::from(dir);
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        std::path::PathBuf::from(home).join(".claude")
    } else {
        std::path::PathBuf::from(".claude")
    }
}

/// Run all scan checks and return findings as category|item|detail lines.
fn run_scan(planning_dir: &Path, claude_dir: &Path) -> Vec<String> {
    let mut findings = Vec::new();
    findings.extend(scan_stale_teams(claude_dir));
    findings.extend(scan_orphaned_processes());
    findings.extend(scan_dangling_pids(planning_dir));
    findings.extend(scan_stale_markers(planning_dir));
    findings
}

/// Run cleanup and return summary.
fn run_cleanup(planning_dir: &Path, claude_dir: &Path, log_file: &Path) -> String {
    log_action(log_file, "cleanup started");

    // Count issues before cleanup
    let teams_count = scan_stale_teams(claude_dir).len();
    let orphan_count = scan_orphaned_processes().len();
    let pid_count = scan_dangling_pids(planning_dir).len();
    let marker_count = scan_stale_markers(planning_dir).len();

    // Cleanup stale teams (delegate to existing module)
    super::clean_stale_teams::clean_stale_teams(claude_dir, log_file);

    // Cleanup orphaned processes
    cleanup_orphaned_processes(log_file);

    // Cleanup dangling PIDs
    cleanup_dangling_pids(planning_dir, log_file);

    // Cleanup stale markers
    cleanup_stale_markers(planning_dir, log_file);

    let summary = format!(
        "cleanup complete: teams={teams_count}, orphans={orphan_count}, pids={pid_count}, markers={marker_count}"
    );
    log_action(log_file, &summary);
    summary
}

// --- Scan functions ---

fn scan_stale_teams(claude_dir: &Path) -> Vec<String> {
    let teams_dir = claude_dir.join("teams");
    if !teams_dir.is_dir() {
        return Vec::new();
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let mut findings = Vec::new();
    let entries = match fs::read_dir(&teams_dir) {
        Ok(e) => e,
        Err(_) => return findings,
    };

    for entry in entries.flatten() {
        let team_path = entry.path();
        if !team_path.is_dir() {
            continue;
        }

        let team_name = match entry.file_name().into_string() {
            Ok(n) => n,
            Err(_) => continue,
        };

        let inbox_dir = team_path.join("inboxes");
        if !inbox_dir.is_dir() {
            continue;
        }

        let inbox_mtime = most_recent_mtime(&inbox_dir);
        let age = now.saturating_sub(inbox_mtime);
        if age < STALE_THRESHOLD_SECS {
            continue;
        }

        let hours = age / 3600;
        let minutes = (age % 3600) / 60;
        findings.push(format!("stale_team|{team_name}|age: {hours}h {minutes}m"));
    }

    findings
}

fn scan_orphaned_processes() -> Vec<String> {
    // Find processes with PPID=1 and comm containing "claude"
    let output = match Command::new("ps")
        .args(["-eo", "pid,ppid,comm"])
        .output()
    {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => return Vec::new(),
    };

    let mut findings = Vec::new();
    for line in output.lines().skip(1) {
        // skip header
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 3 {
            continue;
        }
        let pid = fields[0];
        let ppid = fields[1];
        let comm = fields[2];

        if ppid == "1" && comm.to_lowercase().contains("claude") {
            findings.push(format!("orphan_process|{pid}|{comm}"));
        }
    }
    findings
}

fn scan_dangling_pids(planning_dir: &Path) -> Vec<String> {
    let pid_file = planning_dir.join(".agent-pids");
    if !pid_file.exists() {
        return Vec::new();
    }

    let content = match fs::read_to_string(&pid_file) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut findings = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let pid: u32 = match trimmed.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };
        if !process_alive(pid) {
            findings.push(format!("dangling_pid|{pid}|dead"));
        }
    }
    findings
}

fn scan_stale_markers(planning_dir: &Path) -> Vec<String> {
    let mut findings = Vec::new();

    // Check watchdog PID
    let watchdog_pid_file = planning_dir.join(".watchdog-pid");
    if watchdog_pid_file.exists() {
        if let Ok(content) = fs::read_to_string(&watchdog_pid_file) {
            let trimmed = content.trim();
            if let Ok(pid) = trimmed.parse::<u32>() {
                if !process_alive(pid) {
                    findings.push("stale_marker|.watchdog-pid|dead process".to_string());
                }
            }
        }
    }

    // Check compaction marker age
    let compaction_marker = planning_dir.join(".compaction-marker");
    if compaction_marker.exists() {
        if let Ok(meta) = fs::metadata(&compaction_marker) {
            if let Ok(mtime) = meta.modified() {
                let age = SystemTime::now()
                    .duration_since(mtime)
                    .unwrap_or_default()
                    .as_secs();
                if age > COMPACTION_MARKER_MAX_AGE_SECS {
                    findings.push(format!("stale_marker|.compaction-marker|age: {age}s"));
                }
            }
        }
    }

    // Check active agent marker
    let active_agent_file = planning_dir.join(".active-agent");
    if active_agent_file.exists() {
        findings.push("stale_marker|.active-agent|potentially stale".to_string());
    }

    findings
}

// --- Cleanup functions ---

fn cleanup_orphaned_processes(log_file: &Path) {
    let orphans = scan_orphaned_processes();
    if orphans.is_empty() {
        return;
    }

    // Extract PIDs and SIGTERM
    let pids: Vec<u32> = orphans
        .iter()
        .filter_map(|line| {
            let parts: Vec<&str> = line.split('|').collect();
            if parts.len() >= 2 {
                parts[1].parse::<u32>().ok()
            } else {
                None
            }
        })
        .collect();

    for pid in &pids {
        if process_alive(*pid) {
            log_action(log_file, &format!("sent SIGTERM to orphan process {pid}"));
            unsafe {
                libc::kill(*pid as i32, libc::SIGTERM);
            }
        }
    }

    // Wait 2 seconds
    std::thread::sleep(std::time::Duration::from_secs(2));

    // SIGKILL survivors
    for pid in &pids {
        if process_alive(*pid) {
            log_action(log_file, &format!("sent SIGKILL to survivor process {pid}"));
            unsafe {
                libc::kill(*pid as i32, libc::SIGKILL);
            }
        }
    }

    log_action(log_file, "orphaned processes cleanup completed");
}

fn cleanup_dangling_pids(planning_dir: &Path, log_file: &Path) {
    let pid_file = planning_dir.join(".agent-pids");
    if !pid_file.exists() {
        return;
    }

    let content = match fs::read_to_string(&pid_file) {
        Ok(c) => c,
        Err(_) => return,
    };

    let mut alive_pids = Vec::new();
    let mut pruned = 0u32;

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let pid: u32 = match trimmed.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };
        if process_alive(pid) {
            alive_pids.push(pid);
        } else {
            pruned += 1;
        }
    }

    if alive_pids.is_empty() {
        let _ = fs::remove_file(&pid_file);
    } else {
        let contents: String = alive_pids
            .iter()
            .map(|p| p.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        let _ = fs::write(&pid_file, contents + "\n");
    }

    log_action(log_file, &format!("pruned {pruned} dead PIDs from .agent-pids"));
}

fn cleanup_stale_markers(planning_dir: &Path, log_file: &Path) {
    let markers = [".watchdog-pid", ".compaction-marker", ".active-agent"];
    let mut removed = 0u32;

    for marker_name in &markers {
        let marker_path = planning_dir.join(marker_name);
        if !marker_path.exists() {
            continue;
        }

        let is_stale = match *marker_name {
            ".watchdog-pid" => {
                if let Ok(content) = fs::read_to_string(&marker_path) {
                    if let Ok(pid) = content.trim().parse::<u32>() {
                        !process_alive(pid)
                    } else {
                        false
                    }
                } else {
                    false
                }
            }
            ".compaction-marker" => {
                if let Ok(meta) = fs::metadata(&marker_path) {
                    if let Ok(mtime) = meta.modified() {
                        SystemTime::now()
                            .duration_since(mtime)
                            .unwrap_or_default()
                            .as_secs()
                            > COMPACTION_MARKER_MAX_AGE_SECS
                    } else {
                        false
                    }
                } else {
                    false
                }
            }
            ".active-agent" => true, // Always considered stale in cleanup
            _ => false,
        };

        if is_stale {
            if fs::remove_file(&marker_path).is_ok() {
                log_action(log_file, &format!("removed stale marker: {marker_name}"));
                removed += 1;
            }
        }
    }

    log_action(
        log_file,
        &format!("stale markers cleanup completed: {removed} removed"),
    );
}

// --- Helpers ---

fn most_recent_mtime(dir: &Path) -> u64 {
    let mut latest = 0u64;
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            if let Ok(meta) = entry.metadata() {
                if let Ok(mtime) = meta.modified() {
                    let secs = mtime
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs();
                    if secs > latest {
                        latest = secs;
                    }
                }
            }
        }
    }
    latest
}

fn process_alive(pid: u32) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

fn log_action(log_file: &Path, msg: &str) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .map(|mut f| {
            let _ = writeln!(f, "[{ts}] Doctor cleanup: {msg}");
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_scan_no_issues() {
        let dir = tempdir().unwrap();
        let planning = dir.path().join("planning");
        fs::create_dir(&planning).unwrap();
        let claude = dir.path().join("claude");
        fs::create_dir(&claude).unwrap();

        let findings = run_scan(&planning, &claude);
        assert!(findings.is_empty());
    }

    #[test]
    fn test_scan_stale_teams() {
        let dir = tempdir().unwrap();
        let claude = dir.path().join("claude");
        let teams = claude.join("teams");
        fs::create_dir_all(&teams).unwrap();

        // Stale team (empty inbox => mtime=0)
        let team = teams.join("stale-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();

        let findings = scan_stale_teams(&claude);
        assert_eq!(findings.len(), 1);
        assert!(findings[0].starts_with("stale_team|stale-team|"));
    }

    #[test]
    fn test_scan_fresh_team_skipped() {
        let dir = tempdir().unwrap();
        let claude = dir.path().join("claude");
        let teams = claude.join("teams");
        fs::create_dir_all(&teams).unwrap();

        // Fresh team (file with current mtime)
        let team = teams.join("fresh-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();
        fs::write(inbox.join("msg.json"), "{}").unwrap();

        let findings = scan_stale_teams(&claude);
        assert!(findings.is_empty());
    }

    #[test]
    fn test_scan_dangling_pids() {
        let dir = tempdir().unwrap();
        // Write dead PIDs
        fs::write(dir.path().join(".agent-pids"), "4000001\n4000002\n").unwrap();

        let findings = scan_dangling_pids(dir.path());
        assert_eq!(findings.len(), 2);
        assert!(findings[0].contains("dangling_pid|4000001|dead"));
        assert!(findings[1].contains("dangling_pid|4000002|dead"));
    }

    #[test]
    fn test_scan_dangling_pids_no_file() {
        let dir = tempdir().unwrap();
        let findings = scan_dangling_pids(dir.path());
        assert!(findings.is_empty());
    }

    #[test]
    fn test_scan_stale_watchdog_marker() {
        let dir = tempdir().unwrap();
        // Write a dead PID as watchdog
        fs::write(dir.path().join(".watchdog-pid"), "4000001").unwrap();

        let findings = scan_stale_markers(dir.path());
        assert_eq!(findings.len(), 1);
        assert!(findings[0].contains("stale_marker|.watchdog-pid|dead process"));
    }

    #[test]
    fn test_scan_active_agent_marker() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join(".active-agent"), "some-agent").unwrap();

        let findings = scan_stale_markers(dir.path());
        assert_eq!(findings.len(), 1);
        assert!(findings[0].contains("stale_marker|.active-agent|potentially stale"));
    }

    #[test]
    fn test_cleanup_stale_markers() {
        let dir = tempdir().unwrap();
        let log = dir.path().join("test.log");

        // Create markers
        fs::write(dir.path().join(".watchdog-pid"), "4000001").unwrap();
        fs::write(dir.path().join(".active-agent"), "test").unwrap();

        cleanup_stale_markers(dir.path(), &log);

        assert!(!dir.path().join(".watchdog-pid").exists());
        assert!(!dir.path().join(".active-agent").exists());

        let log_content = fs::read_to_string(&log).unwrap();
        assert!(log_content.contains("removed stale marker: .watchdog-pid"));
        assert!(log_content.contains("removed stale marker: .active-agent"));
        assert!(log_content.contains("2 removed"));
    }

    #[test]
    fn test_cleanup_dangling_pids() {
        let dir = tempdir().unwrap();
        let log = dir.path().join("test.log");

        // Write mix of dead PIDs and our own (alive) PID
        let our_pid = std::process::id();
        fs::write(
            dir.path().join(".agent-pids"),
            format!("4000001\n{our_pid}\n4000002\n"),
        )
        .unwrap();

        cleanup_dangling_pids(dir.path(), &log);

        // File should still exist with our PID
        let content = fs::read_to_string(dir.path().join(".agent-pids")).unwrap();
        assert!(content.contains(&our_pid.to_string()));
        assert!(!content.contains("4000001"));
        assert!(!content.contains("4000002"));

        let log_content = fs::read_to_string(&log).unwrap();
        assert!(log_content.contains("pruned 2 dead PIDs"));
    }

    #[test]
    fn test_cleanup_dangling_pids_all_dead() {
        let dir = tempdir().unwrap();
        let log = dir.path().join("test.log");

        fs::write(dir.path().join(".agent-pids"), "4000001\n4000002\n").unwrap();

        cleanup_dangling_pids(dir.path(), &log);

        // File should be removed entirely
        assert!(!dir.path().join(".agent-pids").exists());
    }

    #[test]
    fn test_execute_scan() {
        let dir = tempdir().unwrap();
        let planning = dir.path().join("planning");
        fs::create_dir(&planning).unwrap();

        // Set env for resolve
        unsafe { std::env::set_var("CLAUDE_CONFIG_DIR", dir.path().join("claude").to_str().unwrap()); }

        let args = vec![
            "yolo".to_string(),
            "doctor".to_string(),
            "scan".to_string(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_ok());
        let (_, code) = result.unwrap();
        assert_eq!(code, 0);

        // Restore
        unsafe { std::env::remove_var("CLAUDE_CONFIG_DIR"); }
    }

    #[test]
    fn test_execute_invalid_action() {
        let dir = tempdir().unwrap();
        let args = vec![
            "yolo".to_string(),
            "doctor".to_string(),
            "invalid".to_string(),
        ];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
    }

    #[test]
    fn test_output_format() {
        let dir = tempdir().unwrap();
        let claude = dir.path().join("claude");
        let teams = claude.join("teams");
        fs::create_dir_all(&teams).unwrap();

        // Create stale team
        let team = teams.join("test-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();

        // Create dangling PID
        let planning = dir.path().join("planning");
        fs::create_dir(&planning).unwrap();
        fs::write(planning.join(".agent-pids"), "4000001\n").unwrap();

        let findings = run_scan(&planning, &claude);

        // All findings should be pipe-delimited with 3 fields
        for finding in &findings {
            let parts: Vec<&str> = finding.split('|').collect();
            assert_eq!(parts.len(), 3, "Expected 3 pipe-delimited fields: {finding}");
        }
    }
}
