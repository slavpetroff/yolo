use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Duration;
use serde_json::Value;

// --- ANSI color constants ---
const C_RESET: &str = "\x1b[0m";
const C_DIM: &str = "\x1b[2m";
const C_BOLD: &str = "\x1b[1m";
const C_CYAN: &str = "\x1b[36m";
const C_GREEN: &str = "\x1b[32m";
const C_YELLOW: &str = "\x1b[33m";
const C_RED: &str = "\x1b[31m";

/// Main entry point: takes raw stdin JSON from Claude Code, returns 4-line statusline.
pub fn render_statusline(stdin_json: &str) -> Result<String, String> {
    let input: Value = serde_json::from_str(stdin_json).unwrap_or(Value::Object(Default::default()));

    // --- Parse stdin JSON fields ---
    let pct = input.pointer("/context_window/used_percentage")
        .and_then(|v| v.as_f64()).unwrap_or(0.0) as i64;
    let _rem = input.pointer("/context_window/remaining_percentage")
        .and_then(|v| v.as_f64()).unwrap_or(100.0) as i64;
    let in_tok = input.pointer("/context_window/current_usage/input_tokens")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let out_tok = input.pointer("/context_window/current_usage/output_tokens")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let cache_w = input.pointer("/context_window/current_usage/cache_creation_input_tokens")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let cache_r = input.pointer("/context_window/current_usage/cache_read_input_tokens")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let ctx_size = input.pointer("/context_window/context_window_size")
        .and_then(|v| v.as_i64()).unwrap_or(200_000);

    let cost = input.pointer("/cost/total_cost_usd")
        .and_then(|v| v.as_f64()).unwrap_or(0.0);
    let dur_ms = input.pointer("/cost/total_duration_ms")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let api_ms = input.pointer("/cost/total_api_duration_ms")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let added = input.pointer("/cost/total_lines_added")
        .and_then(|v| v.as_i64()).unwrap_or(0);
    let removed = input.pointer("/cost/total_lines_removed")
        .and_then(|v| v.as_i64()).unwrap_or(0);

    let model = input.pointer("/model/display_name")
        .and_then(|v| v.as_str()).unwrap_or("Claude");
    let cc_version = input.get("version")
        .and_then(|v| v.as_str()).unwrap_or("?");

    // --- Token calculations ---
    let ctx_used = in_tok + cache_w + cache_r;
    let total_input = in_tok + cache_w + cache_r;
    let cache_hit_pct = if total_input > 0 { cache_r * 100 / total_input } else { 0 };

    // --- Cache infrastructure ---
    let cache_prefix = build_cache_prefix();

    // --- Fast cache (5s TTL): state, config, git, execution ---
    let fast = read_fast_cache(&cache_prefix);

    // --- Slow cache (60s TTL): OAuth usage, update check ---
    let slow = read_slow_cache(&cache_prefix);

    // --- L1: [YOLO] Phase/Plans/Effort/Model + git info ---
    let mut l1 = format!("{}{}{}", C_CYAN, C_BOLD, "[YOLO]");
    l1.push_str(C_RESET);

    if fast.exec_status == "running" && fast.exec_total > 0 {
        let exec_pct = fast.exec_done * 100 / fast.exec_total;
        l1.push_str(&format!(" Build: {} {}/{} plans",
            progress_bar(exec_pct, 8), fast.exec_done, fast.exec_total));
        if fast.exec_twaves > 1 {
            l1.push_str(&format!(" {}|{} Wave {}/{}",
                C_DIM, C_RESET, fast.exec_wave, fast.exec_twaves));
        }
        if !fast.exec_current.is_empty() {
            l1.push_str(&format!(" {}|{} {}{}{}", C_DIM, C_RESET, C_CYAN, fast.exec_current, C_RESET));
        }
    } else if fast.has_planning_dir {
        if fast.total_phases > 0 {
            l1.push_str(&format!(" Phase {}/{}", fast.phase, fast.total_phases));
        } else {
            l1.push_str(&format!(" Phase {}", fast.phase));
        }
        if fast.plans_total > 0 {
            l1.push_str(&format!(" {}|{} Plans: {}/{}",
                C_DIM, C_RESET, fast.plans_done, fast.plans_total));
        }
        l1.push_str(&format!(" {}|{} Effort: {} {}|{} Model: {}",
            C_DIM, C_RESET, fast.effort,
            C_DIM, C_RESET, fast.model_profile));
    } else {
        l1.push_str(&format!(" {}no project{}", C_DIM, C_RESET));
    }

    // Git info
    if !fast.branch.is_empty() {
        l1.push_str(&format!(" {}|{} {}:{}", C_DIM, C_RESET, fast.repo_name, fast.branch));
        let mut git_ind = String::new();
        if fast.staged > 0 {
            git_ind.push_str(&format!("{}+{}{}", C_GREEN, fast.staged, C_RESET));
        }
        if fast.modified > 0 {
            git_ind.push_str(&format!("{}~{}{}", C_YELLOW, fast.modified, C_RESET));
        }
        if !git_ind.is_empty() {
            l1.push_str(&format!(" {}", git_ind));
        }
    }
    if added > 0 || removed > 0 {
        l1.push_str(&format!(" {}Diff:{} {}+{}{} {}-{}{}",
            C_DIM, C_RESET,
            C_GREEN, added, C_RESET,
            C_RED, removed, C_RESET));
    }

    // --- L2: Context window ---
    let ctx_color = if pct >= 90 { C_RED } else if pct >= 70 { C_YELLOW } else { C_GREEN };
    let ctx_bar = progress_bar(pct, 10);
    let cache_color = if cache_hit_pct >= 70 { C_GREEN } else if cache_hit_pct >= 40 { C_YELLOW } else { C_RED };

    let l2 = format!(
        "Context: {}{}{} {}{}%{} {}/{} {}|{} Tokens: {} in  {} out {}|{} Prompt Cache: {}{}% hit{} {} write {} read",
        ctx_color, ctx_bar, C_RESET,
        ctx_color, pct, C_RESET,
        fmt_tok(ctx_used), fmt_tok(ctx_size),
        C_DIM, C_RESET,
        fmt_tok(in_tok), fmt_tok(out_tok),
        C_DIM, C_RESET,
        cache_color, cache_hit_pct, C_RESET,
        fmt_tok(cache_w), fmt_tok(cache_r),
    );

    // --- L3: OAuth usage limits ---
    let l3 = if slow.fetch_ok == "ok" {
        let five_rem = countdown(slow.five_epoch);
        let week_rem = countdown(slow.week_epoch);

        let mut line = format!("Session: {} {}%", progress_bar(slow.five_pct, 10), slow.five_pct);
        if !five_rem.is_empty() {
            line.push_str(&format!(" {}", five_rem));
        }
        line.push_str(&format!(" {}|{} Weekly: {} {}%",
            C_DIM, C_RESET, progress_bar(slow.week_pct, 10), slow.week_pct));
        if !week_rem.is_empty() {
            line.push_str(&format!(" {}", week_rem));
        }
        line
    } else if slow.fetch_ok == "auth" {
        format!("{}Limits: auth expired (run /login){}", C_DIM, C_RESET)
    } else if slow.fetch_ok == "fail" {
        format!("{}Limits: fetch failed (retry in 60s){}", C_DIM, C_RESET)
    } else {
        format!("{}Limits: N/A (using API key){}", C_DIM, C_RESET)
    };

    // --- L4: Model / Time / Versions ---
    let dur_fmt = fmt_dur(dur_ms);
    let api_dur_fmt = fmt_dur(api_ms);
    let cost_fmt = fmt_cost(cost);
    let yolo_ver = read_yolo_version();

    let mut l4 = format!("Model: {}{}{} {}|{} Cost: {} {}|{} Time: {} (API: {})",
        C_DIM, model, C_RESET,
        C_DIM, C_RESET,
        cost_fmt,
        C_DIM, C_RESET,
        dur_fmt, api_dur_fmt);

    if let Some(ref remote) = slow.update_avail {
        l4.push_str(&format!(" {}|{} {}{}YOLO {} -> {}{}",
            C_DIM, C_RESET,
            C_YELLOW, C_BOLD, yolo_ver, remote, C_RESET));
    } else {
        l4.push_str(&format!(" {}|{} {}YOLO {}{}", C_DIM, C_RESET, C_DIM, yolo_ver, C_RESET));
    }
    l4.push_str(&format!(" {}|{} {}CC {}{}", C_DIM, C_RESET, C_DIM, cc_version, C_RESET));

    Ok(format!("{}\n{}\n{}\n{}\n", l1, l2, l3, l4))
}

