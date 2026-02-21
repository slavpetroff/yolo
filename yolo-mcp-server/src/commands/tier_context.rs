use sha2::{Sha256, Digest};
use std::path::Path;

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

/// Reads tier 1 files from the planning codebase directory and produces
/// deterministic content with the `--- TIER 1: SHARED BASE ---` header.
pub fn build_tier1(planning_dir: &Path) -> String {
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

/// Reads tier 2 files for the given role family and produces deterministic
/// content with the `--- TIER 2: ROLE FAMILY ({family}) ---` header.
pub fn build_tier2(planning_dir: &Path, family: &str) -> String {
    let codebase_dir = planning_dir.join("codebase");
    let mut content = format!("--- TIER 2: ROLE FAMILY ({}) ---\n", family);
    for basename in tier2_files(family) {
        // Tier 2 files may live in codebase/ or directly in planning_dir
        let file_path = codebase_dir.join(basename);
        let fallback_path = planning_dir.join(basename);
        let text = std::fs::read_to_string(&file_path)
            .or_else(|_| std::fs::read_to_string(&fallback_path));
        if let Ok(text) = text {
            content.push_str(&format!("\n# {}\n{}\n", basename, text));
        }
    }
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

/// Computes the SHA-256 hex digest of a string.
pub fn sha256_of(s: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(s.as_bytes());
    format!("{:x}", hasher.finalize())
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
    fn test_combined_equals_tiers_joined() {
        let tmp = setup_planning_dir();
        let planning = tmp.path().join(".yolo-planning");
        let phases = planning.join("phases");

        let ctx = build_tiered_context(&planning, "architect", 3, Some(&phases), None);
        let expected = format!("{}\n{}\n{}", ctx.tier1, ctx.tier2, ctx.tier3);
        assert_eq!(ctx.combined, expected);
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
}
