use std::path::{Path, PathBuf};
use std::fs;
use serde_json::Value;

pub fn update_state(file_path: &str) -> Result<String, String> {
    let path = Path::new(file_path);
    if !path.exists() || !path.is_file() {
        return Ok(format!("File does not exist or is not a file: {}", file_path));
    }

    let file_name = path.file_name().unwrap().to_string_lossy();
    let is_plan = file_name.ends_with("-PLAN.md");
    let is_summary = file_name.ends_with("-SUMMARY.md");

    if !is_plan && !is_summary {
        // Not a target file, fail-open (exit 0)
        return Ok("Not a PLAN.md or SUMMARY.md file".to_string());
    }

    let phase_dir = path.parent().unwrap_or(Path::new(""));
    let planning_root = planning_root_from_phase_dir(phase_dir);

    if is_plan {
        update_state_md(phase_dir, &planning_root)?;
        update_roadmap(phase_dir, &planning_root)?;
        
        let state_md = planning_root.join("STATE.md");
        if state_md.exists() {
            let content = fs::read_to_string(&state_md).unwrap_or_default();
            if content.contains("Status: ready") {
                let updated = content.replace("Status: ready", "Status: active");
                let _ = fs::write(&state_md, updated);
            }
        }
    } else if is_summary {
        let (phase, plan, status) = parse_summary_frontmatter(path);
        let summary_id = file_name.trim_end_matches("-SUMMARY.md").to_string();
        
        let mut final_phase = phase.clone();
        if final_phase.is_empty() {
            final_phase = phase_dir.file_name().unwrap_or_default().to_string_lossy().to_string();
            final_phase = final_phase.split('-').next().unwrap_or("").trim_start_matches('0').to_string();
            if final_phase.is_empty() { final_phase = "0".to_string(); }
        }

        let mut final_plan = plan.clone();
        if final_plan.is_empty() {
            final_plan = summary_id.split('-').skip(1).collect::<Vec<_>>().join("-");
            if final_plan.is_empty() { final_plan = summary_id.clone(); }
        }

        let final_status = if status.is_empty() { "completed".to_string() } else { status };

        update_execution_state(&planning_root, &final_phase, &final_plan, &final_status, &summary_id);
        
        update_state_md(phase_dir, &planning_root)?;
        update_roadmap(phase_dir, &planning_root)?;
        update_model_profile(phase_dir, &planning_root)?;
        advance_phase(phase_dir, &planning_root)?;
    }

    Ok("State updated successfully".to_string())
}

fn planning_root_from_phase_dir(phase_dir: &Path) -> PathBuf {
    let phases_dir = phase_dir.parent().unwrap_or(Path::new(""));
    phases_dir.parent().unwrap_or(Path::new(".yolo-planning")).to_path_buf()
}

fn update_state_md(phase_dir: &Path, planning_root: &Path) -> Result<(), String> {
    let state_md = planning_root.join("STATE.md");
    if !state_md.exists() {
        return Ok(());
    }

    let (plan_count, summary_count) = count_plans_and_summaries(phase_dir);
    let pct = if plan_count > 0 { (summary_count * 100) / plan_count } else { 0 };

    let content = fs::read_to_string(&state_md).unwrap_or_default();
    let mut new_lines = vec![];

    for line in content.lines() {
        if line.starts_with("Plans: ") {
            new_lines.push(format!("Plans: {}/{}", summary_count, plan_count));
        } else if line.starts_with("Progress: ") {
            new_lines.push(format!("Progress: {}%", pct));
        } else {
            new_lines.push(line.to_string());
        }
    }

    let mut new_content = new_lines.join("\n");
    new_content.push('\n');
    let _ = fs::write(&state_md, new_content);

    Ok(())
}

