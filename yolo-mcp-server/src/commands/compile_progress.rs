use std::fs;
use std::path::Path;
use regex::Regex;
use serde_json::json;
use super::structured_response::Timer;
use super::utils;

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let timer = Timer::start();

    let planning_dir_arg = args.get(2).map(|s| s.as_str()).unwrap_or(".yolo-planning");
    let planning_dir = cwd.join(planning_dir_arg);

    // Resolve active milestone
    let milestones_dir = planning_dir.join("milestones");
    let (milestone_name, phases_dir) = resolve_milestone(&planning_dir, &milestones_dir);

    if phases_dir.is_none() {
        let resp = json!({
            "ok": true,
            "cmd": "compile-progress",
            "milestone": serde_json::Value::Null,
            "phases": { "total": 0, "completed": 0, "in_progress": 0, "pending": 0 },
            "plans": { "total": 0, "completed": 0, "in_progress": 0, "pending": 0 },
            "tasks": { "total": 0, "completed": 0, "in_progress": 0, "pending": 0 },
            "overall_pct": 0.0,
            "active_phase": serde_json::Value::Null,
            "active_phase_title": serde_json::Value::Null,
            "elapsed_ms": timer.elapsed_ms()
        });
        return Ok((resp.to_string(), 0));
    }

    let phases_dir = phases_dir.unwrap();
    let phase_dirs = utils::sorted_phase_dirs(&phases_dir);

    let mut phases_completed = 0usize;
    let mut phases_in_progress = 0usize;
    let mut phases_pending = 0usize;
    let mut plans_total = 0usize;
    let mut plans_completed = 0usize;
    let mut plans_in_progress = 0usize;
    let mut plans_pending = 0usize;
    let mut tasks_total = 0usize;
    let mut tasks_completed = 0usize;
    let mut active_phase: Option<String> = None;
    let mut active_phase_title: Option<String> = None;

    let task_re = Regex::new(r"^## Task \d+").unwrap();

    for (dirname, path) in &phase_dirs {
        let (p_count, s_count) = count_plans_and_summaries(path);
        plans_total += p_count;
        plans_completed += s_count;

        if p_count > 0 && s_count >= p_count {
            phases_completed += 1;
        } else if p_count > 0 && s_count > 0 {
            phases_in_progress += 1;
            plans_in_progress += p_count - s_count;
        } else if p_count > 0 {
            phases_in_progress += 1;
            plans_pending += p_count;
        } else {
            phases_pending += 1;
        }

        if active_phase.is_none() && (p_count == 0 || s_count < p_count) {
            let num = dirname.split('-').next().unwrap_or("").trim_start_matches('0');
            active_phase = Some(if num.is_empty() { "0".to_string() } else { num.to_string() });
            let title = dirname.split('-').skip(1).collect::<Vec<_>>().join("-");
            active_phase_title = Some(title);
        }

        // Count tasks in plan files
        let (t_total, t_completed) = count_tasks_in_phase(path, &task_re);
        tasks_total += t_total;
        tasks_completed += t_completed;
    }

    let tasks_in_progress = tasks_total.saturating_sub(tasks_completed);
    let overall_pct = if tasks_total > 0 {
        ((tasks_completed as f64 / tasks_total as f64) * 1000.0).round() / 10.0
    } else {
        0.0
    };

    let resp = json!({
        "ok": true,
        "cmd": "compile-progress",
        "milestone": milestone_name,
        "phases": {
            "total": phase_dirs.len(),
            "completed": phases_completed,
            "in_progress": phases_in_progress,
            "pending": phases_pending
        },
        "plans": {
            "total": plans_total,
            "completed": plans_completed,
            "in_progress": plans_in_progress,
            "pending": plans_pending
        },
        "tasks": {
            "total": tasks_total,
            "completed": tasks_completed,
            "in_progress": tasks_in_progress,
            "pending": 0
        },
        "overall_pct": overall_pct,
        "active_phase": active_phase,
        "active_phase_title": active_phase_title,
        "elapsed_ms": timer.elapsed_ms()
    });

    Ok((resp.to_string(), 0))
}

fn resolve_milestone(planning_dir: &Path, milestones_dir: &Path) -> (Option<String>, Option<std::path::PathBuf>) {
    // Check ACTIVE file first
    let active_file = planning_dir.join("ACTIVE");
    if active_file.exists() {
        if let Ok(content) = fs::read_to_string(&active_file) {
            let slug = content.trim();
            if !slug.is_empty() {
                let phases = milestones_dir.join(slug).join("phases");
                if phases.is_dir() {
                    return (Some(slug.to_string()), Some(phases));
                }
            }
        }
    }

    // Try milestones dir - pick the only one or first one
    if milestones_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(milestones_dir) {
            let mut dirs: Vec<_> = entries
                .filter_map(|e| e.ok())
                .filter(|e| e.path().is_dir())
                .collect();
            dirs.sort_by_key(|e| e.file_name());
            if let Some(entry) = dirs.first() {
                let name = entry.file_name().to_string_lossy().to_string();
                let phases = entry.path().join("phases");
                if phases.is_dir() {
                    return (Some(name), Some(phases));
                }
            }
        }
    }

    // Fall back to planning_dir/phases
    let phases = planning_dir.join("phases");
    if phases.is_dir() {
        return (None, Some(phases));
    }

    (None, None)
}

fn count_plans_and_summaries(dir: &Path) -> (usize, usize) {
    let plan_re = Regex::new(r"^\d{2}-\d{2}-PLAN\.md$").unwrap();
    let summary_re = Regex::new(r"^\d{2}-\d{2}-SUMMARY\.md$").unwrap();
    let mut plans = 0;
    let mut summaries = 0;
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if plan_re.is_match(&name) {
                plans += 1;
            } else if summary_re.is_match(&name) {
                summaries += 1;
            }
        }
    }
    (plans, summaries)
}

