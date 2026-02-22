use regex::Regex;
use sha2::{Sha256, Digest};
use std::path::{Path, PathBuf};

/// Returns the cache directory path: /tmp/yolo-tier-cache-{uid}/
fn cache_dir() -> PathBuf {
    let uid = unsafe { libc::getuid() };
    PathBuf::from(format!("/tmp/yolo-tier-cache-{}", uid))
}

/// Returns a short hash of the planning directory path for cache key scoping.
/// This ensures different projects (different planning dirs) get separate cache entries.
fn dir_hash(planning_dir: &Path) -> String {
    let canonical = planning_dir.canonicalize()
        .unwrap_or_else(|_| planning_dir.to_path_buf());
    let full = sha256_of(&canonical.to_string_lossy());
    full[..8].to_string()
}

/// Gets the max mtime (as seconds since epoch) across a list of file paths.
/// Returns 0 if no files exist.
fn max_mtime(paths: &[PathBuf]) -> u64 {
    paths.iter().filter_map(|p| {
        std::fs::metadata(p).ok().and_then(|m| {
            m.modified().ok().and_then(|t| {
                t.duration_since(std::time::UNIX_EPOCH).ok().map(|d| d.as_secs())
            })
        })
    }).max().unwrap_or(0)
}

/// Tries to read a cached tier file. Returns Some(content) on cache hit.
/// Cache file format: first line is JSON {"mtime_secs":N,"hash":"sha256hex"},
/// rest is cached content.
fn read_cache(cache_path: &Path, source_mtime: u64) -> Option<String> {
    let raw = std::fs::read_to_string(cache_path).ok()?;
    let newline_pos = raw.find('\n')?;
    let header_line = &raw[..newline_pos];
    let content = &raw[newline_pos + 1..];

    let header: serde_json::Value = serde_json::from_str(header_line).ok()?;
    let stored_mtime = header.get("mtime_secs")?.as_u64()?;
    let stored_hash = header.get("hash")?.as_str()?;

    if stored_mtime < source_mtime {
        return None;
    }

    // Verify content integrity
    if sha256_of(content) != stored_hash {
        return None;
    }

    Some(content.to_string())
}

/// Writes content to a cache file with mtime header. Fail-open: errors are ignored.
fn write_cache(cache_path: &Path, content: &str, source_mtime: u64) {
    let hash = sha256_of(content);
    let header = format!("{{\"mtime_secs\":{},\"hash\":\"{}\"}}", source_mtime, hash);
    let full = format!("{}\n{}", header, content);
    let _ = std::fs::create_dir_all(cache_path.parent().unwrap_or(Path::new("/tmp")));
    let _ = std::fs::write(cache_path, full);
}

/// Maps a role name to its role family for tier 2 content selection.
pub fn role_family(role: &str) -> &'static str {
    match role {
        "architect" | "lead" => "planning",
        "dev" | "senior" | "qa" | "security" | "debugger" => "execution",
        _ => "default",
    }
}

/// Returns the deterministic list of tier 1 file basenames (shared base).
pub fn tier1_files() -> Vec<&'static str> {
    vec!["CONVENTIONS.md", "STACK.md"]
}

/// Returns the deterministic list of tier 2 file basenames for a given role family.
pub fn tier2_files(family: &str) -> Vec<&'static str> {
    match family {
        "planning" => vec!["ARCHITECTURE.md", "ROADMAP.md", "REQUIREMENTS.md"],
        "execution" => vec!["ROADMAP.md"],
        _ => vec!["ROADMAP.md"],
    }
}

/// Builds tier 1 content without caching (the raw computation).
fn build_tier1_uncached(planning_dir: &Path) -> String {
    let codebase_dir = planning_dir.join("codebase");
    let mut content = String::from("--- TIER 1: SHARED BASE ---\n");
    for basename in tier1_files() {
        let file_path = codebase_dir.join(basename);
        if let Ok(text) = std::fs::read_to_string(&file_path) {
            content.push_str(&format!("\n# {}\n{}\n", basename, text));
        }
    }
    content
}

