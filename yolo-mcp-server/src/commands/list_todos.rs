use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use serde_json::json;
use chrono::{NaiveDate, Utc};
use regex::Regex;

fn resolve_state_path(planning_dir: &Path) -> Result<PathBuf, String> {
    let state_path = planning_dir.join("STATE.md");
    if state_path.exists() {
        return Ok(state_path);
    }

    let active = planning_dir.join("ACTIVE");
    if active.exists() {
        if let Ok(slug) = fs::read_to_string(&active) {
            let slug = slug.trim();
            if !slug.is_empty() && !slug.contains('/') && !slug.contains('\\') {
                let milestone_state = planning_dir.join("milestones").join(slug).join("STATE.md");
                if milestone_state.exists() {
                    return Ok(milestone_state);
                }
            }
        }
    }

    let mut latest_milestone: Option<PathBuf> = None;
    let mut latest_mtime = 0;

    let milestones_dir = planning_dir.join("milestones");
    if milestones_dir.exists() {
        if let Ok(entries) = fs::read_dir(milestones_dir) {
            for entry in entries.filter_map(|e| e.ok()) {
                let ms_dir = entry.path();
                if ms_dir.is_dir() {
                    let st = ms_dir.join("STATE.md");
                    if st.exists() {
                        if let Ok(metadata) = fs::metadata(&st) {
                            if let Ok(modified) = metadata.modified() {
                                let mtime = modified.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs();
                                if mtime > latest_mtime {
                                    latest_mtime = mtime;
                                    latest_milestone = Some(st);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if let Some(lm) = latest_milestone {
        return Ok(lm);
    }

    Err(serde_json::to_string(&json!({
        "status": "error",
        "message": format!("STATE.md not found at {}. Run /yolo:init or check .yolo-planning/ACTIVE.", state_path.display())
    })).unwrap_or_default())
}

fn extract_todos(file: &Path) -> Option<(String, String)> {
    let content = fs::read_to_string(file).unwrap_or_default();
    let mut section_name = String::new();
    let mut lines = String::new();

    let mut found = false;
    let mut sub_found = false;
    let mut in_legacy = false;

    // First try modern "## Todos"
    for line in content.lines() {
        if line == "## Todos" && !found {
            found = true;
            section_name = "## Todos".to_string();
            continue;
        }
        if found {
            if line.starts_with("## ") {
                break;
            }
            if line.starts_with("### ") {
                sub_found = true;
                continue;
            }
            if sub_found && line.starts_with("##") {
                break;
            }
            if !sub_found && line.starts_with("- ") {
                lines.push_str(line);
                lines.push('\n');
            }
        }
    }

    if lines.is_empty() {
        found = false;
        // Try legacy "### Pending Todos"
        for line in content.lines() {
            if line == "### Pending Todos" && !found {
                found = true;
                in_legacy = true;
                section_name = "### Pending Todos".to_string();
                continue;
            }
            if found && in_legacy {
                if line.starts_with("## ") || line.starts_with("### ") {
                    break;
                }
                if line.starts_with("- ") {
                    lines.push_str(line);
                    lines.push('\n');
                }
            }
        }
    }

    if lines.is_empty() {
        return None;
    }

    Some((section_name, lines.trim_end().to_string()))
}

fn relative_age(date_str: &str) -> String {
    if date_str.len() != 10 { return String::new(); }
    let parsed = NaiveDate::parse_from_str(date_str, "%Y-%m-%d");
    if let Ok(then) = parsed {
        let now = Utc::now().date_naive();
        // Calculate difference in days safely
        let days = now.signed_duration_since(then).num_days();

        if days < 0 {
            return String::new();
        } else if days == 0 {
            return "today".to_string();
        } else if days == 1 {
            return "1d ago".to_string();
        } else if days < 30 {
            return format!("{}d ago", days);
        } else if days < 365 {
            return format!("{}mo ago", days / 30);
        } else {
            return format!("{}y ago", days / 365);
        }
    }
    String::new()
}

fn parse_todo_line(line: &str) -> (String, String, String, String) {
    let text = line.trim_start_matches("- ").to_string();
    let mut priority = "normal".to_string();

    if text.starts_with("[HIGH] ") {
        priority = "high".to_string();
    } else if text.starts_with("[low] ") {
        priority = "low".to_string();
    }

    fn get_date_re() -> &'static Regex {
        static RE: OnceLock<Regex> = OnceLock::new();
        RE.get_or_init(|| Regex::new(r"\(added ([0-9]{4}-[0-9]{2}-[0-9]{2})\)").unwrap())
    }

    let mut date_str = String::new();
    if let Some(caps) = get_date_re().captures(&text) {
        if let Some(m) = caps.get(1) {
            date_str = m.as_str().to_string();
        }
    }

    let mut age = String::new();
    if !date_str.is_empty() {
        age = relative_age(&date_str);
    }

    (priority, date_str, age, text)
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let filter = args.get(2).map(|s| s.to_lowercase());
    let filter_str = filter.as_deref();

    let planning_dir = cwd.join(".yolo-planning");
    let state_path = match resolve_state_path(&planning_dir) {
        Ok(p) => p,
        Err(e) => {
            return Ok((e, 0)); // Fail open outputting JSON
        }
    };

    let extracted = extract_todos(&state_path);
    if extracted.is_none() {
        let out = json!({
            "status": "empty",
            "state_path": state_path.to_string_lossy(),
            "section": serde_json::Value::Null,
            "count": 0,
            "filter": filter_str,
            "display": "No pending todos.",
            "items": []
        });
        return Ok((serde_json::to_string(&out).unwrap(), 0));
    }

    let (section_name, raw_output) = extracted.unwrap();

    let mut items = Vec::new();
    let mut display = String::new();
    let mut display_num = 0;
    let mut filtered_count = 0;

    for line in raw_output.lines() {
        if line.trim().is_empty() { continue; }
        let stripped = line.trim_start_matches("- ").trim();
        if stripped.is_empty() { continue; }

        let (pri, date_val, age, text) = parse_todo_line(line);

        if let Some(f) = filter_str {
            if f != pri {
                continue;
            }
        }

        filtered_count += 1;
        display_num += 1;

        items.push(json!({
            "num": display_num,
            "line": line,
            "text": text,
            "priority": pri,
            "date": date_val,
            "age": age
        }));

        let pri_tag = match pri.as_str() {
            "high" => "[HIGH] ",
            "low" => "[low] ",
            _ => ""
        };

        let mut display_text = text.clone();
        display_text = display_text.replacen("[HIGH] ", "", 1);
        display_text = display_text.replacen("[low] ", "", 1);
        fn get_date_suffix_re() -> &'static Regex {
            static RE: OnceLock<Regex> = OnceLock::new();
            RE.get_or_init(|| Regex::new(r" *\(added [0-9]{4}-[0-9]{2}-[0-9]{2}\)$").unwrap())
        }
        display_text = get_date_suffix_re().replace(&display_text, "").to_string();

        let age_suffix = if age.is_empty() { "".to_string() } else { format!(" ({})", age) };
        display.push_str(&format!("{}. {}{}{}\n", display_num, pri_tag, display_text, age_suffix));
    }

    if filtered_count == 0 {
        let msg = if filter_str.is_some() {
            format!("No {}-priority todos found.", filter_str.unwrap_or(""))
        } else {
            "No pending todos.".to_string()
        };
        let out = json!({
            "status": if filter_str.is_some() { "no-match" } else { "empty" },
            "state_path": state_path.to_string_lossy(),
            "section": section_name,
            "count": 0,
            "filter": filter_str,
            "display": msg,
            "items": []
        });
        return Ok((serde_json::to_string(&out).unwrap(), 0));
    }

    let out = json!({
        "status": "ok",
        "state_path": state_path.to_string_lossy(),
        "section": section_name,
        "count": filtered_count,
        "filter": filter_str,
        "display": display,
        "items": items
    });

    Ok((serde_json::to_string(&out).unwrap(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn run_list_todos(args: &[&str], cwd: &Path) -> Result<(String, i32), String> {
        let mut string_args = Vec::new();
        string_args.push("yolo".to_string());
        string_args.push("list-todos".to_string());
        for a in args {
            string_args.push(a.to_string());
        }
        execute(&string_args, cwd)
    }

    #[test]
    fn test_missing_state() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();

        let (out, _) = run_list_todos(&[], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "error");
        assert!(json["message"].as_str().unwrap().contains("STATE.md not found"));
    }

    #[test]
    fn test_empty_todos_modern() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state = plan_dir.join("STATE.md");
        fs::write(&state, "# State\n\n## Todos\nNone.\n").unwrap();

        let (out, _) = run_list_todos(&[], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "empty");
        assert_eq!(json["count"], 0);
    }

    #[test]
    fn test_legacy_todos() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state = plan_dir.join("STATE.md");
        fs::write(&state, "# State\n\n## Misc\n\n### Pending Todos\n- Do this thing\n- And that\n").unwrap();

        let (out, _) = run_list_todos(&[], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "ok");
        assert_eq!(json["section"], "### Pending Todos");
        assert_eq!(json["count"], 2);
    }

    #[test]
    fn test_modern_todos() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state = plan_dir.join("STATE.md");
        fs::write(&state, "# State\n\n## Todos\n- [HIGH] Fix critical bug\n- Normal task\n- [low] Minor tweak (added 2023-01-01)\n\n## Next\n").unwrap();

        let (out, _) = run_list_todos(&[], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "ok");
        assert_eq!(json["section"], "## Todos");
        assert_eq!(json["count"], 3);
        assert_eq!(json["items"][0]["priority"], "high");
        assert_eq!(json["items"][1]["priority"], "normal");
        assert_eq!(json["items"][2]["priority"], "low");
        assert_eq!(json["items"][2]["date"], "2023-01-01");

        let display = json["display"].as_str().unwrap();
        assert!(display.contains("1. [HIGH] Fix critical bug"));
        assert!(display.contains("3. [low] Minor tweak"));
        assert!(display.contains("y ago"));
    }

    #[test]
    fn test_filtered_todos() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state = plan_dir.join("STATE.md");
        fs::write(&state, "# State\n\n## Todos\n- [HIGH] Fix critical bug\n- Normal task\n- [low] Minor tweak (added 2023-01-01)\n\n## Next\n").unwrap();

        let (out, _) = run_list_todos(&["high"], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "ok");
        assert_eq!(json["count"], 1);
        assert_eq!(json["items"][0]["priority"], "high");

        let (out, _) = run_list_todos(&["low"], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["count"], 1);
    }

    #[test]
    fn test_no_match() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state = plan_dir.join("STATE.md");
        fs::write(&state, "# State\n\n## Todos\n- Normal task\n\n## Next\n").unwrap();

        let (out, _) = run_list_todos(&["high"], dir.path()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(json["status"], "no-match");
        assert_eq!(json["count"], 0);
    }
}