// === Helper structs ===

struct FastCache {
    phase: String,
    total_phases: i64,
    effort: String,
    model_profile: String,
    branch: String,
    repo_name: String,
    plans_done: i64,
    plans_total: i64,
    staged: i64,
    modified: i64,
    has_planning_dir: bool,
    exec_status: String,
    exec_wave: i64,
    exec_twaves: i64,
    exec_done: i64,
    exec_total: i64,
    exec_current: String,
}

struct SlowCache {
    five_pct: i64,
    five_epoch: i64,
    week_pct: i64,
    week_epoch: i64,
    fetch_ok: String,
    update_avail: Option<String>,
}

// === Cache prefix ===

fn build_cache_prefix() -> String {
    let uid = unsafe { libc::getuid() };
    let ver = read_yolo_version();

    let repo_root = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| if o.status.success() {
            Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
        } else { None })
        .unwrap_or_else(|| {
            std::env::current_dir()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| ".".to_string())
        });

    let repo_hash = simple_hash(&repo_root);
    format!("/tmp/yolo-{}-{}-{}", ver, uid, repo_hash)
}

fn simple_hash(s: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    s.hash(&mut hasher);
    format!("{:08x}", hasher.finish() & 0xFFFF_FFFF)
}

fn read_yolo_version() -> String {
    // Try VERSION file relative to binary location first
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            // Binary is typically in target/release or target/debug — go up to repo root
            for ancestor in [parent, parent.parent().unwrap_or(parent)] {
                let vp = ancestor.join("VERSION");
                if let Ok(v) = fs::read_to_string(&vp) {
                    let trimmed = v.trim().to_string();
                    if !trimmed.is_empty() {
                        return trimmed;
                    }
                }
            }
        }
    }
    // Try cwd-based VERSION
    if let Ok(v) = fs::read_to_string("VERSION") {
        let trimmed = v.trim().to_string();
        if !trimmed.is_empty() {
            return trimmed;
        }
    }
    "?".to_string()
}