/// Reads tier 1 files from the planning codebase directory and produces
/// deterministic content with the `--- TIER 1: SHARED BASE ---` header.
/// Uses mtime-based caching to skip recomputation when source files are unchanged.
pub fn build_tier1(planning_dir: &Path) -> String {
    let codebase_dir = planning_dir.join("codebase");
    let source_paths: Vec<PathBuf> = tier1_files().iter()
        .map(|b| codebase_dir.join(b))
        .collect();
    let mtime = max_mtime(&source_paths);

    let dh = dir_hash(planning_dir);
    let cache_path = cache_dir().join(format!("tier1-{}.cache", dh));
    if let Some(cached) = read_cache(&cache_path, mtime) {
        return cached;
    }

    let content = build_tier1_uncached(planning_dir);
    write_cache(&cache_path, &content, mtime);
    content
}

/// Filters completed phase detail sections from ROADMAP.md content.
///
/// Parses the progress table to identify phases with status "Complete",
/// then removes their `## Phase N: ...` detail sections (from the header
/// to the next `---` separator or `## Phase` header). Preserves the file
/// header, goal, scope, progress table, phase list checkboxes, and
/// non-complete phase sections.
///
/// Cache invalidation happens naturally: when this function produces
/// different output (due to newly completed phases), the content hash
/// in the tier cache will mismatch, triggering a cache rebuild.
fn filter_completed_phases(text: &str) -> String {
    // Pass 1: collect completed phase numbers from progress table rows
    let table_re = Regex::new(r"^\|\s*(\d+)\s*\|\s*Complete\s*\|").unwrap();
    let mut completed: Vec<u32> = Vec::new();
    for line in text.lines() {
        if let Some(caps) = table_re.captures(line) {
            if let Ok(n) = caps[1].parse::<u32>() {
                completed.push(n);
            }
        }
    }

    if completed.is_empty() {
        return text.to_string();
    }

    // Pass 2: filter out ## Phase N sections for completed phases
    let phase_header_re = Regex::new(r"^## Phase (\d+):").unwrap();
    let mut result = String::with_capacity(text.len());
    let mut skipping = false;

    for line in text.lines() {
        // Check if this line starts a phase detail section
        if let Some(caps) = phase_header_re.captures(line) {
            if let Ok(n) = caps[1].parse::<u32>() {
                if completed.contains(&n) {
                    skipping = true;
                    continue;
                } else {
                    skipping = false;
                }
            }
        }

        // A `---` separator or a new `## Phase` header ends a skipped section
        if skipping {
            if line.trim() == "---" {
                // The separator belongs to the completed section; skip it too
                continue;
            }
            if phase_header_re.is_match(line) {
                // New phase section starts — stop skipping (handled above on next iteration)
                // but this line is a non-completed phase header, so keep it
                skipping = false;
            } else {
                continue;
            }
        }

        result.push_str(line);
        result.push('\n');
    }

    // Remove trailing extra newline if original didn't end with one
    if !text.ends_with('\n') && result.ends_with('\n') {
        result.pop();
    }

    result
}

/// Builds tier 2 content without caching (the raw computation).
fn build_tier2_uncached(planning_dir: &Path, family: &str) -> String {
    let codebase_dir = planning_dir.join("codebase");
    let mut content = format!("--- TIER 2: ROLE FAMILY ({}) ---\n", family);
    for basename in tier2_files(family) {
        // Tier 2 files may live in codebase/ or directly in planning_dir
        let file_path = codebase_dir.join(basename);
        let fallback_path = planning_dir.join(basename);
        let text = std::fs::read_to_string(&file_path)
            .or_else(|_| std::fs::read_to_string(&fallback_path));
        if let Ok(text) = text {
            let filtered = if basename == "ROADMAP.md" {
                filter_completed_phases(&text)
            } else {
                text
            };
            content.push_str(&format!("\n# {}\n{}\n", basename, filtered));
        }
    }
    content
}