fn slug_to_name(slug: &str) -> String {
    let trimmed = slug.trim_start_matches(|c: char| c.is_ascii_digit() || c == '-');
    let words: Vec<&str> = trimmed.split('-').collect();
    words.into_iter().map(|w| {
        let mut chars = w.chars();
        match chars.next() {
            None => String::new(),
            Some(f) => f.to_uppercase().collect::<String>() + chars.as_str(),
        }
    }).collect::<Vec<String>>().join(" ")
}

fn update_roadmap(phase_dir: &Path, planning_root: &Path) -> Result<(), String> {
    let roadmap = planning_root.join("ROADMAP.md");
    if !roadmap.exists() {
        return Ok(());
    }

    let dirname = phase_dir.file_name().unwrap_or_default().to_string_lossy().to_string();
    let phase_num_str = dirname.split('-').next().unwrap_or("").trim_start_matches('0');
    if phase_num_str.is_empty() {
        return Ok(());
    }

    let (plan_count, summary_count) = count_plans_and_summaries(phase_dir);
    if plan_count == 0 {
        return Ok(());
    }

    let (status, date_str) = if summary_count == plan_count {
        ("complete", chrono::Local::now().format("%Y-%m-%d").to_string())
    } else if summary_count > 0 {
        ("in progress", "-".to_string())
    } else {
        ("planned", "-".to_string())
    };

    let content = fs::read_to_string(&roadmap).unwrap_or_default();
    let mut existing_name = String::new();
    let search_prefix = format!("| {} - ", phase_num_str);
    let search_prefix_space = format!("|  {} - ", phase_num_str);
    let search_prefix_alt = format!("|   {} - ", phase_num_str);

    for line in content.lines() {
        if line.starts_with(&search_prefix) || line.starts_with(&search_prefix_space) || line.starts_with(&search_prefix_alt) {
            let parts: Vec<&str> = line.split('|').collect();
            if parts.len() > 1 {
                let name_part = parts[1].trim();
                if let Some(idx) = name_part.find('-') {
                    existing_name = name_part[idx+1..].trim().to_string();
                    break;
                }
            }
        }
    }

    if existing_name.is_empty() {
        return Ok(());
    }

    let mut new_lines = vec![];
    for line in content.lines() {
        if line.starts_with(&search_prefix) || line.starts_with(&search_prefix_space) || line.starts_with(&search_prefix_alt) {
            new_lines.push(format!("| {} - {} | {}/{} | {} | {} |", phase_num_str, existing_name, summary_count, plan_count, status, date_str));
        } else if status == "complete" && line.starts_with(&format!("- [ ] Phase {}:", phase_num_str)) {
            new_lines.push(line.replace("- [ ]", "- [x]"));
        } else {
            new_lines.push(line.to_string());
        }
    }

    let mut new_content = new_lines.join("\n");
    new_content.push('\n');
    let _ = fs::write(&roadmap, new_content);

    Ok(())
}

fn update_model_profile(phase_dir: &Path, planning_root: &Path) -> Result<(), String> {
    let state_md = planning_root.join("STATE.md");
    if !state_md.exists() {
        return Ok(());
    }

    let mut config_file = planning_root.join("config.json");
    if !config_file.exists() {
        config_file = PathBuf::from(".yolo-planning/config.json");
    }

    let mut model_profile = "quality".to_string();
    if config_file.exists() {
        if let Ok(content) = fs::read_to_string(&config_file) {
            if let Ok(json) = serde_json::from_str::<Value>(&content) {
                if let Some(prof) = json.get("model_profile").and_then(|v| v.as_str()) {
                    model_profile = prof.to_string();
                }
            }
        }
    }

    let content = fs::read_to_string(&state_md).unwrap_or_default();
    if !content.contains("## Codebase Profile") {
        return Ok(());
    }

    let mut new_lines = vec![];
    let mut found = false;
    for line in content.lines() {
        if line.starts_with("- **Model Profile:**") {
            new_lines.push(format!("- **Model Profile:** {}", model_profile));
            found = true;
        } else {
            new_lines.push(line.to_string());
            if line.starts_with("- **Test Coverage:**") && !found {
                // Determine if Model Profile line was already seen/added. We will add it right after Test Coverage if not found.
                // Wait, if it exists later, this adds a duplicate. We will do a full scan first.
            }
        }
    }

    if !found {
        let mut final_lines = vec![];
        for line in new_lines {
            final_lines.push(line.clone());
            if line.starts_with("- **Test Coverage:**") {
                final_lines.push(format!("- **Model Profile:** {}", model_profile));
            }
        }
        new_lines = final_lines;
    }

    let mut new_content = new_lines.join("\n");
    new_content.push('\n');
    let _ = fs::write(&state_md, new_content);

    Ok(())
}

