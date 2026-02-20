use std::path::Path;
use std::fs;
use chrono::{DateTime, Utc};
use serde_json::{Value, json, Map};

fn load_jsonl(path: &Path) -> Vec<Value> {
    let mut res = Vec::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            if let Ok(v) = serde_json::from_str::<Value>(line) {
                res.push(v);
            }
        }
    }
    res
}

fn build_measurement(cwd: &Path, phase_filter: Option<&str>) -> Value {
    let planning_dir = cwd.join(".yolo-planning");
    let metrics_file = planning_dir.join(".metrics").join("run-metrics.jsonl");
    let events_file = planning_dir.join(".events").join("event-log.jsonl");
    let budgets_path = cwd.join("config").join("token-budgets.json");

    let events: Vec<Value> = load_jsonl(&events_file);
    let metrics: Vec<Value> = load_jsonl(&metrics_file);

    let ts = Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);

    let mut phases = std::collections::BTreeSet::new();
    for v in &events {
        if let Some(p) = v["phase"].as_str() { phases.insert(p.to_string()); }
        if let Some(p) = v["phase"].as_i64() { phases.insert(p.to_string()); }
    }
    for v in &metrics {
        if let Some(p) = v["phase"].as_str() { phases.insert(p.to_string()); }
        if let Some(p) = v["phase"].as_i64() { phases.insert(p.to_string()); }
    }

    let filter_set: Option<std::collections::BTreeSet<String>> = phase_filter.map(|f| {
        let mut s = std::collections::BTreeSet::new();
        s.insert(f.to_string());
        s
    });

    let target_phases = filter_set.unwrap_or(phases);

    let mut phases_map = Map::new();
    let mut total_overages = 0;
    let mut total_truncated = 0;
    let mut total_tasks = 0;
    let mut total_escalations = 0;

    for phase in target_phases {
        let mut p_overages = 0;
        let mut p_truncated = 0;
        let mut p_tasks = 0;
        let mut p_escalations = 0;

        for e in &events {
            let matches_phase = e["phase"].as_str() == Some(&phase) || e["phase"].as_i64() == phase.parse::<i64>().ok();
            if matches_phase {
                if e["event"] == "task_started" { p_tasks += 1; }
                if e["event"] == "token_cap_escalated" { p_escalations += 1; }
            }
        }

        for m in &metrics {
            let matches_phase = m["phase"].as_str() == Some(&phase) || m["phase"].as_i64() == phase.parse::<i64>().ok();
            if matches_phase {
                if m["event"] == "token_overage" {
                    p_overages += 1;
                    if let Some(data) = m["data"].as_object() {
                        let trunc = data.get("chars_truncated").or_else(|| data.get("lines_truncated"));
                        if let Some(t) = trunc {
                            if let Some(num) = t.as_i64() { p_truncated += num; }
                            else if let Some(s) = t.as_str() { p_truncated += s.parse::<i64>().unwrap_or(0); }
                        }
                    }
                }
            }
        }

        let p_opt = if p_tasks > 0 { (p_overages as f64) / (p_tasks as f64) } else { 0.0 };

        phases_map.insert(phase, json!({
            "overages": p_overages,
            "truncated_chars": p_truncated,
            "tasks": p_tasks,
            "escalations_legacy": p_escalations,
            "overages_per_task": p_opt
        }));

        total_overages += p_overages;
        total_truncated += p_truncated;
        total_tasks += p_tasks;
        total_escalations += p_escalations;
    }

    let total_opt = if total_tasks > 0 { (total_overages as f64) / (total_tasks as f64) } else { 0.0 };

    let mut budget_map = Map::new();
    if budgets_path.exists() {
        if let Ok(content) = fs::read_to_string(&budgets_path) {
            if let Ok(budgets_json) = serde_json::from_str::<Value>(&content) {
                if let Some(budgets) = budgets_json["budgets"].as_object() {
                    for role in budgets.keys() {
                        let mut r_total = 0;
                        let mut r_max = 0;
                        for m in &metrics {
                            if m["event"] == "token_overage" && m["data"]["role"].as_str() == Some(role) {
                                if let Some(data) = m["data"].as_object() {
                                    let t = data.get("chars_total").or_else(|| data.get("lines_total"));
                                    if let Some(v) = t {
                                        if let Some(num) = v.as_i64() { r_total += num; }
                                        else if let Some(s) = v.as_str() { r_total += s.parse::<i64>().unwrap_or(0); }
                                    }
                                    let mx = data.get("chars_max").or_else(|| data.get("lines_max"));
                                    if let Some(v) = mx {
                                        if let Some(num) = v.as_i64() { r_max += num; }
                                        else if let Some(s) = v.as_str() { r_max += s.parse::<i64>().unwrap_or(0); }
                                    }
                                }
                            }
                        }
                        let r_pct = if r_max > 0 { (r_total * 100) / r_max } else { 0 };
                        budget_map.insert(role.clone(), json!({
                            "total_chars": r_total,
                            "max_chars": r_max,
                            "utilization_pct": r_pct
                        }));
                    }
                }
            }
        }
    }

    json!({
        "timestamp": ts,
        "phases": phases_map,
        "totals": {
            "overages": total_overages,
            "truncated_chars": total_truncated,
            "tasks": total_tasks,
            "escalations_legacy": total_escalations,
            "overages_per_task": total_opt
        },
        "budget_utilization": budget_map
    })
}