/// Reads tier 2 files for the given role family and produces deterministic
/// content with the `--- TIER 2: ROLE FAMILY ({family}) ---` header.
/// Uses mtime-based caching to skip recomputation when source files are unchanged.
pub fn build_tier2(planning_dir: &Path, family: &str) -> String {
    let codebase_dir = planning_dir.join("codebase");
    let source_paths: Vec<PathBuf> = tier2_files(family).iter()
        .map(|b| {
            let primary = codebase_dir.join(b);
            if primary.exists() { primary } else { planning_dir.join(b) }
        })
        .collect();
    let mtime = max_mtime(&source_paths);

    let dh = dir_hash(planning_dir);
    let cache_path = cache_dir().join(format!("tier2-{}-{}.cache", family, dh));
    if let Some(cached) = read_cache(&cache_path, mtime) {
        return cached;
    }

    let content = build_tier2_uncached(planning_dir, family);
    write_cache(&cache_path, &content, mtime);
    content
}

/// Reads phase plans and produces the volatile tail with the
/// `--- TIER 3: VOLATILE TAIL (phase={N}) ---` header.
///
/// Does NOT include git diff (caller adds that for MCP vs CLI differences).
pub fn build_tier3_volatile(
    phase: i64,
    phases_dir: Option<&Path>,
    plan_path: Option<&Path>,
) -> String {
    let mut content = format!("--- TIER 3: VOLATILE TAIL (phase={}) ---\n", phase);

    // If a specific plan_path is provided, read it directly
    if let Some(pp) = plan_path {
        if let Ok(text) = std::fs::read_to_string(pp) {
            let name = pp.file_name().map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "plan".to_string());
            content.push_str(&format!("\n# Phase {} Plan: {}\n{}\n", phase, name, text));
        }
        return content;
    }

    // Otherwise enumerate plan files from the phases directory
    if phase > 0 {
        if let Some(pd) = phases_dir {
            let phase_dir = pd.join(format!("{:02}", phase));
            if phase_dir.is_dir() {
                let mut entries: Vec<_> = std::fs::read_dir(&phase_dir)
                    .into_iter()
                    .flatten()
                    .flatten()
                    .filter(|e| {
                        let name = e.file_name();
                        let name_str = name.to_string_lossy();
                        name_str.ends_with("-PLAN.md") || name_str.ends_with(".plan.jsonl")
                    })
                    .collect();
                // Sort by filename for deterministic ordering
                entries.sort_by_key(|e| e.file_name());
                for entry in entries {
                    if let Ok(text) = std::fs::read_to_string(entry.path()) {
                        let name = entry.file_name().to_string_lossy().to_string();
                        content.push_str(&format!("\n# Phase {} Plan: {}\n{}\n", phase, name, text));
                    }
                }
            }
        }
    }
    content
}

/// Removes all files in the tier cache directory. Fail-open: errors are ignored.
pub fn invalidate_tier_cache() -> Result<(), String> {
    let dir = cache_dir();
    if !dir.exists() {
        return Ok(());
    }
    let entries = std::fs::read_dir(&dir).map_err(|e| e.to_string())?;
    for entry in entries.flatten() {
        let _ = std::fs::remove_file(entry.path());
    }
    Ok(())
}

/// Computes the SHA-256 hex digest of a string.
pub fn sha256_of(s: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(s.as_bytes());
    format!("{:x}", hasher.finalize())
}