fn advance_phase(phase_dir: &Path, planning_root: &Path) -> Result<(), String> {
    let state_md = planning_root.join("STATE.md");
    if !state_md.exists() {
        return Ok(());
    }

    let (plan_count, summary_count) = count_plans_and_summaries(phase_dir);
    if plan_count == 0 || summary_count < plan_count {
        return Ok(());
    }

    let phases_dir = phase_dir.parent().unwrap_or(Path::new(""));
    let mut entries = match fs::read_dir(phases_dir) {
        Ok(entries) => entries.filter_map(|e| e.ok()).collect::<Vec<_>>(),
        Err(_) => return Ok(()),
    };
    entries.sort_by_key(|e| e.path());

    let total = entries.iter().filter(|e| e.path().is_dir()).count();
    let mut next_num = String::new();
    let mut next_name = String::new();
    let mut all_done = true;

    for entry in entries.iter().filter(|e| e.path().is_dir()) {
        let (p, s) = count_plans_and_summaries(&entry.path());
        if p == 0 || s < p {
            if next_num.is_empty() {
                let dirname = entry.file_name().to_string_lossy().to_string();
                next_num = dirname.split('-').next().unwrap_or("").trim_start_matches('0').to_string();
                if next_num.is_empty() { next_num = "0".to_string(); }
                next_name = slug_to_name(&dirname);
            }
            all_done = false;
            break;
        }
    }

    if total == 0 {
        return Ok(());
    }

    let content = fs::read_to_string(&state_md).unwrap_or_default();
    let mut new_lines = vec![];

    for line in content.lines() {
        if all_done {
            if line.starts_with("Status: ") {
                new_lines.push("Status: complete".to_string());
            } else {
                new_lines.push(line.to_string());
            }
        } else if !next_num.is_empty() {
            if line.starts_with("Phase: ") {
                new_lines.push(format!("Phase: {} of {} ({})", next_num, total, next_name));
            } else if line.starts_with("Status: ") {
                new_lines.push("Status: ready".to_string());
            } else {
                new_lines.push(line.to_string());
            }
        } else {
            new_lines.push(line.to_string());
        }
    }

    let mut new_content = new_lines.join("\n");
    new_content.push('\n');
    let _ = fs::write(&state_md, new_content);

    Ok(())
}

fn parse_summary_frontmatter(path: &Path) -> (String, String, String) {
    let mut phase = String::new();
    let mut plan = String::new();
    let mut status = String::new();
    let mut in_frontmatter = false;

    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if line == "---" {
                if !in_frontmatter {
                    in_frontmatter = true;
                    continue;
                } else {
                    break;
                }
            }
            if in_frontmatter {
                let parts: Vec<&str> = line.splitn(2, ':').collect();
                if parts.len() == 2 {
                    let key = parts[0].trim();
                    let val = parts[1].trim().trim_matches('"').trim_matches('\'');
                    match key {
                        "phase" => phase = val.to_string(),
                        "plan" => plan = val.to_string(),
                        "status" => status = val.to_string(),
                        _ => {}
                    }
                }
            }
        }
    }
    (phase, plan, status)
}

