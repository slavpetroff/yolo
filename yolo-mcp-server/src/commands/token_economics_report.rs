use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::process::Command;

use serde_json::{json, Value};

// ANSI color constants (matching statusline.rs)
const C_RESET: &str = "\x1b[0m";
const C_DIM: &str = "\x1b[2m";
const C_BOLD: &str = "\x1b[1m";
const C_CYAN: &str = "\x1b[36m";
const C_GREEN: &str = "\x1b[32m";
const C_YELLOW: &str = "\x1b[33m";
const C_RED: &str = "\x1b[31m";

/// Per-agent token stats grouped by (role, phase).
#[derive(Debug, Default, Clone)]
struct AgentTokenStats {
    input: i64,
    output: i64,
    cache_read: i64,
    cache_write: i64,
}

impl AgentTokenStats {
    fn total(&self) -> i64 {
        self.input + self.output + self.cache_read + self.cache_write
    }
}

/// Parsed command flags.
struct Flags {
    phase_filter: Option<String>,
    json_output: bool,
}

fn parse_flags(args: &[String]) -> Flags {
    let mut flags = Flags {
        phase_filter: None,
        json_output: false,
    };
    for arg in args {
        if arg.starts_with("--phase=") {
            flags.phase_filter = Some(arg["--phase=".len()..].to_string());
        } else if arg == "--json" {
            flags.json_output = true;
        }
    }
    flags
}

fn load_jsonl(path: &Path) -> Vec<Value> {
    let mut res = Vec::new();
    if let Ok(content) = fs::read_to_string(path) {
        for line in content.lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                if let Ok(v) = serde_json::from_str::<Value>(trimmed) {
                    res.push(v);
                }
            }
        }
    }
    res
}

fn matches_phase(entry: &Value, phase: &str) -> bool {
    let phase_i64 = phase.parse::<i64>().ok();
    entry["phase"].as_str() == Some(phase) || entry["phase"].as_i64() == phase_i64
}

/// Build per-agent token stats from metrics JSONL.
fn build_agent_stats(
    metrics: &[Value],
    phase_filter: Option<&str>,
) -> BTreeMap<(String, String), AgentTokenStats> {
    let mut stats: BTreeMap<(String, String), AgentTokenStats> = BTreeMap::new();

    for m in metrics {
        if m["event"].as_str() != Some("agent_token_usage") {
            continue;
        }
        if let Some(pf) = phase_filter {
            if !matches_phase(m, pf) {
                continue;
            }
        }

        let role = m["data"]["role"]
            .as_str()
            .or_else(|| m["role"].as_str())
            .unwrap_or("unknown")
            .to_string();
        let phase = m["phase"]
            .as_i64()
            .map(|p| p.to_string())
            .or_else(|| m["phase"].as_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "?".to_string());

        let entry = stats.entry((role, phase)).or_default();
        entry.input += m["data"]["input_tokens"].as_i64().unwrap_or(0);
        entry.output += m["data"]["output_tokens"].as_i64().unwrap_or(0);
        entry.cache_read += m["data"]["cache_read_tokens"].as_i64().unwrap_or(0);
        entry.cache_write += m["data"]["cache_write_tokens"].as_i64().unwrap_or(0);
    }

    stats
}

/// Calculate cache hit rates.
fn calc_cache_hit_rates(
    stats: &BTreeMap<(String, String), AgentTokenStats>,
) -> (f64, BTreeMap<String, f64>) {
    let mut total_read: i64 = 0;
    let mut total_denominator: i64 = 0;
    let mut per_role: BTreeMap<String, (i64, i64)> = BTreeMap::new();

    for ((role, _), s) in stats {
        let denom = s.cache_read + s.cache_write + s.input;
        total_read += s.cache_read;
        total_denominator += denom;

        let e = per_role.entry(role.clone()).or_insert((0, 0));
        e.0 += s.cache_read;
        e.1 += denom;
    }

    let overall = if total_denominator > 0 {
        (total_read as f64 / total_denominator as f64) * 100.0
    } else {
        0.0
    };

    let per_agent: BTreeMap<String, f64> = per_role
        .into_iter()
        .map(|(role, (read, denom))| {
            let pct = if denom > 0 {
                (read as f64 / denom as f64) * 100.0
            } else {
                0.0
            };
            (role, pct)
        })
        .collect();

    (overall, per_agent)
}