/// Minifies markdown text by collapsing excessive whitespace and removing decorative separators.
///
/// Specifically:
/// 1. Collapses 2+ consecutive empty lines into exactly 1 empty line
/// 2. Removes lines that are only `---` (bare horizontal separators), but preserves
///    tier headers like `--- TIER 1: SHARED BASE ---`
/// 3. Trims trailing whitespace from every line
/// 4. Preserves all meaningful content (headers, code blocks, tables, lists)
pub fn minify_markdown(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    let mut consecutive_empty = 0u32;

    for line in text.lines() {
        let trimmed_right = line.trim_end();

        // Remove bare `---` separators (but keep tier headers like `--- TIER 1: ... ---`)
        if trimmed_right.trim() == "---" {
            // Skip bare separators entirely
            continue;
        }

        if trimmed_right.is_empty() {
            consecutive_empty += 1;
            if consecutive_empty <= 1 {
                result.push('\n');
            }
            // Skip additional consecutive empty lines
            continue;
        }

        // Non-empty line: reset empty counter
        consecutive_empty = 0;
        result.push_str(trimmed_right);
        result.push('\n');
    }

    // Trim trailing newlines to at most one
    while result.ends_with("\n\n") {
        result.pop();
    }

    result
}

/// The 3-tier context structure with content, hashes, and backward-compatible combined field.
pub struct TieredContext {
    pub tier1: String,
    pub tier2: String,
    pub tier3: String,
    pub tier1_hash: String,
    pub tier2_hash: String,
    pub combined: String,
}