// === Cache freshness check ===

fn cache_fresh(path: &str, ttl_secs: u64) -> bool {
    if let Ok(meta) = fs::metadata(path) {
        if let Ok(modified) = meta.modified() {
            if let Ok(elapsed) = modified.elapsed() {
                return elapsed < Duration::from_secs(ttl_secs);
            }
        }
    }
    false
}

// === Fast cache (5s TTL) ===

fn read_fast_cache(prefix: &str) -> FastCache {
    let cache_file = format!("{}-fast", prefix);

    if !cache_fresh(&cache_file, 5) {
        let data = compute_fast_cache();
        let serialized = format!("{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
            data.phase, data.total_phases, data.effort, data.model_profile,
            data.branch, data.plans_done, data.plans_total, data.staged, data.modified,
            if data.has_planning_dir { 1 } else { 0 },
            data.exec_status, data.exec_wave, data.exec_twaves,
            data.exec_done, data.exec_total, data.exec_current);
        // Also stash repo_name
        let full = format!("{}|{}", serialized, data.repo_name);
        let _ = fs::write(&cache_file, &full);
        return data;
    }

    // Read cached
    if let Ok(content) = fs::read_to_string(&cache_file) {
        let parts: Vec<&str> = content.trim().split('|').collect();
        if parts.len() >= 16 {
            return FastCache {
                phase: parts[0].to_string(),
                total_phases: parts[1].parse().unwrap_or(0),
                effort: parts[2].to_string(),
                model_profile: parts[3].to_string(),
                branch: parts[4].to_string(),
                plans_done: parts[5].parse().unwrap_or(0),
                plans_total: parts[6].parse().unwrap_or(0),
                staged: parts[7].parse().unwrap_or(0),
                modified: parts[8].parse().unwrap_or(0),
                has_planning_dir: parts[9] == "1",
                exec_status: parts[10].to_string(),
                exec_wave: parts[11].parse().unwrap_or(0),
                exec_twaves: parts[12].parse().unwrap_or(0),
                exec_done: parts[13].parse().unwrap_or(0),
                exec_total: parts[14].parse().unwrap_or(0),
                exec_current: parts[15].to_string(),
                repo_name: parts.get(16).unwrap_or(&"").to_string(),
            };
        }
    }

    compute_fast_cache()
}