/// Identify waste: agents where input >> output (ratio > 10:1).
fn calc_waste(
    stats: &BTreeMap<(String, String), AgentTokenStats>,
) -> Vec<(String, i64, i64, f64)> {
    let mut per_role_totals: BTreeMap<String, (i64, i64)> = BTreeMap::new();

    for ((role, _), s) in stats {
        let e = per_role_totals.entry(role.clone()).or_insert((0, 0));
        e.0 += s.input;
        e.1 += s.output;
    }

    let mut waste_agents: Vec<(String, i64, i64, f64)> = Vec::new();
    for (role, (input, output)) in &per_role_totals {
        let ratio = if *output > 0 {
            *input as f64 / *output as f64
        } else if *input > 0 {
            f64::INFINITY
        } else {
            0.0
        };
        if ratio > 10.0 {
            waste_agents.push((role.clone(), *input, *output, ratio));
        }
    }

    waste_agents.sort_by(|a, b| b.3.partial_cmp(&a.3).unwrap_or(std::cmp::Ordering::Equal));
    waste_agents
}

/// Count completed tasks and commits for ROI.
fn calc_roi(
    events: &[Value],
    cwd: &Path,
    phase_filter: Option<&str>,
    total_tokens: i64,
) -> (i64, i64, f64, f64) {
    let completed_tasks = events
        .iter()
        .filter(|e| {
            if e["event"].as_str() != Some("task_completed_confirmed") {
                return false;
            }
            if let Some(pf) = phase_filter {
                return matches_phase(e, pf);
            }
            true
        })
        .count() as i64;

    let commit_count = Command::new("git")
        .args(["log", "--oneline"])
        .current_dir(cwd)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .count() as i64
        })
        .unwrap_or(0);

    let tokens_per_task = if completed_tasks > 0 {
        total_tokens as f64 / completed_tasks as f64
    } else {
        0.0
    };

    let tokens_per_commit = if commit_count > 0 {
        total_tokens as f64 / commit_count as f64
    } else {
        0.0
    };

    (completed_tasks, commit_count, tokens_per_task, tokens_per_commit)
}

fn fmt_tok(v: i64) -> String {
    if v >= 1_000_000 {
        format!("{:.1}M", v as f64 / 1_000_000.0)
    } else if v >= 1_000 {
        format!("{:.1}K", v as f64 / 1_000.0)
    } else {
        format!("{}", v)
    }
}

fn progress_bar(pct: f64, width: i64) -> String {
    let pct_i = pct as i64;
    let filled = ((pct_i * width) / 100).max(0).min(width);
    let filled = if pct_i > 0 && filled == 0 { 1 } else { filled };
    let empty = width - filled;

    let color = if pct_i >= 80 {
        C_GREEN
    } else if pct_i >= 50 {
        C_YELLOW
    } else {
        C_RED
    };

    let bar_filled: String = (0..filled).map(|_| '\u{2593}').collect();
    let bar_empty: String = (0..empty).map(|_| '\u{2591}').collect();

    format!("{}{}{}{}", color, bar_filled, bar_empty, C_RESET)
}