/// Orchestrates building all three tiers, computing hashes, and producing the combined output.
pub fn build_tiered_context(
    planning_dir: &Path,
    role: &str,
    phase: i64,
    phases_dir: Option<&Path>,
    plan_path: Option<&Path>,
) -> TieredContext {
    let family = role_family(role);
    let tier1 = build_tier1(planning_dir);
    let tier2 = build_tier2(planning_dir, family);
    let tier3 = build_tier3_volatile(phase, phases_dir, plan_path);

    let tier1_hash = sha256_of(&tier1);
    let tier2_hash = sha256_of(&tier2);
    let combined = format!("{}\n{}\n{}", tier1, tier2, tier3);
    let combined = minify_markdown(&combined);

    TieredContext {
        tier1,
        tier2,
        tier3,
        tier1_hash,
        tier2_hash,
        combined,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// Creates a temp planning directory with standard test files.
    fn setup_planning_dir() -> tempfile::TempDir {
        let tmp = tempfile::tempdir().expect("failed to create temp dir");
        let planning = tmp.path().join(".yolo-planning");
        let codebase = planning.join("codebase");
        fs::create_dir_all(&codebase).unwrap();

        fs::write(codebase.join("CONVENTIONS.md"), "Convention rules here").unwrap();
        fs::write(codebase.join("STACK.md"), "Stack: Rust + TypeScript").unwrap();
        fs::write(codebase.join("ARCHITECTURE.md"), "Architecture overview").unwrap();
        fs::write(codebase.join("ROADMAP.md"), "Roadmap content").unwrap();
        fs::write(planning.join("ROADMAP.md"), "Roadmap content fallback").unwrap();
        fs::write(planning.join("REQUIREMENTS.md"), "Requirements list").unwrap();
        fs::write(codebase.join("REQUIREMENTS.md"), "Requirements list").unwrap();

        // Phase plans
        let phase_dir = planning.join("phases/03");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(phase_dir.join("01-PLAN.md"), "Plan A content").unwrap();
        fs::write(phase_dir.join("02-PLAN.md"), "Plan B content").unwrap();

        tmp
    }

    #[test]
    fn test_role_family_known_roles() {
        assert_eq!(role_family("architect"), "planning");
        assert_eq!(role_family("lead"), "planning");
        assert_eq!(role_family("dev"), "execution");
        assert_eq!(role_family("senior"), "execution");
        assert_eq!(role_family("qa"), "execution");
        assert_eq!(role_family("security"), "execution");
        assert_eq!(role_family("debugger"), "execution");
        assert_eq!(role_family("unknown"), "default");
        assert_eq!(role_family(""), "default");
    }

    #[test]
    fn test_tier1_files_list() {
        let files = tier1_files();
        assert_eq!(files, vec!["CONVENTIONS.md", "STACK.md"]);
    }

    #[test]
    fn test_tier2_files_by_family() {
        let planning = tier2_files("planning");
        assert_eq!(planning, vec!["ARCHITECTURE.md", "ROADMAP.md", "REQUIREMENTS.md"]);

        let execution = tier2_files("execution");
        assert_eq!(execution, vec!["ROADMAP.md"]);

        let default = tier2_files("default");
        assert_eq!(default, vec!["ROADMAP.md"]);
    }

    #[test]
    fn test_tier1_byte_identical_across_roles() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        let t1_dev = build_tier1(&planning);
        let t1_arch = build_tier1(&planning);
        let t1_lead = build_tier1(&planning);

        // Tier 1 must be byte-identical regardless of role
        assert_eq!(t1_dev, t1_arch);
        assert_eq!(t1_dev, t1_lead);
        assert!(t1_dev.contains("--- TIER 1: SHARED BASE ---"));
        assert!(t1_dev.contains("Convention rules here"));
        assert!(t1_dev.contains("Stack: Rust + TypeScript"));
    }

    #[test]
    fn test_tier2_same_family_identical() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        // dev and qa are both "execution" family
        let t2_dev = build_tier2(&planning, role_family("dev"));
        let t2_qa = build_tier2(&planning, role_family("qa"));
        assert_eq!(t2_dev, t2_qa);

        // lead and architect are both "planning" family
        let t2_lead = build_tier2(&planning, role_family("lead"));
        let t2_arch = build_tier2(&planning, role_family("architect"));
        assert_eq!(t2_lead, t2_arch);
    }

    #[test]
    fn test_tier2_different_families_differ() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        let t2_dev = build_tier2(&planning, role_family("dev"));
        let t2_lead = build_tier2(&planning, role_family("lead"));

        // Different families must produce different tier 2 content
        assert_ne!(t2_dev, t2_lead);

        // Planning family gets ARCHITECTURE.md, execution does not
        assert!(t2_lead.contains("Architecture overview"));
        assert!(!t2_dev.contains("Architecture overview"));
    }

    #[test]
    fn test_build_tiered_context_all_fields() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let phases = planning.join("phases");

        let ctx = build_tiered_context(&planning, "dev", 3, Some(&phases), None);

        assert!(ctx.tier1.contains("--- TIER 1: SHARED BASE ---"));
        assert!(ctx.tier2.contains("--- TIER 2: ROLE FAMILY (execution) ---"));
        assert!(ctx.tier3.contains("--- TIER 3: VOLATILE TAIL (phase=3) ---"));
        assert!(ctx.tier3.contains("Plan A content"));
        assert!(ctx.tier3.contains("Plan B content"));

        assert_eq!(ctx.tier1_hash, sha256_of(&ctx.tier1));
        assert_eq!(ctx.tier2_hash, sha256_of(&ctx.tier2));
    }

    #[test]
    fn test_combined_is_minified_tiers_joined() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let phases = planning.join("phases");

        let ctx = build_tiered_context(&planning, "architect", 3, Some(&phases), None);
        let raw = format!("{}\n{}\n{}", ctx.tier1, ctx.tier2, ctx.tier3);
        let expected = minify_markdown(&raw);
        assert_eq!(ctx.combined, expected);
        // Minified should be no larger than raw
        assert!(ctx.combined.len() <= raw.len());
    }

    #[test]
    fn test_sha256_deterministic() {
        let input = "hello world";
        let h1 = sha256_of(input);
        let h2 = sha256_of(input);
        assert_eq!(h1, h2);
        assert_eq!(h1.len(), 64); // SHA-256 hex is 64 chars
    }

    #[test]
    fn test_tier3_with_explicit_plan_path() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let plan = planning.join("phases/03/01-PLAN.md");

        let t3 = build_tier3_volatile(3, None, Some(&plan));
        assert!(t3.contains("--- TIER 3: VOLATILE TAIL (phase=3) ---"));
        assert!(t3.contains("Plan A content"));
        // Should only contain the explicit plan, not Plan B
        assert!(!t3.contains("Plan B content"));
    }

    #[test]
    fn test_tier3_sorts_plan_files() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let phases = planning.join("phases");

        let t3 = build_tier3_volatile(3, Some(&phases), None);
        // Both plans should be present
        assert!(t3.contains("Plan A content"));
        assert!(t3.contains("Plan B content"));
        // 01-PLAN.md should appear before 02-PLAN.md (sorted order)
        let pos_a = t3.find("Plan A content").unwrap();
        let pos_b = t3.find("Plan B content").unwrap();
        assert!(pos_a < pos_b);
    }

    #[test]
    fn test_tier1_cache_hit() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        // First call populates cache
        let t1_first = build_tier1(&planning);
        // Second call should return identical content (from cache)
        let t1_second = build_tier1(&planning);
        assert_eq!(t1_first, t1_second);
        assert!(t1_first.contains("--- TIER 1: SHARED BASE ---"));
        assert!(t1_first.contains("Convention rules here"));
    }

    #[test]
    fn test_tier1_cache_invalidation() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let codebase = planning.join("codebase");

        let t1_before = build_tier1(&planning);
        assert!(t1_before.contains("Convention rules here"));

        // Sleep briefly so mtime definitely changes
        std::thread::sleep(std::time::Duration::from_millis(1100));

        // Modify source file to change mtime and content
        fs::write(codebase.join("CONVENTIONS.md"), "Updated conventions").unwrap();

        let t1_after = build_tier1(&planning);
        // Cache should be invalidated, new content returned
        assert!(t1_after.contains("Updated conventions"));
        assert!(!t1_after.contains("Convention rules here"));
    }

    #[test]
    fn test_tier2_cache_per_family() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        let t2_planning = build_tier2(&planning, "planning");
        let t2_execution = build_tier2(&planning, "execution");

        // Different families must have different content
        assert_ne!(t2_planning, t2_execution);
        assert!(t2_planning.contains("Architecture overview"));
        assert!(!t2_execution.contains("Architecture overview"));

        // Subsequent calls return same content
        let t2_planning2 = build_tier2(&planning, "planning");
        let t2_execution2 = build_tier2(&planning, "execution");
        assert_eq!(t2_planning, t2_planning2);
        assert_eq!(t2_execution, t2_execution2);
    }

    #[test]
    fn test_cache_corruption_fallback() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        // Build once to establish expected content
        let expected = build_tier1_uncached(&planning);

        // Write corrupt cache file at the dir-scoped path
        let cdir = cache_dir();
        let dh = dir_hash(&planning);
        fs::create_dir_all(&cdir).unwrap();
        fs::write(cdir.join(format!("tier1-{}.cache", dh)), "not valid json\ngarbage content").unwrap();

        // build_tier1 should fall through to normal build (fail-open)
        let result = build_tier1(&planning);
        assert_eq!(result, expected);
    }

    #[test]
    fn test_invalidate_tier_cache() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");

        // Build to populate cache
        let _ = build_tier1(&planning);
        let _ = build_tier2(&planning, "execution");

        let cdir = cache_dir();
        let dh = dir_hash(&planning);
        // Cache files should exist (scoped by dir hash)
        assert!(cdir.join(format!("tier1-{}.cache", dh)).exists());
        assert!(cdir.join(format!("tier2-execution-{}.cache", dh)).exists());

        // Invalidate
        invalidate_tier_cache().expect("invalidation should succeed");

        // Cache files should be gone
        assert!(!cdir.join(format!("tier1-{}.cache", dh)).exists());
        assert!(!cdir.join(format!("tier2-execution-{}.cache", dh)).exists());
    }

    // --- filter_completed_phases tests ---

    fn sample_roadmap() -> String {
        r#"# Roadmap Title

**Goal:** Build things

**Scope:** 3 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3 | 10 | 8 |
| 2 | Pending | 0 | 0 | 0 |
| 3 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] Phase 1
- [ ] Phase 2
- [ ] Phase 3