fn update_execution_state(planning_root: &Path, phase: &str, plan: &str, status: &str, summary_id: &str) {
    let state_file = planning_root.join(".execution-state.json");
    if !state_file.exists() {
        return;
    }

    if let Ok(content) = fs::read_to_string(&state_file) {
        if let Ok(mut json) = serde_json::from_str::<Value>(&content) {
            // Attempt to update
            if let Some(plans) = json.get_mut("plans").and_then(|p| p.as_array_mut()) {
                for p in plans.iter_mut() {
                    let pid = p.get("id").and_then(|v| v.as_str()).unwrap_or("");
                    let pid_last = pid.split('-').last().unwrap_or("");
                    if pid == summary_id || pid == plan || (pid_last.parse::<u64>().is_ok() && plan.parse::<u64>().is_ok() && pid_last == plan) {
                        if let Some(obj) = p.as_object_mut() {
                            obj.insert("status".to_string(), Value::String(status.to_string()));
                        }
                    }
                }
            } else if let Some(phases) = json.get_mut("phases").and_then(|p| p.as_object_mut()) {
                if let Some(phase_obj) = phases.get_mut(phase).and_then(|p| p.as_object_mut()) {
                    if let Some(plan_obj) = phase_obj.get_mut(plan).and_then(|p| p.as_object_mut()) {
                        plan_obj.insert("status".to_string(), Value::String(status.to_string()));
                    }
                }
            }

            if let Ok(updated) = serde_json::to_string_pretty(&json) {
                let _ = fs::write(&state_file, updated);
            }
        }
    }
}