fn compute_fast_cache() -> FastCache {
    let mut fc = FastCache {
        phase: "?".to_string(),
        total_phases: 0,
        effort: "balanced".to_string(),
        model_profile: "quality".to_string(),
        branch: String::new(),
        repo_name: String::new(),
        plans_done: 0,
        plans_total: 0,
        staged: 0,
        modified: 0,
        has_planning_dir: false,
        exec_status: String::new(),
        exec_wave: 0,
        exec_twaves: 0,
        exec_done: 0,
        exec_total: 0,
        exec_current: String::new(),
    };

    let planning_dir = Path::new(".yolo-planning");
    fc.has_planning_dir = planning_dir.is_dir();

    // Parse STATE.md (Markdown bold format)
    let state_path = planning_dir.join("STATE.md");
    if let Ok(content) = fs::read_to_string(&state_path) {
        fc.phase = parse_state_field(&content, "Current Phase");
        let progress_str = parse_state_field(&content, "Progress");
        // Extract phase numbers from "Phase X of Y" or just "Phase X"
        if let Some(num) = extract_first_number(&fc.phase) {
            let phase_num = num.to_string();
            fc.phase = phase_num;
        }
        // Count total phases from phase directories
        if let Ok(entries) = fs::read_dir(planning_dir.join("phases")) {
            let mut max_phase = 0i64;
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if entry.path().is_dir() {
                    if let Some(n) = extract_first_number(&name) {
                        if n > max_phase { max_phase = n; }
                    }
                }
            }
            fc.total_phases = max_phase;
        }
        let _ = progress_str; // progress is shown via exec state or plan counts
    }

    // Parse config.json
    let config_path = planning_dir.join("config.json");
    if let Ok(content) = fs::read_to_string(&config_path) {
        if let Ok(cfg) = serde_json::from_str::<Value>(&content) {
            if let Some(e) = cfg.get("effort").and_then(|v| v.as_str()) {
                fc.effort = e.to_string();
            }
            if let Some(m) = cfg.get("model_profile").and_then(|v| v.as_str()) {
                fc.model_profile = m.to_string();
            }
        }
    }

    // Git info
    if let Ok(out) = Command::new("git").args(["branch", "--show-current"]).output() {
        if out.status.success() {
            fc.branch = String::from_utf8_lossy(&out.stdout).trim().to_string();
        }
    }
    // Repo name from remote or directory
    if let Ok(out) = Command::new("git").args(["remote", "get-url", "origin"]).output() {
        if out.status.success() {
            let url = String::from_utf8_lossy(&out.stdout).trim().to_string();
            fc.repo_name = extract_repo_name(&url);
        }
    }
    if fc.repo_name.is_empty() {
        fc.repo_name = std::env::current_dir()
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            .unwrap_or_else(|| "unknown".to_string());
    }

    // Staged/modified counts
    if let Ok(out) = Command::new("git").args(["diff", "--cached", "--numstat"]).output() {
        if out.status.success() {
            fc.staged = String::from_utf8_lossy(&out.stdout).lines().count() as i64;
        }
    }
    if let Ok(out) = Command::new("git").args(["diff", "--numstat"]).output() {
        if out.status.success() {
            fc.modified = String::from_utf8_lossy(&out.stdout).lines().count() as i64;
        }
    }

    // Plan counts
    if let Ok(entries) = fs::read_dir(planning_dir.join("phases")) {
        for entry in entries.flatten() {
            if entry.path().is_dir() {
                if let Ok(files) = fs::read_dir(entry.path()) {
                    for f in files.flatten() {
                        let name = f.file_name().to_string_lossy().to_string();
                        if name.ends_with("-PLAN.md") || name.ends_with(".plan.jsonl") {
                            fc.plans_total += 1;
                        }
                        if name.ends_with("-SUMMARY.md") {
                            fc.plans_done += 1;
                        }
                    }
                }
            }
        }
    }

    // Execution state
    let exec_path = planning_dir.join(".execution-state.json");
    if let Ok(content) = fs::read_to_string(&exec_path) {
        if let Ok(exec) = serde_json::from_str::<Value>(&content) {
            fc.exec_status = exec.get("status").and_then(|v| v.as_str()).unwrap_or("").to_string();
            fc.exec_wave = exec.get("wave").and_then(|v| v.as_i64()).unwrap_or(0);
            fc.exec_twaves = exec.get("total_waves").and_then(|v| v.as_i64()).unwrap_or(0);

            if let Some(plans) = exec.get("plans").and_then(|v| v.as_array()) {
                fc.exec_total = plans.len() as i64;
                fc.exec_done = plans.iter()
                    .filter(|p| p.get("status").and_then(|s| s.as_str()) == Some("complete"))
                    .count() as i64;
                fc.exec_current = plans.iter()
                    .find(|p| p.get("status").and_then(|s| s.as_str()) == Some("running"))
                    .and_then(|p| p.get("title").and_then(|t| t.as_str()))
                    .unwrap_or("")
                    .to_string();
            }
        }
    }

    fc
}