---

## Phase 1: Foundation

**Goal:** Build foundation

**Success Criteria:**
- Everything works

**Dependencies:** None

---

## Phase 2: Features

**Goal:** Add features

**Success Criteria:**
- Features work

**Dependencies:** Phase 1

---

## Phase 3: Polish

**Goal:** Polish everything

**Success Criteria:**
- Polished

**Dependencies:** Phase 2"#
            .to_string()
    }

    #[test]
    fn test_filter_completed_phases_basic() {
        let input = sample_roadmap();
        let result = filter_completed_phases(&input);

        // Header, goal, scope preserved
        assert!(result.contains("# Roadmap Title"));
        assert!(result.contains("**Goal:** Build things"));
        assert!(result.contains("**Scope:** 3 phases"));

        // Progress table preserved (including the Complete row)
        assert!(result.contains("| 1 | Complete | 3 | 10 | 8 |"));
        assert!(result.contains("| 2 | Pending | 0 | 0 | 0 |"));

        // Phase list preserved
        assert!(result.contains("- [x] Phase 1"));
        assert!(result.contains("- [ ] Phase 2"));

        // Phase 1 detail section removed
        assert!(!result.contains("## Phase 1: Foundation"));
        assert!(!result.contains("Build foundation"));

        // Phases 2 and 3 detail sections preserved
        assert!(result.contains("## Phase 2: Features"));
        assert!(result.contains("Add features"));
        assert!(result.contains("## Phase 3: Polish"));
        assert!(result.contains("Polish everything"));
    }

    #[test]
    fn test_filter_completed_phases_all_complete() {
        let input = r#"# Roadmap

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3 | 10 | 8 |
| 2 | Complete | 2 | 5 | 4 |

---

## Phase List
- [x] Phase 1
- [x] Phase 2

---

## Phase 1: First

**Goal:** First phase

---

## Phase 2: Second

**Goal:** Second phase"#;

        let result = filter_completed_phases(input);

        // Header and progress table preserved
        assert!(result.contains("# Roadmap"));
        assert!(result.contains("| 1 | Complete |"));
        assert!(result.contains("| 2 | Complete |"));
        assert!(result.contains("## Phase List"));

        // All phase detail sections removed
        assert!(!result.contains("## Phase 1: First"));
        assert!(!result.contains("## Phase 2: Second"));
        assert!(!result.contains("First phase"));
        assert!(!result.contains("Second phase"));
    }

    #[test]
    fn test_filter_completed_phases_none_complete() {
        let input = r#"# Roadmap

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Pending | 0 | 0 | 0 |
| 2 | Pending | 0 | 0 | 0 |

---

## Phase 1: First

**Goal:** First phase

---

## Phase 2: Second

**Goal:** Second phase"#;

        let result = filter_completed_phases(input);

        // No filtering — output equals input
        // (Normalize trailing newline for comparison)
        assert_eq!(result.trim(), input.trim());
    }

    #[test]
    fn test_tier2_roadmap_filtered() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let codebase = planning.join("codebase");

        // Write a ROADMAP with Phase 1 Complete, Phase 2 Pending
        let roadmap = r#"# Test Roadmap

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 2 | 5 | 4 |
| 2 | Pending | 0 | 0 | 0 |

---

## Phase 1: Done Phase

**Goal:** Already done

---

## Phase 2: Active Phase

**Goal:** Currently active"#;

        fs::write(codebase.join("ROADMAP.md"), roadmap).unwrap();

        // Invalidate cache to force rebuild
        invalidate_tier_cache().unwrap();

        let t2 = build_tier2(&planning, "execution");

        // Progress table preserved
        assert!(t2.contains("| 1 | Complete |"));
        assert!(t2.contains("| 2 | Pending |"));

        // Completed phase section filtered out
        assert!(!t2.contains("## Phase 1: Done Phase"));
        assert!(!t2.contains("Already done"));

        // Active phase section preserved
        assert!(t2.contains("## Phase 2: Active Phase"));
        assert!(t2.contains("Currently active"));
    }
}