fn render_branded(
    stats: &BTreeMap<(String, String), AgentTokenStats>,
    overall_cache: f64,
    per_agent_cache: &BTreeMap<String, f64>,
    waste_agents: &[(String, i64, i64, f64)],
    completed_tasks: i64,
    commit_count: i64,
    tokens_per_task: f64,
    tokens_per_commit: f64,
    total_tokens: i64,
) -> String {
    let mut out = String::new();

    // Header
    out.push_str(&format!(
        "\n{}{}[YOLO]{} Token Economics Dashboard\n",
        C_CYAN, C_BOLD, C_RESET
    ));
    out.push_str(&format!(
        "{}================================================================{}\n\n",
        C_DIM, C_RESET
    ));

    // Section 1: Per-Agent Token Spend
    out.push_str(&format!(
        "{}{}1. Per-Agent Token Spend{}\n",
        C_CYAN, C_BOLD, C_RESET
    ));
    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));
    out.push_str(&format!(
        "{}{:<14} {:<8} {:>10} {:>10} {:>12} {:>12} {:>10}{}\n",
        C_BOLD,
        "Role",
        "Phase",
        "Input",
        "Output",
        "Cache Read",
        "Cache Write",
        "Total",
        C_RESET
    ));
    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));

    let mut grand_total = AgentTokenStats::default();
    for ((role, phase), s) in stats {
        out.push_str(&format!(
            "{:<14} {:<8} {:>10} {:>10} {:>12} {:>12} {:>10}\n",
            role,
            phase,
            fmt_tok(s.input),
            fmt_tok(s.output),
            fmt_tok(s.cache_read),
            fmt_tok(s.cache_write),
            fmt_tok(s.total())
        ));
        grand_total.input += s.input;
        grand_total.output += s.output;
        grand_total.cache_read += s.cache_read;
        grand_total.cache_write += s.cache_write;
    }

    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));
    out.push_str(&format!(
        "{}{:<14} {:<8} {:>10} {:>10} {:>12} {:>12} {:>10}{}\n",
        C_BOLD,
        "TOTAL",
        "",
        fmt_tok(grand_total.input),
        fmt_tok(grand_total.output),
        fmt_tok(grand_total.cache_read),
        fmt_tok(grand_total.cache_write),
        fmt_tok(total_tokens),
        C_RESET
    ));
    out.push('\n');

    // Section 2: Cache Hit Rate
    out.push_str(&format!(
        "{}{}2. Cache Hit Rate{}\n",
        C_CYAN, C_BOLD, C_RESET
    ));
    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));
    let cache_color = if overall_cache >= 70.0 {
        C_GREEN
    } else if overall_cache >= 40.0 {
        C_YELLOW
    } else {
        C_RED
    };
    out.push_str(&format!(
        "Overall: {} {}{:.1}%{}\n",
        progress_bar(overall_cache, 20),
        cache_color,
        overall_cache,
        C_RESET
    ));
    for (role, pct) in per_agent_cache {
        let color = if *pct >= 70.0 {
            C_GREEN
        } else if *pct >= 40.0 {
            C_YELLOW
        } else {
            C_RED
        };
        out.push_str(&format!(
            "  {:<12} {} {}{:.1}%{}\n",
            role,
            progress_bar(*pct, 15),
            color,
            pct,
            C_RESET
        ));
    }
    out.push('\n');

    // Section 3: Waste Detection
    out.push_str(&format!(
        "{}{}3. Waste Detection{}\n",
        C_CYAN, C_BOLD, C_RESET
    ));
    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));
    if waste_agents.is_empty() {
        out.push_str(&format!(
            "{}No high-waste agents detected (threshold: >10:1 input/output ratio){}\n",
            C_GREEN, C_RESET
        ));
    } else {
        out.push_str(&format!(
            "{}{:<14} {:>10} {:>10} {:>10}{}\n",
            C_BOLD, "Agent", "Input", "Output", "Ratio", C_RESET
        ));
        for (role, input, output, ratio) in waste_agents {
            let flag = if *ratio > 50.0 {
                format!("{}HIGH{}", C_RED, C_RESET)
            } else {
                format!("{}WARN{}", C_YELLOW, C_RESET)
            };
            out.push_str(&format!(
                "{:<14} {:>10} {:>10} {:>8.1}x  {}\n",
                role,
                fmt_tok(*input),
                fmt_tok(*output),
                ratio,
                flag
            ));
        }
    }
    out.push('\n');

    // Section 4: ROI Metrics
    out.push_str(&format!(
        "{}{}4. ROI Metrics{}\n",
        C_CYAN, C_BOLD, C_RESET
    ));
    out.push_str(&format!(
        "{}----------------------------------------------------------------{}\n",
        C_DIM, C_RESET
    ));
    out.push_str(&format!("Tasks completed:     {}\n", completed_tasks));
    out.push_str(&format!("Commits:             {}\n", commit_count));
    out.push_str(&format!(
        "Tokens per task:     {}{}{}\n",
        C_BOLD,
        fmt_tok(tokens_per_task as i64),
        C_RESET
    ));
    out.push_str(&format!(
        "Tokens per commit:   {}{}{}\n",
        C_BOLD,
        fmt_tok(tokens_per_commit as i64),
        C_RESET
    ));
    out.push_str(&format!(
        "{}================================================================{}\n",
        C_DIM, C_RESET
    ));

    out
}