fn get_direction(d: f64) -> &'static str {
    if d > 0.0005 { "worse" }
    else if d < -0.0005 { "better" }
    else { "same" }
}

fn build_comparison(cwd: &Path, phase_filter: Option<&str>) -> Option<Value> {
    let baseline_file = cwd.join(".yolo-planning").join(".baselines").join("token-baseline.json");
    if !baseline_file.exists() {
        return None;
    }

    let b_content = fs::read_to_string(&baseline_file).unwrap_or_default();
    let baseline: Value = serde_json::from_str(&b_content).ok()?;
    let current = build_measurement(cwd, phase_filter);

    let get_val = |v: &Value, prop1: &str, prop2: &str| -> i64 {
        v["totals"][prop1].as_i64()
            .or_else(|| v["totals"][prop2].as_i64())
            .unwrap_or(0)
    };

    let b_ov = get_val(&baseline, "overages", "overages");
    let c_ov = get_val(&current, "overages", "overages");
    let b_tr = get_val(&baseline, "truncated_chars", "truncated_lines");
    let c_tr = get_val(&current, "truncated_chars", "truncated_lines");
    let b_es = get_val(&baseline, "escalations_legacy", "escalations");
    let c_es = get_val(&current, "escalations_legacy", "escalations");

    let b_opt = baseline["totals"]["overages_per_task"].as_f64().unwrap_or(0.0);
    let c_opt = current["totals"]["overages_per_task"].as_f64().unwrap_or(0.0);

    let mut phase_changes = Map::new();
    let b_phases = baseline["phases"].as_object().unwrap_or(&Map::new()).clone();
    let c_phases = current["phases"].as_object().unwrap_or(&Map::new()).clone();

    for key in b_phases.keys() {
        if !c_phases.contains_key(key) {
            phase_changes.insert(key.clone(), json!("removed"));
        }
    }
    for key in c_phases.keys() {
        if !b_phases.contains_key(key) {
            phase_changes.insert(key.clone(), json!("new"));
        }
    }

    Some(json!({
        "baseline_timestamp": baseline["timestamp"].as_str().unwrap_or("unknown"),
        "current_timestamp": current["timestamp"].as_str().unwrap_or("unknown"),
        "deltas": {
            "overages": { "baseline": b_ov, "current": c_ov, "delta": c_ov - b_ov, "direction": get_direction((c_ov - b_ov) as f64) },
            "truncated_chars": { "baseline": b_tr, "current": c_tr, "delta": c_tr - b_tr, "direction": get_direction((c_tr - b_tr) as f64) },
            "escalations_legacy": { "baseline": b_es, "current": c_es, "delta": c_es - b_es, "direction": get_direction((c_es - b_es) as f64) },
            "overages_per_task": { "baseline": b_opt, "current": c_opt, "delta": c_opt - b_opt, "direction": get_direction(c_opt - b_opt) }
        },
        "phase_changes": phase_changes
    }))
}

