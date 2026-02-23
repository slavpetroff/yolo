---
phase: "03b"
plan: "02"
title: "Eliminate code duplication and fix performance issues"
wave: 1
depends_on: []
must_haves:
  - "Shared sorted_phase_dirs utility eliminates duplicate dir-listing code"
  - "Config parsing uses serde Deserialize struct with defaults"
  - "Regex compiled outside loops in phase_detect.rs and compile_progress.rs"
  - "config_read.rs response builder eliminates 4x duplication"
  - "detect_stack.rs skills kept as Vec throughout"
  - "All existing tests pass"
---

# Plan 03b-02: Eliminate code duplication and fix performance issues

## Summary

Extract shared utilities, eliminate duplicated patterns, and fix the regex-in-loop performance bug.

## Task 1: Extract shared sorted_phase_dirs utility

**File:** Create `yolo-mcp-server/src/commands/utils.rs` (or add to existing shared module)

**Changes:**
1. Extract the "read_dir -> filter dirs matching pattern -> sort by name" utility:
   ```rust
   pub fn sorted_phase_dirs(phases_dir: &Path) -> Vec<(String, PathBuf)> {
       let mut dirs = Vec::new();
       if let Ok(entries) = fs::read_dir(phases_dir) {
           for entry in entries.filter_map(|e| e.ok()) {
               let name = entry.file_name().to_string_lossy().to_string();
               if entry.path().is_dir() && name.chars().next().map_or(false, |c| c.is_ascii_digit()) {
                   dirs.push((name, entry.path()));
               }
           }
       }
       dirs.sort_by(|a, b| a.0.cmp(&b.0));
       dirs
   }
   ```
2. Replace the duplicated implementations in:
   - `phase_detect.rs` (lines ~92-103)
   - `compile_progress.rs` (lines ~160-173)
   - `session_start.rs` (multiple locations)
3. Add `pub mod utils;` to `commands/mod.rs`

## Task 2: Config struct with serde Deserialize

**File:** `yolo-mcp-server/src/commands/utils.rs` (same new file)

**Changes:**
1. Add a shared config struct:
   ```rust
   #[derive(serde::Deserialize)]
   #[serde(default)]
   pub struct YoloConfig {
       pub effort: String,
       pub autonomy: String,
       pub auto_commit: bool,
       pub planning_tracking: String,
       pub auto_push: String,
       pub verification_tier: String,
       pub prefer_teams: String,
       pub max_tasks_per_plan: u32,
       pub context_compiler: bool,
       pub compaction_threshold: u64,
   }

   impl Default for YoloConfig {
       fn default() -> Self {
           YoloConfig {
               effort: "balanced".into(),
               autonomy: "standard".into(),
               auto_commit: true,
               planning_tracking: "commit".into(),
               auto_push: "never".into(),
               verification_tier: "standard".into(),
               prefer_teams: "never".into(),
               max_tasks_per_plan: 5,
               context_compiler: false,
               compaction_threshold: 130000,
           }
       }
   }

   pub fn load_config(config_path: &Path) -> YoloConfig {
       fs::read_to_string(config_path)
           .ok()
           .and_then(|s| serde_json::from_str(&s).ok())
           .unwrap_or_default()
   }
   ```
2. Replace the manual if-let chains in `phase_detect.rs` (lines ~167-195) and `session_start.rs` with `utils::load_config()`
3. Output format uses `config.effort` etc. directly

## Task 3: Fix regex performance issues

**Files:** `phase_detect.rs`, `compile_progress.rs`

**Changes:**
1. In `phase_detect.rs`, move regex outside the loop OR replace with simple string checks:
   ```rust
   // Instead of regex to extract leading digits:
   fn extract_phase_number(dirname: &str) -> Option<&str> {
       let digits: String = dirname.chars().take_while(|c| c.is_ascii_digit()).collect();
       if digits.is_empty() { None } else { Some(digits) }
   }
   ```
   Or if regex is needed, compile once before the loop.

2. In `compile_progress.rs`, replace `count_plans_and_summaries` and `count_tasks_in_phase` regexes with `str` methods:
   ```rust
   fn is_plan_file(name: &str) -> bool {
       name.len() >= 12  // "00-00-PLAN.md"
           && name[..2].bytes().all(|b| b.is_ascii_digit())
           && name[3..5].bytes().all(|b| b.is_ascii_digit())
           && name.ends_with("-PLAN.md")
   }
   ```

## Task 4: Deduplicate config_read.rs response builder

**File:** `yolo-mcp-server/src/commands/config_read.rs`

**Changes:**
1. Extract response builder:
   ```rust
   fn build_response(key: &str, value: Option<&Value>, default: Option<&str>, elapsed: u128) -> String {
       let (resolved_value, source) = match (value, default) {
           (Some(v), _) => (v.clone(), "config"),
           (None, Some(d)) => (Value::String(d.to_string()), "default"),
           (None, None) => (Value::Null, "missing"),
       };
       serde_json::to_string(&json!({
           "key": key,
           "value": resolved_value,
           "source": source,
           "elapsed_ms": elapsed,
       })).unwrap_or_default()
   }
   ```
2. Replace all 4 duplicated response construction sites

## Task 5: Fix detect_stack.rs skills collection

**File:** `yolo-mcp-server/src/commands/detect_stack.rs`

**Changes:**
1. Replace the join-then-split pattern with keeping skills as `Vec<String>` throughout:
   ```rust
   let installed_global: Vec<String> = collect_skills_from_claude_md(&claude_global_path);
   let installed_project: Vec<String> = collect_skills_from_claude_md(&claude_project_path);
   let installed_agents: Vec<String> = collect_skills_from_agent_dir(&agent_dir);
   let all_installed: Vec<String> = [installed_global, installed_project, installed_agents]
       .into_iter().flatten().collect();
   ```
2. Extract `collect_skills_from_claude_md` as a helper that returns `Vec<String>` directly