fn count_plans_and_summaries(dir: &Path) -> (usize, usize) {
    let mut plans = 0;
    let mut summaries = 0;
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with("-PLAN.md") {
                plans += 1;
            } else if name.ends_with("-SUMMARY.md") {
                summaries += 1;
            }
        }
    }
    (plans, summaries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::env;

    fn setup_test_dir(name: &str) -> PathBuf {
        let mut d = env::temp_dir();
        d.push(format!("yolo_test_{}_{}", name, std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_micros()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join(".yolo-planning/phases")).unwrap();
        d
    }

    #[test]
    fn test_slug_to_name() {
        assert_eq!(slug_to_name("01-hello-world"), "Hello World");
        assert_eq!(slug_to_name("2-setup-system"), "Setup System");
        assert_eq!(slug_to_name("feature-x"), "Feature X");
    }

    #[test]
    fn test_planning_root_from_phase_dir() {
        let root = setup_test_dir("root_test");
        fs::create_dir_all(root.join(".yolo-planning/phases/01-test-phase")).unwrap();
        let phase_dir = root.join(".yolo-planning/phases/01-test-phase");
        let res = planning_root_from_phase_dir(&phase_dir);
        assert_eq!(res, root.join(".yolo-planning"));

        // active milestone
        fs::create_dir_all(root.join(".yolo-planning/milestones/ms1/phases/01-ms-phase")).unwrap();
        fs::write(root.join(".yolo-planning/ACTIVE"), "ms1\n").unwrap();
        let phase_dir2 = root.join(".yolo-planning/milestones/ms1/phases/01-ms-phase");
        let res2 = planning_root_from_phase_dir(&phase_dir2);
        assert_eq!(res2, root.join(".yolo-planning/milestones/ms1"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_update_state_plan_trigger() {
        let root = setup_test_dir("plan_trigger");
        let phase_dir = root.join(".yolo-planning/phases/01-test");
        fs::create_dir_all(&phase_dir).unwrap();
        
        let plan_file = phase_dir.join("1-PLAN.md");
        fs::write(&plan_file, "plan content").unwrap();

        let state_md = root.join(".yolo-planning/STATE.md");
        fs::write(&state_md, "Phase: 1 of 1 (Test)\nStatus: ready\nPlans: 0/0\nProgress: 0%\n").unwrap();

        let roadmap = root.join(".yolo-planning/ROADMAP.md");
        fs::write(&roadmap, "| 1 - Test | 0/0 | planned | - |\n- [ ] Phase 1:\n").unwrap();

        let result = update_state(plan_file.to_str().unwrap());
        assert!(result.is_ok());

        let state_content = fs::read_to_string(&state_md).unwrap();
        assert!(state_content.contains("Status: active"));
        assert!(state_content.contains("Plans: 0/1"));
        assert!(state_content.contains("Progress: 0%"));

        let roadmap_content = fs::read_to_string(&roadmap).unwrap();
        assert!(roadmap_content.contains("| 1 - Test | 0/1 | planned | - |"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_update_state_summary_trigger() {
        let root = setup_test_dir("summary_trigger");
        let phase_dir = root.join(".yolo-planning/phases/01-test");
        fs::create_dir_all(&phase_dir).unwrap();
        
        fs::write(phase_dir.join("1-PLAN.md"), "plan 1").unwrap();
        fs::write(phase_dir.join("2-PLAN.md"), "plan 2").unwrap();
        
        let summary_file = phase_dir.join("1-SUMMARY.md");
        fs::write(&summary_file, "---\nphase: \"1\"\nplan: \"1\"\nstatus: \"completed\"\n---\nsummary").unwrap();

        let state_md = root.join(".yolo-planning/STATE.md");
        fs::write(&state_md, "Phase: 1 of 1 (Test)\nStatus: active\nPlans: 0/2\nProgress: 0%\n## Codebase Profile\n- **Test Coverage:** 90%\n").unwrap();

        let roadmap = root.join(".yolo-planning/ROADMAP.md");
        fs::write(&roadmap, "| 1 - Test | 0/2 | planned | - |\n- [ ] Phase 1:\n").unwrap();

        let config_file = root.join(".yolo-planning/config.json");
        fs::write(&config_file, r#"{"model_profile": "speed"}"#).unwrap();

        let exec_state = root.join(".yolo-planning/.execution-state.json");
        fs::write(&exec_state, r#"{"plans": [{"id": "1", "status": "running"}]}"#).unwrap();

        let result = update_state(summary_file.to_str().unwrap());
        assert!(result.is_ok());

        let state_content = fs::read_to_string(&state_md).unwrap();
        assert!(state_content.contains("Plans: 1/2"));
        assert!(state_content.contains("Progress: 50%"));
        assert!(state_content.contains("- **Model Profile:** speed"));

        let roadmap_content = fs::read_to_string(&roadmap).unwrap();
        assert!(roadmap_content.contains("| 1 - Test | 1/2 | in progress | - |"));

        let exec_content = fs::read_to_string(&exec_state).unwrap();
        assert!(exec_content.contains(r#""status": "completed""#));

        // Now add the second summary and trigger advance_phase
        let summary2 = phase_dir.join("2-SUMMARY.md");
        fs::write(&summary2, "---\nphase: \"1\"\nplan: \"2\"\nstatus: \"completed\"\n---\nsummary").unwrap();
        update_state(summary2.to_str().unwrap()).unwrap();

        let state_content_2 = fs::read_to_string(&state_md).unwrap();
        assert!(state_content_2.contains("Plans: 2/2"));
        assert!(state_content_2.contains("Progress: 100%"));
        assert!(state_content_2.contains("Status: complete")); // no next phase, all done

        let roadmap_content_2 = fs::read_to_string(&roadmap).unwrap();
        assert!(roadmap_content_2.contains("| 1 - Test | 2/2 | complete |"));
        assert!(roadmap_content_2.contains("- [x] Phase 1:"));
        
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_advance_phase_next() {
        let root = setup_test_dir("advance_phase");
        let p1 = root.join(".yolo-planning/phases/01-one");
        let p2 = root.join(".yolo-planning/phases/02-two");
        fs::create_dir_all(&p1).unwrap();
        fs::create_dir_all(&p2).unwrap();
        
        fs::write(p1.join("1-PLAN.md"), "").unwrap();
        fs::write(p1.join("1-SUMMARY.md"), "").unwrap();
        
        fs::write(p2.join("1-PLAN.md"), "").unwrap();
        // p2 is incomplete

        let state_md = root.join(".yolo-planning/STATE.md");
        fs::write(&state_md, "Phase: 1 of 2 (One)\nStatus: active\n").unwrap();

        update_state(p1.join("1-SUMMARY.md").to_str().unwrap()).unwrap();

        let content = fs::read_to_string(&state_md).unwrap();
        assert!(content.contains("Phase: 2 of 2 (Two)"));
        assert!(content.contains("Status: ready"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_update_execution_state_phases() {
        let root = setup_test_dir("execution_state_phases");
        let exec_state = root.join(".execution-state.json");
        fs::write(&exec_state, r#"{"phases": {"1": {"1": {"status": "planned"}}}}"#).unwrap();
        
        update_execution_state(&root, "1", "1", "completed", "1");
        
        let content = fs::read_to_string(&exec_state).unwrap();
        assert!(content.contains(r#""status": "completed""#));
        
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_update_state_invalid_files() {
        let root = setup_test_dir("invalid_files");
        
        // Non-existent file
        let res1 = update_state("/does/not/exist.md");
        assert!(res1.unwrap().contains("does not exist"));

        // Not a plan or summary
        let random_file = root.join("random.txt");
        fs::write(&random_file, "data").unwrap();
        let res2 = update_state(random_file.to_str().unwrap());
        assert!(res2.unwrap().contains("Not a PLAN.md or SUMMARY.md file"));
        
        // Directory instead of file
        let dir_path = root.join("some_dir");
        fs::create_dir_all(&dir_path).unwrap();
        let res3 = update_state(dir_path.to_str().unwrap());
        assert!(res3.unwrap().contains("does not exist or is not a file"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn test_edge_cases_and_fallbacks() {
        let root = setup_test_dir("edge_cases");
        let phase_dir = root.join(".yolo-planning/phases/01-test");
        fs::create_dir_all(&phase_dir).unwrap();

        // 1. Missing ROADMAP.md
        let res = update_roadmap(&phase_dir, &root.join(".yolo-planning"));
        assert!(res.is_ok()); // Should return gracefully

        // 2. Missing STATE.md for update_state_md
        let res2 = update_state_md(&phase_dir, &root.join(".yolo-planning"));
        assert!(res2.is_ok());

        // 3. Invalid config.json
        fs::write(root.join(".yolo-planning/config.json"), "invalid json").unwrap();
        let state_md = root.join(".yolo-planning/STATE.md");
        fs::write(&state_md, "## Codebase Profile\n- **Test Coverage:**\n").unwrap();
        update_model_profile(&phase_dir, &root.join(".yolo-planning")).unwrap();
        let content = fs::read_to_string(&state_md).unwrap();
        assert!(content.contains("- **Model Profile:** quality")); // defaults to quality on error

        // 4. Update execution state missing file
        update_execution_state(&root.join(".yolo-planning"), "1", "1", "done", "1");
        
        // 5. update_roadmap empty phase_num_str
        let empty_phase_dir = root.join(".yolo-planning/phases/");
        update_roadmap(&empty_phase_dir, &root.join(".yolo-planning")).unwrap();

        // 6. update_roadmap missing existing_name
        let rm_path = root.join(".yolo-planning/ROADMAP.md");
        fs::write(&rm_path, "no columns here").unwrap();
        update_roadmap(&phase_dir, &root.join(".yolo-planning")).unwrap();

        // 7. update_roadmap with plan count 0
        fs::remove_dir_all(&phase_dir).unwrap();
        fs::create_dir_all(&phase_dir).unwrap(); // empty dir
        update_roadmap(&phase_dir, &root.join(".yolo-planning")).unwrap();

        let _ = fs::remove_dir_all(&root);
    }
}