fn build_json_output(
    stats: &BTreeMap<(String, String), AgentTokenStats>,
    overall_cache: f64,
    per_agent_cache: &BTreeMap<String, f64>,
    waste_agents: &[(String, i64, i64, f64)],
    completed_tasks: i64,
    commit_count: i64,
    tokens_per_task: f64,
    tokens_per_commit: f64,
) -> String {
    let per_agent: Vec<Value> = stats
        .iter()
        .map(|((role, phase), s)| {
            json!({
                "role": role,
                "phase": phase,
                "input_tokens": s.input,
                "output_tokens": s.output,
                "cache_read_tokens": s.cache_read,
                "cache_write_tokens": s.cache_write,
                "total_tokens": s.total()
            })
        })
        .collect();

    let per_agent_cache_map: Value = per_agent_cache
        .iter()
        .map(|(k, v)| (k.clone(), json!((*v * 10.0).round() / 10.0)))
        .collect::<serde_json::Map<String, Value>>()
        .into();

    let waste_list: Vec<Value> = waste_agents
        .iter()
        .map(|(role, input, output, ratio)| {
            json!({
                "agent": role,
                "input_tokens": input,
                "output_tokens": output,
                "ratio": (*ratio * 10.0).round() / 10.0
            })
        })
        .collect();

    let result = json!({
        "per_agent": per_agent,
        "cache_hit_rate": {
            "overall": (overall_cache * 10.0).round() / 10.0,
            "per_agent": per_agent_cache_map
        },
        "waste": {
            "agents": waste_list
        },
        "roi": {
            "completed_tasks": completed_tasks,
            "commits": commit_count,
            "tokens_per_task": tokens_per_task.round() as i64,
            "tokens_per_commit": tokens_per_commit.round() as i64
        }
    });

    serde_json::to_string_pretty(&result).unwrap_or_else(|_| "{}".to_string())
}