// === Slow cache (60s TTL) ===

fn read_slow_cache(prefix: &str) -> SlowCache {
    let cache_file = format!("{}-slow", prefix);

    if !cache_fresh(&cache_file, 60) {
        let data = compute_slow_cache();
        let update_str = data.update_avail.as_deref().unwrap_or("");
        let serialized = format!("{}|{}|{}|{}|{}|{}",
            data.five_pct, data.five_epoch, data.week_pct, data.week_epoch,
            data.fetch_ok, update_str);
        let _ = fs::write(&cache_file, &serialized);
        return data;
    }

    if let Ok(content) = fs::read_to_string(&cache_file) {
        let parts: Vec<&str> = content.trim().split('|').collect();
        if parts.len() >= 5 {
            return SlowCache {
                five_pct: parts[0].parse().unwrap_or(0),
                five_epoch: parts[1].parse().unwrap_or(0),
                week_pct: parts[2].parse().unwrap_or(0),
                week_epoch: parts[3].parse().unwrap_or(0),
                fetch_ok: parts[4].to_string(),
                update_avail: parts.get(5)
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string()),
            };
        }
    }

    compute_slow_cache()
}

fn compute_slow_cache() -> SlowCache {
    let mut sc = SlowCache {
        five_pct: 0,
        five_epoch: 0,
        week_pct: 0,
        week_epoch: 0,
        fetch_ok: "noauth".to_string(),
        update_avail: None,
    };

    // --- OAuth credential discovery ---
    let oauth_token = get_oauth_token();

    if let Some(token) = oauth_token {
        // Call /api/oauth/usage with curl
        let result = Command::new("curl")
            .args([
                "-s", "--max-time", "3",
                "-H", &format!("Authorization: Bearer {}", token),
                "-H", "anthropic-beta: oauth-2025-04-20",
                "https://api.anthropic.com/api/oauth/usage",
            ])
            .output();

        if let Ok(out) = result {
            if out.status.success() {
                let body = String::from_utf8_lossy(&out.stdout);
                if let Ok(usage) = serde_json::from_str::<Value>(&body) {
                    if usage.get("five_hour").is_some() {
                        sc.five_pct = usage.pointer("/five_hour/utilization")
                            .and_then(|v| v.as_f64()).unwrap_or(0.0) as i64;
                        sc.week_pct = usage.pointer("/seven_day/utilization")
                            .and_then(|v| v.as_f64()).unwrap_or(0.0) as i64;
                        // Parse reset epochs (best effort)
                        sc.five_epoch = parse_iso_epoch(
                            usage.pointer("/five_hour/resets_at")
                                .and_then(|v| v.as_str()).unwrap_or(""));
                        sc.week_epoch = parse_iso_epoch(
                            usage.pointer("/seven_day/resets_at")
                                .and_then(|v| v.as_str()).unwrap_or(""));
                        sc.fetch_ok = "ok".to_string();
                    } else {
                        sc.fetch_ok = "fail".to_string();
                    }
                } else {
                    sc.fetch_ok = "fail".to_string();
                }
            } else {
                sc.fetch_ok = "fail".to_string();
            }
        }
    }

    // --- Update check ---
    let remote_ver_result = Command::new("curl")
        .args([
            "-sf", "--max-time", "3",
            "https://raw.githubusercontent.com/slavpetroff/yolo/main/VERSION",
        ])
        .output();

    if let Ok(out) = remote_ver_result {
        if out.status.success() {
            let remote_ver = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let local_ver = read_yolo_version();
            if !remote_ver.is_empty() && !local_ver.is_empty()
                && remote_ver != local_ver && remote_ver != "?"
            {
                // Simple version comparison: if remote is lexicographically greater
                if version_is_newer(&remote_ver, &local_ver) {
                    sc.update_avail = Some(remote_ver);
                }
            }
        }
    }

    sc
}