fn count_tasks_in_phase(dir: &Path, task_re: &Regex) -> (usize, usize) {
    let plan_re = Regex::new(r"^(\d{2}-\d{2})-PLAN\.md$").unwrap();
    let mut total = 0;
    let mut completed = 0;
    if let Ok(entries) = fs::read_dir(dir) {
        let mut plan_files: Vec<_> = entries
            .filter_map(|e| e.ok())
            .filter(|e| {
                let name = e.file_name().to_string_lossy().to_string();
                plan_re.is_match(&name)
            })
            .collect();
        plan_files.sort_by_key(|e| e.file_name());

        for entry in plan_files {
            let name = entry.file_name().to_string_lossy().to_string();
            let prefix = plan_re.captures(&name)
                .and_then(|c| c.get(1))
                .map(|m| m.as_str().to_string())
                .unwrap_or_default();

            let task_count = count_task_headers(&entry.path(), task_re);
            total += task_count;

            let summary_name = format!("{}-SUMMARY.md", prefix);
            if dir.join(&summary_name).exists() {
                completed += task_count;
            }
        }
    }
    (total, completed)
}

fn count_task_headers(path: &Path, task_re: &Regex) -> usize {
    let mut count = 0;
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if task_re.is_match(line) {
                count += 1;
            }
        }
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn make_planning_dir(dir: &Path) -> std::path::PathBuf {
        let planning = dir.join(".yolo-planning");
        fs::create_dir_all(&planning).unwrap();
        planning
    }

    #[test]
    fn test_empty_planning_dir_returns_zeroes() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());
        // No milestones or phases dirs
        let (output, code) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["ok"], true);
        assert_eq!(j["tasks"]["total"], 0);
        assert_eq!(j["plans"]["total"], 0);
        assert_eq!(j["phases"]["total"], 0);
        assert_eq!(j["overall_pct"], 0.0);
        let _ = planning; // suppress unused warning
    }

    #[test]
    fn test_single_phase_with_plans() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());
        let phases = planning.join("phases");
        let p1 = phases.join("01-setup");
        fs::create_dir_all(&p1).unwrap();

        fs::write(p1.join("01-01-PLAN.md"), "## Task 1: Do something\n## Task 2: Another\n").unwrap();
        fs::write(p1.join("01-02-PLAN.md"), "## Task 1: Only one\n").unwrap();
        fs::write(p1.join("01-01-SUMMARY.md"), "done").unwrap();

        let (output, code) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        assert_eq!(code, 0);
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["phases"]["total"], 1);
        assert_eq!(j["plans"]["total"], 2);
        assert_eq!(j["plans"]["completed"], 1);
        assert_eq!(j["tasks"]["total"], 3);
        assert_eq!(j["tasks"]["completed"], 2); // plan 01-01 has 2 tasks, completed
    }

    #[test]
    fn test_phase_with_no_plans_is_pending() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());
        let phases = planning.join("phases");
        fs::create_dir_all(phases.join("01-setup")).unwrap();
        fs::create_dir_all(phases.join("02-build")).unwrap();

        let (output, _) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["phases"]["total"], 2);
        assert_eq!(j["phases"]["pending"], 2);
        assert_eq!(j["phases"]["completed"], 0);
    }

    #[test]
    fn test_overall_percentage_calculation() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());
        let p1 = planning.join("phases").join("01-one");
        fs::create_dir_all(&p1).unwrap();

        // 4 tasks total, 2 completed (in plan 01)
        fs::write(p1.join("01-01-PLAN.md"), "## Task 1: A\n## Task 2: B\n").unwrap();
        fs::write(p1.join("01-02-PLAN.md"), "## Task 1: C\n## Task 2: D\n").unwrap();
        fs::write(p1.join("01-01-SUMMARY.md"), "done").unwrap();

        let (output, _) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["tasks"]["total"], 4);
        assert_eq!(j["tasks"]["completed"], 2);
        assert_eq!(j["overall_pct"], 50.0);
    }

    #[test]
    fn test_active_phase_detection() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());
        let phases = planning.join("phases");

        let p1 = phases.join("01-setup");
        let p2 = phases.join("02-build");
        fs::create_dir_all(&p1).unwrap();
        fs::create_dir_all(&p2).unwrap();

        // Phase 01 fully done
        fs::write(p1.join("01-01-PLAN.md"), "## Task 1: done\n").unwrap();
        fs::write(p1.join("01-01-SUMMARY.md"), "done").unwrap();

        // Phase 02 has plans but not done
        fs::write(p2.join("02-01-PLAN.md"), "## Task 1: pending\n").unwrap();

        let (output, _) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["active_phase"], "2");
        assert_eq!(j["active_phase_title"], "build");
    }

    #[test]
    fn test_milestone_resolution() {
        let dir = tempdir().unwrap();
        let planning = make_planning_dir(dir.path());

        let ms_phases = planning.join("milestones").join("my-milestone").join("phases").join("01-init");
        fs::create_dir_all(&ms_phases).unwrap();
        fs::write(planning.join("ACTIVE"), "my-milestone").unwrap();
        fs::write(ms_phases.join("01-01-PLAN.md"), "## Task 1: work\n").unwrap();

        let (output, _) = execute(&vec!["yolo".into(), "compile-progress".into()], dir.path()).unwrap();
        let j: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(j["milestone"], "my-milestone");
        assert_eq!(j["phases"]["total"], 1);
        assert_eq!(j["tasks"]["total"], 1);
    }
}
