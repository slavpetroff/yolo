use std::fs;
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

const STALE_THRESHOLD_SECS: u64 = 7200; // 2 hours

/// Clean stale agent team directories under CLAUDE_DIR/teams/.
/// Teams with all inbox files older than 2 hours are removed atomically.
/// Returns (teams_cleaned, tasks_cleaned).
pub fn clean_stale_teams(claude_dir: &Path, log_file: &Path) -> (usize, usize) {
    let teams_dir = claude_dir.join("teams");
    let tasks_dir = claude_dir.join("tasks");

    if !teams_dir.is_dir() {
        return (0, 0);
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let unique_id = uuid::Uuid::new_v4();
    let temp_dir = std::env::temp_dir().join(format!("yolo-stale-teams-{unique_id}"));
    let _ = fs::create_dir_all(&temp_dir);

    let mut teams_cleaned = 0usize;
    let mut tasks_cleaned = 0usize;

    let entries = match fs::read_dir(&teams_dir) {
        Ok(e) => e,
        Err(_) => return (0, 0),
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

        // Find most recent file mtime in inboxes
        let inbox_mtime = most_recent_mtime(&inbox_dir);

        let age = now.saturating_sub(inbox_mtime);
        if age < STALE_THRESHOLD_SECS {
            continue;
        }

        let stale_hours = age / 3600;

        // Atomic cleanup: mv to temp, then rm
        let dest = temp_dir.join(&team_name);
        if fs::rename(&team_path, &dest).is_ok() {
            teams_cleaned += 1;
            log_msg(
                log_file,
                &format!("Stale team cleanup: {team_name} (stale for {stale_hours}h)"),
            );
        }

        // Also remove paired tasks directory
        let task_path = tasks_dir.join(&team_name);
        if task_path.is_dir() {
            let task_dest = temp_dir.join(format!("{team_name}-tasks"));
            if fs::rename(&task_path, &task_dest).is_ok() {
                tasks_cleaned += 1;
                log_msg(
                    log_file,
                    &format!("Stale tasks cleanup: {team_name} (paired with team)"),
                );
            }
        }
    }

    // Remove temp directory
    let _ = fs::remove_dir_all(&temp_dir);

    if teams_cleaned > 0 || tasks_cleaned > 0 {
        log_msg(
            log_file,
            &format!("Summary: {teams_cleaned} teams cleaned, {tasks_cleaned} tasks removed"),
        );
    }

    (teams_cleaned, tasks_cleaned)
}

fn most_recent_mtime(dir: &Path) -> u64 {
    let mut latest = 0u64;
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            if let Ok(meta) = entry.metadata()
                && let Ok(mtime) = meta.modified() {
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
    latest
}

fn log_msg(log_file: &Path, msg: &str) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .map(|mut f| {
            let _ = writeln!(f, "[{ts}] {msg}");
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_no_teams_dir() {
        let dir = tempdir().unwrap();
        let log = dir.path().join("test.log");
        let (t, ta) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 0);
        assert_eq!(ta, 0);
    }

    #[test]
    fn test_empty_teams_dir() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("teams")).unwrap();
        let log = dir.path().join("test.log");
        let (t, _) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 0);
    }

    #[test]
    fn test_fresh_team_not_cleaned() {
        let dir = tempdir().unwrap();
        let teams = dir.path().join("teams");
        fs::create_dir(&teams).unwrap();

        // Create a team with current timestamp (fresh)
        let team = teams.join("fresh-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();
        fs::write(inbox.join("msg.json"), "{}").unwrap();

        let log = dir.path().join("test.log");
        let (t, _) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 0);
        assert!(team.exists()); // Not cleaned
    }

    #[test]
    fn test_team_without_inbox_not_cleaned() {
        let dir = tempdir().unwrap();
        let teams = dir.path().join("teams");
        let team = teams.join("no-inbox-team");
        fs::create_dir_all(&team).unwrap();

        let log = dir.path().join("test.log");
        let (t, _) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 0);
        assert!(team.exists());
    }

    #[test]
    fn test_stale_team_cleaned() {
        let dir = tempdir().unwrap();
        let teams = dir.path().join("teams");
        fs::create_dir(&teams).unwrap();

        // Create team with empty inbox dir (mtime=0 => very stale)
        let team = teams.join("old-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();
        // No files in inbox => mtime stays 0 => definitely stale

        let log = dir.path().join("test.log");
        let (t, _) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 1);
        assert!(!team.exists()); // Cleaned

        // Check log
        let log_content = fs::read_to_string(&log).unwrap();
        assert!(log_content.contains("Stale team cleanup: old-team"));
    }

    #[test]
    fn test_paired_tasks_cleaned() {
        let dir = tempdir().unwrap();
        let teams = dir.path().join("teams");
        let tasks = dir.path().join("tasks");
        fs::create_dir(&teams).unwrap();
        fs::create_dir(&tasks).unwrap();

        // Stale team
        let team = teams.join("paired-team");
        let inbox = team.join("inboxes");
        fs::create_dir_all(&inbox).unwrap();

        // Paired tasks dir
        let task = tasks.join("paired-team");
        fs::create_dir(&task).unwrap();

        let log = dir.path().join("test.log");
        let (t, ta) = clean_stale_teams(dir.path(), &log);
        assert_eq!(t, 1);
        assert_eq!(ta, 1);
        assert!(!team.exists());
        assert!(!task.exists());
    }
}