fn get_oauth_token() -> Option<String> {
    // Priority 1: env var
    if let Ok(token) = std::env::var("YOLO_OAUTH_TOKEN") {
        if !token.is_empty() {
            return Some(token);
        }
    }

    // Priority 2: macOS Keychain
    if cfg!(target_os = "macos") {
        if let Ok(out) = Command::new("security")
            .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
            .output()
        {
            if out.status.success() {
                let cred_json = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if let Ok(cred) = serde_json::from_str::<Value>(&cred_json) {
                    if let Some(token) = cred.pointer("/claudeAiOauth/accessToken")
                        .and_then(|v| v.as_str())
                    {
                        if !token.is_empty() {
                            return Some(token.to_string());
                        }
                    }
                }
            }
        }
    }

    // Priority 3: credential files
    let home = std::env::var("HOME").unwrap_or_default();
    let claude_dir = std::env::var("CLAUDE_CONFIG_DIR")
        .unwrap_or_else(|_| format!("{}/.claude", home));

    for name in &[".credentials.json", "credentials.json"] {
        let path = format!("{}/{}", claude_dir, name);
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(cred) = serde_json::from_str::<Value>(&content) {
                if let Some(token) = cred.pointer("/claudeAiOauth/accessToken")
                    .and_then(|v| v.as_str())
                {
                    if !token.is_empty() {
                        return Some(token.to_string());
                    }
                }
            }
        }
    }

    None
}

// === Format helpers ===

fn fmt_tok(v: i64) -> String {
    if v >= 1_000_000 {
        let d = v / 1_000_000;
        let r = ((v % 1_000_000) + 50_000) / 100_000;
        if r >= 10 {
            format!("{}M", d + 1)
        } else {
            format!("{}.{}M", d, r)
        }
    } else if v >= 1_000 {
        let d = v / 1_000;
        let r = ((v % 1_000) + 50) / 100;
        if r >= 10 {
            format!("{}K", d + 1)
        } else {
            format!("{}.{}K", d, r)
        }
    } else {
        format!("{}", v)
    }
}

fn fmt_dur(ms: i64) -> String {
    let s = ms / 1000;
    if s >= 3600 {
        format!("{}h {}m", s / 3600, (s % 3600) / 60)
    } else if s >= 60 {
        format!("{}m {}s", s / 60, s % 60)
    } else {
        format!("{}s", s)
    }
}

fn fmt_cost(cost: f64) -> String {
    if cost >= 100.0 {
        format!("${:.0}", cost)
    } else if cost >= 10.0 {
        format!("${:.1}", cost)
    } else {
        format!("${:.2}", cost)
    }
}

fn progress_bar(pct: i64, width: i64) -> String {
    let filled = ((pct * width) / 100).max(0).min(width);
    let filled = if pct > 0 && filled == 0 { 1 } else { filled };
    let empty = width - filled;

    let color = if pct >= 80 { C_RED } else if pct >= 50 { C_YELLOW } else { C_GREEN };

    let bar_filled: String = (0..filled).map(|_| '\u{2593}').collect(); // dark shade
    let bar_empty: String = (0..empty).map(|_| '\u{2591}').collect();   // light shade

    format!("{}{}{}{}", color, bar_filled, bar_empty, C_RESET)
}