pub fn execute(args: &[String], cwd: &Path, _db_path: &Path) -> Result<(String, i32), String> {
    let flags = parse_flags(args);

    let planning_dir = cwd.join(".yolo-planning");
    let metrics_file = planning_dir.join(".metrics").join("run-metrics.jsonl");
    let events_file = planning_dir.join(".events").join("event-log.jsonl");

    if !metrics_file.exists() && !events_file.exists() {
        let msg = format!(
            "{}{}[YOLO]{} No token economics data found.\n\
             Enable v3_metrics=true and v3_event_log=true, then run tasks to generate data.\n",
            C_CYAN, C_BOLD, C_RESET
        );
        return Ok((msg, 0));
    }

    let metrics = load_jsonl(&metrics_file);
    let events = load_jsonl(&events_file);

    let stats = build_agent_stats(&metrics, flags.phase_filter.as_deref());

    let (overall_cache, per_agent_cache) = calc_cache_hit_rates(&stats);
    let waste_agents = calc_waste(&stats);

    let total_tokens: i64 = stats.values().map(|s| s.total()).sum();
    let (completed_tasks, commit_count, tokens_per_task, tokens_per_commit) =
        calc_roi(&events, cwd, flags.phase_filter.as_deref(), total_tokens);

    if flags.json_output {
        let output = build_json_output(
            &stats,
            overall_cache,
            &per_agent_cache,
            &waste_agents,
            completed_tasks,
            commit_count,
            tokens_per_task,
            tokens_per_commit,
        );
        Ok((output, 0))
    } else {
        let output = render_branded(
            &stats,
            overall_cache,
            &per_agent_cache,
            &waste_agents,
            completed_tasks,
            commit_count,
            tokens_per_task,
            tokens_per_commit,
            total_tokens,
        );
        Ok((output, 0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn setup_test_dir() -> tempfile::TempDir {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir(&plan_dir).unwrap();
        fs::create_dir(plan_dir.join(".metrics")).unwrap();
        fs::create_dir(plan_dir.join(".events")).unwrap();
        dir
    }

    fn write_test_metrics(dir: &Path, content: &str) {
        let path = dir
            .join(".yolo-planning")
            .join(".metrics")
            .join("run-metrics.jsonl");
        fs::write(&path, content).unwrap();
    }

    fn write_test_events(dir: &Path, content: &str) {
        let path = dir
            .join(".yolo-planning")
            .join(".events")
            .join("event-log.jsonl");
        fs::write(&path, content).unwrap();
    }

    #[test]
    fn test_output_contains_all_sections() {
        let dir = setup_test_dir();
        let db_path = dir.path().join("test.db");

        write_test_metrics(
            dir.path(),
            r#"{"event":"agent_token_usage","phase":1,"data":{"role":"dev","input_tokens":5000,"output_tokens":2000,"cache_read_tokens":3000,"cache_write_tokens":500}}
{"event":"agent_token_usage","phase":1,"data":{"role":"architect","input_tokens":8000,"output_tokens":1000,"cache_read_tokens":4000,"cache_write_tokens":1000}}"#,
        );
        write_test_events(
            dir.path(),
            r#"{"event":"task_completed_confirmed","phase":1,"data":{"task_id":"1"}}"#,
        );

        let args: Vec<String> = vec!["yolo".into(), "report-tokens".into()];
        let (output, code) = execute(&args, dir.path(), &db_path).unwrap();

        assert_eq!(code, 0);
        assert!(
            output.contains("Per-Agent Token Spend"),
            "Missing Per-Agent section"
        );
        assert!(
            output.contains("Cache Hit Rate"),
            "Missing Cache Hit section"
        );
        assert!(
            output.contains("Waste Detection"),
            "Missing Waste section"
        );
        assert!(output.contains("ROI Metrics"), "Missing ROI section");
    }

    #[test]
    fn test_cache_hit_rate_calculation() {
        // 3000 read / (3000 read + 500 write + 500 input) = 3000/4000 = 75%
        let mut stats: BTreeMap<(String, String), AgentTokenStats> = BTreeMap::new();
        stats.insert(
            ("dev".to_string(), "1".to_string()),
            AgentTokenStats {
                input: 500,
                output: 200,
                cache_read: 3000,
                cache_write: 500,
            },
        );

        let (overall, per_agent) = calc_cache_hit_rates(&stats);
        assert!(
            (overall - 75.0).abs() < 0.1,
            "Expected ~75%, got {:.1}%",
            overall
        );
        assert!(
            (per_agent["dev"] - 75.0).abs() < 0.1,
            "Expected ~75% for dev, got {:.1}%",
            per_agent["dev"]
        );
    }

    #[test]
    fn test_waste_detection_flags_high_ratio() {
        let mut stats: BTreeMap<(String, String), AgentTokenStats> = BTreeMap::new();
        // dev: 5:1 ratio -- should NOT be flagged
        stats.insert(
            ("dev".to_string(), "1".to_string()),
            AgentTokenStats {
                input: 5000,
                output: 1000,
                cache_read: 0,
                cache_write: 0,
            },
        );
        // architect: 20:1 ratio -- SHOULD be flagged
        stats.insert(
            ("architect".to_string(), "1".to_string()),
            AgentTokenStats {
                input: 20000,
                output: 1000,
                cache_read: 0,
                cache_write: 0,
            },
        );

        let waste = calc_waste(&stats);
        assert_eq!(waste.len(), 1, "Only architect should be flagged");
        assert_eq!(waste[0].0, "architect");
        assert!((waste[0].3 - 20.0).abs() < 0.1, "Ratio should be ~20");
    }

    #[test]
    fn test_json_output_valid() {
        let dir = setup_test_dir();
        let db_path = dir.path().join("test.db");

        write_test_metrics(
            dir.path(),
            r#"{"event":"agent_token_usage","phase":1,"data":{"role":"dev","input_tokens":5000,"output_tokens":2000,"cache_read_tokens":3000,"cache_write_tokens":500}}"#,
        );
        write_test_events(
            dir.path(),
            r#"{"event":"task_completed_confirmed","phase":1,"data":{"task_id":"1"}}"#,
        );

        let args: Vec<String> = vec!["yolo".into(), "report-tokens".into(), "--json".into()];
        let (output, code) = execute(&args, dir.path(), &db_path).unwrap();

        assert_eq!(code, 0);
        let parsed: Value = serde_json::from_str(&output).expect("Output should be valid JSON");
        assert!(parsed.get("per_agent").is_some(), "Missing per_agent key");
        assert!(
            parsed.get("cache_hit_rate").is_some(),
            "Missing cache_hit_rate key"
        );
        assert!(parsed.get("waste").is_some(), "Missing waste key");
        assert!(parsed.get("roi").is_some(), "Missing roi key");
    }

    #[test]
    fn test_phase_filter() {
        let dir = setup_test_dir();
        let db_path = dir.path().join("test.db");

        write_test_metrics(
            dir.path(),
            r#"{"event":"agent_token_usage","phase":1,"data":{"role":"dev","input_tokens":5000,"output_tokens":2000,"cache_read_tokens":0,"cache_write_tokens":0}}
{"event":"agent_token_usage","phase":2,"data":{"role":"dev","input_tokens":8000,"output_tokens":3000,"cache_read_tokens":0,"cache_write_tokens":0}}"#,
        );
        write_test_events(dir.path(), "");

        let args: Vec<String> = vec![
            "yolo".into(),
            "report-tokens".into(),
            "--phase=1".into(),
            "--json".into(),
        ];
        let (output, _) = execute(&args, dir.path(), &db_path).unwrap();
        let parsed: Value = serde_json::from_str(&output).unwrap();
        let agents = parsed["per_agent"].as_array().unwrap();

        assert_eq!(agents.len(), 1, "Should only contain phase 1 data");
        assert_eq!(agents[0]["phase"], "1");
        assert_eq!(agents[0]["input_tokens"], 5000);
    }

    #[test]
    fn test_no_data_message() {
        let dir = tempdir().unwrap();
        let db_path = dir.path().join("test.db");
        let args: Vec<String> = vec!["yolo".into(), "report-tokens".into()];
        let (output, code) = execute(&args, dir.path(), &db_path).unwrap();
        assert_eq!(code, 0);
        assert!(output.contains("No token economics data found"));
    }

    #[test]
    fn test_zero_division_safety_cache_hit_rate() {
        // When no tokens recorded, cache hit rate should be 0% not NaN/panic
        let stats: BTreeMap<(String, String), AgentTokenStats> = BTreeMap::new();
        let (overall, per_agent) = calc_cache_hit_rates(&stats);
        assert_eq!(overall, 0.0, "Empty stats should yield 0% cache hit rate");
        assert!(per_agent.is_empty(), "No agents means no per-agent rates");

        // Agent with all zeros
        let mut stats2: BTreeMap<(String, String), AgentTokenStats> = BTreeMap::new();
        stats2.insert(
            ("dev".to_string(), "1".to_string()),
            AgentTokenStats {
                input: 0,
                output: 0,
                cache_read: 0,
                cache_write: 0,
            },
        );
        let (overall2, per_agent2) = calc_cache_hit_rates(&stats2);
        assert_eq!(overall2, 0.0, "All-zero tokens should yield 0%");
        assert_eq!(per_agent2["dev"], 0.0, "Dev with zero tokens should be 0%");
    }

    #[test]
    fn test_missing_fields_default_to_zero() {
        // JSONL event with partial data (no cache_write)
        let metrics = vec![
            serde_json::from_str::<Value>(
                r#"{"event":"agent_token_usage","phase":1,"data":{"role":"dev","input_tokens":1000,"output_tokens":200}}"#,
            )
            .unwrap(),
        ];
        let stats = build_agent_stats(&metrics, None);
        let s = &stats[&("dev".to_string(), "1".to_string())];
        assert_eq!(s.input, 1000);
        assert_eq!(s.output, 200);
        assert_eq!(s.cache_read, 0, "Missing cache_read should default to 0");
        assert_eq!(s.cache_write, 0, "Missing cache_write should default to 0");

        // JSONL event with no data fields at all (only role)
        let metrics2 = vec![
            serde_json::from_str::<Value>(
                r#"{"event":"agent_token_usage","phase":1,"data":{"role":"empty-agent"}}"#,
            )
            .unwrap(),
        ];
        let stats2 = build_agent_stats(&metrics2, None);
        let s2 = &stats2[&("empty-agent".to_string(), "1".to_string())];
        assert_eq!(s2.input, 0);
        assert_eq!(s2.output, 0);
        assert_eq!(s2.cache_read, 0);
        assert_eq!(s2.cache_write, 0);
    }

    #[test]
    fn test_large_dataset_aggregation() {
        // 100+ events across 5 phases, verify aggregation completes and totals are correct
        let mut lines = Vec::new();
        for phase in 1..=5 {
            for i in 0..20 {
                let role = match i % 4 {
                    0 => "dev",
                    1 => "architect",
                    2 => "qa",
                    _ => "lead",
                };
                lines.push(format!(
                    r#"{{"event":"agent_token_usage","phase":{},"data":{{"role":"{}","input_tokens":100,"output_tokens":50,"cache_read_tokens":30,"cache_write_tokens":10}}}}"#,
                    phase, role
                ));
            }
        }
        // 100 events total: 20 per phase, 5 per role per phase
        assert_eq!(lines.len(), 100);

        let metrics: Vec<Value> = lines
            .iter()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect();

        let stats = build_agent_stats(&metrics, None);
        // 5 phases x 4 roles = 20 unique (role, phase) pairs
        assert_eq!(stats.len(), 20, "Should have 20 unique (role, phase) pairs");

        // Each (role, phase) pair has 5 events with 100 input each = 500
        for s in stats.values() {
            assert_eq!(s.input, 500, "Each bucket should have 5 * 100 = 500 input");
            assert_eq!(s.output, 250, "Each bucket should have 5 * 50 = 250 output");
            assert_eq!(s.cache_read, 150, "Each bucket should have 5 * 30 = 150 cache_read");
            assert_eq!(s.cache_write, 50, "Each bucket should have 5 * 10 = 50 cache_write");
        }

        // Verify total across all
        let total: i64 = stats.values().map(|s| s.total()).sum();
        // 100 events * (100+50+30+10) = 100 * 190 = 19000
        assert_eq!(total, 19000, "Grand total should be 19000");
    }

    #[test]
    fn test_roi_with_zero_tasks() {
        // With no task_completed_confirmed events, tokens_per_task should be 0 (not panic)
        let events: Vec<Value> = vec![
            serde_json::from_str(r#"{"event":"phase_start","phase":1}"#).unwrap(),
        ];
        let dir = tempdir().unwrap();
        let (_tasks, _commits, tokens_per_task, _tokens_per_commit) =
            calc_roi(&events, dir.path(), None, 50000);
        assert_eq!(tokens_per_task, 0.0, "Zero tasks should yield 0 tokens/task, not panic");
    }
}