fn build_report(cwd: &Path, phase_filter: Option<&str>) -> String {
    let current = build_measurement(cwd, phase_filter);
    let baseline_file = cwd.join(".yolo-planning").join(".baselines").join("token-baseline.json");

    let mut out = String::new();
    out.push_str("# Token Usage Baseline Report\n\n");
    out.push_str(&format!("Generated: {}\n", current["timestamp"].as_str().unwrap_or("unknown")));
    if let Some(pf) = phase_filter {
        out.push_str(&format!("Phase filter: {}\n", pf));
    }
    out.push_str("\n## Per-Phase Summary\n");
    out.push_str("| Phase | Overages | Chars Truncated | Tasks | Overages/Task |\n");
    out.push_str("|-------|----------|-----------------|-------|---------------|\n");

    let phases = current["phases"].as_object().unwrap_or(&Map::new()).clone();
    let mut keys: Vec<String> = phases.keys().cloned().collect();
    keys.sort_by(|a, b| a.parse::<i64>().unwrap_or(0).cmp(&b.parse::<i64>().unwrap_or(0))); // Sort numerically if possible

    for k in keys {
        let p = &phases[&k];
        out.push_str(&format!("| {} | {} | {} | {} | {:.2} |\n",
            k,
            p["overages"].as_i64().unwrap_or(0),
            p["truncated_chars"].as_i64().unwrap_or(0),
            p["tasks"].as_i64().unwrap_or(0),
            p["overages_per_task"].as_f64().unwrap_or(0.0)
        ));
    }

    let t = &current["totals"];
    out.push_str(&format!("| **Total** | **{}** | **{}** | **{}** | **{:.2}** |\n\n",
        t["overages"].as_i64().unwrap_or(0),
        t["truncated_chars"].as_i64().unwrap_or(0),
        t["tasks"].as_i64().unwrap_or(0),
        t["overages_per_task"].as_f64().unwrap_or(0.0)
    ));

    out.push_str("## Budget Utilization\n");
    out.push_str("| Role | Total Chars | Budget Max | Utilization |\n");
    out.push_str("|------|-------------|-----------|-------------|\n");
    
    let budget = current["budget_utilization"].as_object().unwrap_or(&Map::new()).clone();
    let mut has_budget = false;
    for (role, b) in budget {
        let t_chars = b["total_chars"].as_i64().or_else(|| b.get("total_lines").and_then(|v| v.as_i64())).unwrap_or(0);
        let m_chars = b["max_chars"].as_i64().or_else(|| b.get("max_lines").and_then(|v| v.as_i64())).unwrap_or(0);
        let pct = b["utilization_pct"].as_i64().unwrap_or(0);
        if t_chars > 0 || m_chars > 0 {
            out.push_str(&format!("| {} | {} | {} | {}% |\n", role, t_chars, m_chars, pct));
            has_budget = true;
        }
    }
    if !has_budget {
        out.push_str("| (no overage data) | - | - | - |\n");
    }
    out.push_str("\n");

    out.push_str("## Comparison with Baseline\n");
    if baseline_file.exists() {
        if let Some(comp) = build_comparison(cwd, phase_filter) {
            out.push_str(&format!("Baseline from: {}\n\n", comp["baseline_timestamp"].as_str().unwrap_or("unknown")));
            out.push_str("| Metric | Baseline | Current | Delta | Direction |\n");
            out.push_str("|--------|----------|---------|-------|-----------|\n");
            let deltas = &comp["deltas"];
            
            let ov = &deltas["overages"];
            let tr = &deltas["truncated_chars"];
            
            let fmt_delta = |d: i64| -> String { if d > 0 { format!("+{}", d) } else { d.to_string() } };
            
            out.push_str(&format!("| Overages | {} | {} | {} | {} |\n",
                ov["baseline"].as_i64().unwrap_or(0), ov["current"].as_i64().unwrap_or(0), fmt_delta(ov["delta"].as_i64().unwrap_or(0)), ov["direction"].as_str().unwrap_or("same")
            ));
            out.push_str(&format!("| Truncated Chars | {} | {} | {} | {} |\n",
                tr["baseline"].as_i64().unwrap_or(0), tr["current"].as_i64().unwrap_or(0), fmt_delta(tr["delta"].as_i64().unwrap_or(0)), tr["direction"].as_str().unwrap_or("same")
            ));
        }
    } else {
        out.push_str("\nNo baseline available. Run `yolo token-baseline measure --save` to create a baseline for comparison.\n");
    }
    out.push_str("\n");
    out
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let mut action = "measure";
    let mut phase_filter: Option<String> = None;
    let mut save = false;

    for arg in args.iter().skip(2) {
        if arg == "measure" || arg == "compare" || arg == "report" {
            action = arg;
        } else if arg.starts_with("--phase=") {
            phase_filter = Some(arg.replace("--phase=", ""));
        } else if arg == "--save" {
            save = true;
        }
    }

    let planning_dir = cwd.join(".yolo-planning");
    let metrics_file = planning_dir.join(".metrics").join("run-metrics.jsonl");
    let events_file = planning_dir.join(".events").join("event-log.jsonl");

    if !metrics_file.exists() && !events_file.exists() {
        return Ok(("No event data found. Enable v3_event_log=true and v3_metrics=true in config.\n".to_string(), 0));
    }

    let result = match action {
        "measure" => {
            let res = build_measurement(cwd, phase_filter.as_deref());
            let out_str = res.to_string();
            if save {
                let baselines_dir = planning_dir.join(".baselines");
                let _ = fs::create_dir_all(&baselines_dir);
                let _ = fs::write(baselines_dir.join("token-baseline.json"), &out_str);
            }
            out_str
        }
        "compare" => {
            if let Some(comp) = build_comparison(cwd, phase_filter.as_deref()) {
                comp.to_string()
            } else {
                "No baseline found. Run with --save first.\n".to_string()
            }
        }
        "report" => {
            build_report(cwd, phase_filter.as_deref())
        }
        _ => "".to_string()
    };

    Ok((result, 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_execute_no_data() {
        let dir = tempdir().unwrap();
        let (out, code) = execute(&["yolo".to_string(), "token-baseline".to_string()], dir.path()).unwrap();
        assert_eq!(code, 0);
        assert!(out.contains("No event data found"));
    }

    #[test]
    fn test_execute_measure_and_compare() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        fs::create_dir(plan_dir.join(".metrics")).unwrap();
        fs::create_dir(plan_dir.join(".events")).unwrap();
        fs::create_dir(dir.path().join("config")).unwrap();
        
        fs::write(plan_dir.join(".events").join("event-log.jsonl"), r#"
{"event": "task_started", "ts": "2023-10-01T12:00:00Z", "phase": "1"}
{"event": "task_started", "ts": "2023-10-01T12:05:00Z", "phase": "2"}
        "#).unwrap();

        fs::write(plan_dir.join(".metrics").join("run-metrics.jsonl"), r#"
{"event": "token_overage", "phase": "1", "data": {"chars_truncated": 500, "role": "architect", "chars_total": 1000, "chars_max": 2000}}
        "#).unwrap();

        fs::write(dir.path().join("config").join("token-budgets.json"), r#"
{"budgets": {"architect": {}, "reviewer": {}}}
        "#).unwrap();

        // 1. Measure and save
        let (out_meas, _) = execute(&["yolo".to_string(), "token-baseline".to_string(), "measure".to_string(), "--save".to_string()], dir.path()).unwrap();
        let meas_json: Value = serde_json::from_str(&out_meas).unwrap();
        assert_eq!(meas_json["totals"]["tasks"].as_i64().unwrap(), 2);
        assert_eq!(meas_json["totals"]["overages"].as_i64().unwrap(), 1);
        
        let arch_budget = &meas_json["budget_utilization"]["architect"];
        assert_eq!(arch_budget["total_chars"].as_i64().unwrap(), 1000);
        assert_eq!(arch_budget["utilization_pct"].as_i64().unwrap(), 50);

        // 2. Compare (no changes should yield 0 deltas)
        let (out_comp, _) = execute(&["yolo".to_string(), "token-baseline".to_string(), "compare".to_string()], dir.path()).unwrap();
        let comp_json: Value = serde_json::from_str(&out_comp).unwrap();
        assert_eq!(comp_json["deltas"]["overages"]["delta"].as_i64().unwrap(), 0);

        // 3. Report
        let (out_rep, _) = execute(&["yolo".to_string(), "token-baseline".to_string(), "report".to_string()], dir.path()).unwrap();
        assert!(out_rep.contains("## Per-Phase Summary"));
        assert!(out_rep.contains("## Budget Utilization"));
        assert!(out_rep.contains("| architect | 1000 | 2000 | 50% |"));
    }
}