fn countdown(epoch: i64) -> String {
    if epoch <= 0 {
        return String::new();
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let diff = epoch - now;
    if diff <= 0 {
        return "now".to_string();
    }
    if diff >= 86400 {
        format!("~{}d {}h", diff / 86400, (diff % 86400) / 3600)
    } else {
        format!("~{}h{}m", diff / 3600, (diff % 3600) / 60)
    }
}

fn parse_state_field(content: &str, field: &str) -> String {
    // Matches **Field:** value  (Markdown bold format)
    let pattern = format!("**{}:**", field);
    for line in content.lines() {
        if let Some(idx) = line.find(&pattern) {
            let after = &line[idx + pattern.len()..];
            return after.trim().to_string();
        }
    }
    String::new()
}

fn extract_first_number(s: &str) -> Option<i64> {
    let mut num = String::new();
    let mut found = false;
    for c in s.chars() {
        if c.is_ascii_digit() {
            num.push(c);
            found = true;
        } else if found {
            break;
        }
    }
    if found { num.parse().ok() } else { None }
}

fn extract_repo_name(url: &str) -> String {
    // Handle git@github.com:user/repo.git or https://github.com/user/repo.git
    let s = url.trim_end_matches(".git");
    s.rsplit('/').next()
        .or_else(|| s.rsplit(':').next())
        .unwrap_or("")
        .to_string()
}

fn parse_iso_epoch(iso: &str) -> i64 {
    if iso.is_empty() {
        return 0;
    }
    // Best-effort ISO 8601 parsing: 2024-01-15T10:30:00Z
    // Use chrono if available, otherwise fall back to simple parsing
    chrono::DateTime::parse_from_rfc3339(iso)
        .map(|dt| dt.timestamp())
        .unwrap_or(0)
}

fn version_is_newer(remote: &str, local: &str) -> bool {
    let parse = |v: &str| -> Vec<u64> {
        v.split('.').filter_map(|p| p.parse().ok()).collect()
    };
    let r = parse(remote);
    let l = parse(local);
    for i in 0..r.len().max(l.len()) {
        let rv = r.get(i).copied().unwrap_or(0);
        let lv = l.get(i).copied().unwrap_or(0);
        if rv > lv { return true; }
        if rv < lv { return false; }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_render_statusline_empty_stdin() {
        let out = render_statusline("{}").unwrap();
        let lines: Vec<&str> = out.trim().lines().collect();
        assert_eq!(lines.len(), 4, "Should produce exactly 4 lines");
        assert!(out.contains("[YOLO]"), "L1 should contain [YOLO]");
        assert!(out.contains("Context:"), "L2 should contain Context:");
        assert!(out.contains("Model:"), "L4 should contain Model:");
    }

    #[test]
    fn test_render_statusline_with_context() {
        let input = r#"{
            "context_window": {
                "used_percentage": 45,
                "remaining_percentage": 55,
                "current_usage": {
                    "input_tokens": 50000,
                    "output_tokens": 10000,
                    "cache_creation_input_tokens": 5000,
                    "cache_read_input_tokens": 80000
                },
                "context_window_size": 200000
            }
        }"#;
        let out = render_statusline(input).unwrap();
        assert!(out.contains("45%"), "Should show 45% context usage");
        assert!(out.contains("200.0K"), "Should show 200K context size");
    }

    #[test]
    fn test_render_statusline_with_model() {
        let input = r#"{"model": {"display_name": "Claude Opus 4"}}"#;
        let out = render_statusline(input).unwrap();
        assert!(out.contains("Claude Opus 4"), "Should show model display name");
        assert!(!out.contains("claude-3-5-sonnet"), "Should NOT contain hardcoded model");
    }

    #[test]
    fn test_render_statusline_with_cost() {
        let input = r#"{
            "cost": {
                "total_cost_usd": 1.23,
                "total_duration_ms": 125000,
                "total_api_duration_ms": 60000,
                "total_lines_added": 150,
                "total_lines_removed": 30
            }
        }"#;
        let out = render_statusline(input).unwrap();
        assert!(out.contains("$1.23"), "Should show cost");
        assert!(out.contains("2m 5s"), "Should show 2m 5s duration");
        assert!(out.contains("+150"), "Should show lines added");
        assert!(out.contains("-30"), "Should show lines removed");
    }

    #[test]
    fn test_fast_cache_state_parsing() {
        let content = "# State\n\n**Current Phase:** Phase 2\n**Status:** In Progress\n**Progress:** 50%\n";
        let phase = parse_state_field(content, "Current Phase");
        assert!(phase.contains("Phase 2"), "Should parse 'Phase 2' from bold format");

        let status = parse_state_field(content, "Status");
        assert_eq!(status, "In Progress");

        let progress = parse_state_field(content, "Progress");
        assert_eq!(progress, "50%");
    }

    #[test]
    fn test_format_helpers() {
        // Token formatting
        assert_eq!(fmt_tok(500), "500");
        assert_eq!(fmt_tok(1500), "1.5K");
        assert_eq!(fmt_tok(10000), "10.0K");
        assert_eq!(fmt_tok(1500000), "1.5M");
        assert_eq!(fmt_tok(200000), "200.0K");

        // Duration formatting
        assert_eq!(fmt_dur(5000), "5s");
        assert_eq!(fmt_dur(125000), "2m 5s");
        assert_eq!(fmt_dur(3700000), "1h 1m");

        // Cost formatting
        assert_eq!(fmt_cost(1.23), "$1.23");
        assert_eq!(fmt_cost(15.5), "$15.5");
        assert_eq!(fmt_cost(150.0), "$150");

        // Progress bar
        let bar = progress_bar(50, 10);
        assert!(bar.contains('\u{2593}'), "Should contain filled blocks");
        assert!(bar.contains('\u{2591}'), "Should contain empty blocks");

        // Extract number
        assert_eq!(extract_first_number("Phase 2"), Some(2));
        assert_eq!(extract_first_number("02-fix-statusline"), Some(2));
        assert_eq!(extract_first_number("no number"), None);

        // Version comparison
        assert!(version_is_newer("2.3.0", "2.2.2"));
        assert!(!version_is_newer("2.2.2", "2.2.2"));
        assert!(!version_is_newer("2.2.1", "2.2.2"));
    }

    #[test]
    fn test_fast_cache_execution_state() {
        // Test parsing execution state JSON
        let exec_json = r#"{
            "status": "running",
            "wave": 2,
            "total_waves": 3,
            "plans": [
                {"title": "Plan A", "status": "complete"},
                {"title": "Plan B", "status": "running"},
                {"title": "Plan C", "status": "pending"}
            ]
        }"#;
        let exec: Value = serde_json::from_str(exec_json).unwrap();
        let status = exec.get("status").and_then(|v| v.as_str()).unwrap();
        assert_eq!(status, "running");
        let plans = exec.get("plans").and_then(|v| v.as_array()).unwrap();
        assert_eq!(plans.len(), 3);
        let done = plans.iter()
            .filter(|p| p.get("status").and_then(|s| s.as_str()) == Some("complete"))
            .count();
        assert_eq!(done, 1);
        let current = plans.iter()
            .find(|p| p.get("status").and_then(|s| s.as_str()) == Some("running"))
            .and_then(|p| p.get("title").and_then(|t| t.as_str()))
            .unwrap();
        assert_eq!(current, "Plan B");
    }

    #[test]
    fn test_extract_repo_name() {
        assert_eq!(extract_repo_name("https://github.com/user/myrepo.git"), "myrepo");
        assert_eq!(extract_repo_name("git@github.com:user/myrepo.git"), "myrepo");
        assert_eq!(extract_repo_name("https://github.com/user/myrepo"), "myrepo");
    }

    #[test]
    fn test_countdown() {
        assert_eq!(countdown(0), "");
        assert_eq!(countdown(-1), "");
        // A past epoch should return "now"
        assert_eq!(countdown(1), "now");
    }
}
