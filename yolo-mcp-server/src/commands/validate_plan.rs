use serde_json::json;
use std::fs;
use std::path::Path;

/// Validates a plan file's depends_on references and cross-phase dependencies.
///
/// Usage: yolo validate-plan <plan_path> <phase_dir>
///
/// Checks:
/// 1. Plan file exists and has valid YAML frontmatter
/// 2. depends_on references resolve to existing plan files in phase_dir
/// 3. cross_phase_deps references resolve to completed SUMMARY.md files
///
/// Exit codes: 0=valid, 1=invalid, 2=partial
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err("Usage: yolo validate-plan <plan_path> <phase_dir>".to_string());
    }

    let plan_path = Path::new(&args[2]);
    let phase_dir = Path::new(&args[3]);

    // Check plan file exists
    if !plan_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "validate-plan",
            "errors": [format!("Plan file not found: {}", plan_path.display())]
        });
        return Ok((resp.to_string(), 1));
    }

    let content = fs::read_to_string(plan_path)
        .map_err(|e| format!("Failed to read plan file: {}", e))?;

    // Extract frontmatter
    let frontmatter = match extract_frontmatter(&content) {
        Some(fm) => fm,
        None => {
            let resp = json!({
                "ok": false,
                "cmd": "validate-plan",
                "errors": ["Plan file has no valid YAML frontmatter"]
            });
            return Ok((resp.to_string(), 1));
        }
    };

    let mut errors: Vec<String> = Vec::new();
    let mut depends_on_checked = 0u32;
    let mut cross_phase_checked = 0u32;

    // Validate depends_on
    let depends_on = parse_depends_on(&frontmatter);
    for dep_id in &depends_on {
        depends_on_checked += 1;
        if !plan_file_exists(phase_dir, dep_id) {
            errors.push(format!("depends_on: plan {} not found in phase dir", dep_id));
        }
    }

    // Validate cross_phase_deps
    let cross_phase_deps = parse_cross_phase_deps(&frontmatter);
    for dep in &cross_phase_deps {
        cross_phase_checked += 1;
        match validate_cross_phase_dep(phase_dir, dep) {
            Ok(()) => {}
            Err(msg) => errors.push(msg),
        }
    }

    if errors.is_empty() {
        let resp = json!({
            "ok": true,
            "cmd": "validate-plan",
            "depends_on": {
                "valid": true,
                "checked": depends_on_checked
            },
            "cross_phase": {
                "valid": true,
                "checked": cross_phase_checked
            }
        });
        Ok((resp.to_string(), 0))
    } else {
        let all_deps_failed = errors.len() as u32 == depends_on_checked + cross_phase_checked;
        let exit_code = if all_deps_failed { 1 } else { 2 };
        let resp = json!({
            "ok": false,
            "cmd": "validate-plan",
            "errors": errors,
            "depends_on": {
                "valid": depends_on.is_empty() || !errors.iter().any(|e| e.starts_with("depends_on:")),
                "checked": depends_on_checked
            },
            "cross_phase": {
                "valid": cross_phase_deps.is_empty() || !errors.iter().any(|e| e.starts_with("cross_phase:")),
                "checked": cross_phase_checked
            }
        });
        Ok((resp.to_string(), exit_code))
    }
}

/// Extract frontmatter content between first `---` and second `---`.
fn extract_frontmatter(content: &str) -> Option<String> {
    if !content.starts_with("---") {
        return None;
    }
    let after_first = &content[3..];
    let rest = after_first.trim_start_matches(|c: char| c != '\n');
    let rest = rest.strip_prefix('\n').unwrap_or(rest);
    if let Some(end_idx) = rest.find("\n---") {
        Some(rest[..end_idx].to_string())
    } else if rest.ends_with("---") {
        let trimmed = rest.trim_end_matches("---");
        Some(trimmed.to_string())
    } else {
        None
    }
}

/// Parse depends_on field from frontmatter.
/// Supports both inline array `depends_on: ["01", "02"]` and YAML list format.
fn parse_depends_on(frontmatter: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut in_depends_on = false;

    for line in frontmatter.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with("depends_on:") {
            let value = trimmed["depends_on:".len()..].trim();

            // Check for inline array: depends_on: ["01", "02"]
            if value.starts_with('[') {
                let inner = value.trim_start_matches('[').trim_end_matches(']');
                for item in inner.split(',') {
                    let cleaned = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !cleaned.is_empty() {
                        result.push(cleaned.to_string());
                    }
                }
                return result;
            }

            // Check for empty inline: depends_on: []
            if value == "[]" {
                return result;
            }

            // Start of YAML list
            in_depends_on = true;
            continue;
        }

        if in_depends_on {
            if trimmed.starts_with("- ") {
                let item = trimmed[2..].trim().trim_matches('"').trim_matches('\'');
                if !item.is_empty() {
                    result.push(item.to_string());
                }
            } else if !trimmed.is_empty() {
                // Hit a new field, stop parsing depends_on
                break;
            }
        }
    }

    result
}

/// Parse cross_phase_deps field from frontmatter.
/// Each entry is expected to be in format: "phase:NN:plan:MM" or "NN-MM".
fn parse_cross_phase_deps(frontmatter: &str) -> Vec<CrossPhaseDep> {
    let mut result = Vec::new();
    let mut in_cross_phase = false;

    for line in frontmatter.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with("cross_phase_deps:") {
            let value = trimmed["cross_phase_deps:".len()..].trim();

            // Check for inline array
            if value.starts_with('[') {
                let inner = value.trim_start_matches('[').trim_end_matches(']');
                for item in inner.split(',') {
                    let cleaned = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if let Some(dep) = CrossPhaseDep::parse(cleaned) {
                        result.push(dep);
                    }
                }
                return result;
            }

            if value == "[]" {
                return result;
            }

            in_cross_phase = true;
            continue;
        }

        if in_cross_phase {
            if trimmed.starts_with("- ") {
                let item = trimmed[2..].trim().trim_matches('"').trim_matches('\'');
                if let Some(dep) = CrossPhaseDep::parse(item) {
                    result.push(dep);
                }
            } else if !trimmed.is_empty() {
                break;
            }
        }
    }

    result
}

#[derive(Debug)]
struct CrossPhaseDep {
    phase: String,
    plan: String,
}

impl CrossPhaseDep {
    /// Parse a cross-phase dep reference like "phase:03:plan:01" or "03-01".
    fn parse(s: &str) -> Option<Self> {
        // Try "phase:NN:plan:MM" format
        if s.starts_with("phase:") {
            let parts: Vec<&str> = s.split(':').collect();
            if parts.len() >= 4 && parts[2] == "plan" {
                return Some(CrossPhaseDep {
                    phase: parts[1].to_string(),
                    plan: parts[3].to_string(),
                });
            }
        }

        // Try "NN-MM" format
        let parts: Vec<&str> = s.split('-').collect();
        if parts.len() == 2 {
            return Some(CrossPhaseDep {
                phase: parts[0].to_string(),
                plan: parts[1].to_string(),
            });
        }

        None
    }
}

/// Check if a plan file exists in the phase directory.
/// Tries patterns: {phase_dir}/{id}-PLAN.md, {phase_dir}/{NN}-{id}-PLAN.md
fn plan_file_exists(phase_dir: &Path, plan_id: &str) -> bool {
    // Direct match: {id}-PLAN.md
    if phase_dir.join(format!("{}-PLAN.md", plan_id)).exists() {
        return true;
    }

    // Try glob pattern: any file matching *-{id}-PLAN.md or {id}-*-PLAN.md
    if let Ok(entries) = fs::read_dir(phase_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.ends_with("-PLAN.md") {
                // Check if plan_id appears as a component
                let stem = name_str.trim_end_matches("-PLAN.md");
                let parts: Vec<&str> = stem.split('-').collect();
                if parts.contains(&plan_id.as_ref()) {
                    return true;
                }
            }
        }
    }

    false
}

/// Validate a cross-phase dependency.
/// Checks that the referenced phase's plan SUMMARY.md exists and has status: complete.
fn validate_cross_phase_dep(phase_dir: &Path, dep: &CrossPhaseDep) -> Result<(), String> {
    // Navigate up from phase_dir to phases root, then into target phase
    let phases_root = match phase_dir.parent() {
        Some(p) => p,
        None => {
            return Err(format!(
                "cross_phase: cannot determine phases root from {}",
                phase_dir.display()
            ))
        }
    };

    // Find the target phase directory (pattern: {NN}-{slug}/)
    let target_phase_dir = find_phase_dir(phases_root, &dep.phase);

    match target_phase_dir {
        Some(dir) => {
            // Look for SUMMARY.md: try {plan}-SUMMARY.md or *-{plan}-SUMMARY.md
            let summary = find_summary_file(&dir, &dep.plan);
            match summary {
                Some(summary_path) => {
                    // Check that status is complete
                    let content = fs::read_to_string(&summary_path).map_err(|e| {
                        format!(
                            "cross_phase: Phase {} Plan {} SUMMARY.md unreadable: {}",
                            dep.phase, dep.plan, e
                        )
                    })?;
                    let fm = extract_frontmatter(&content);
                    if let Some(fm) = fm {
                        let status = frontmatter_field_value(&fm, "status");
                        if status.as_deref() != Some("complete") {
                            return Err(format!(
                                "cross_phase: Phase {} Plan {} status is '{}', expected 'complete'",
                                dep.phase,
                                dep.plan,
                                status.unwrap_or_else(|| "missing".to_string())
                            ));
                        }
                    } else {
                        return Err(format!(
                            "cross_phase: Phase {} Plan {} SUMMARY.md has no valid frontmatter",
                            dep.phase, dep.plan
                        ));
                    }
                    Ok(())
                }
                None => Err(format!(
                    "cross_phase: Phase {} Plan {} SUMMARY.md missing",
                    dep.phase, dep.plan
                )),
            }
        }
        None => Err(format!(
            "cross_phase: Phase {} directory not found under {}",
            dep.phase,
            phases_root.display()
        )),
    }
}

/// Find a phase directory matching the given phase number (e.g., "03" -> "03-some-slug/").
fn find_phase_dir(phases_root: &Path, phase_num: &str) -> Option<std::path::PathBuf> {
    if let Ok(entries) = fs::read_dir(phases_root) {
        for entry in entries.flatten() {
            if entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();
                if name_str.starts_with(&format!("{}-", phase_num)) || name_str == phase_num {
                    return Some(entry.path());
                }
            }
        }
    }
    None
}

/// Find a SUMMARY.md file for the given plan ID in a phase directory.
fn find_summary_file(phase_dir: &Path, plan_id: &str) -> Option<std::path::PathBuf> {
    // Direct match
    let direct = phase_dir.join(format!("{}-SUMMARY.md", plan_id));
    if direct.exists() {
        return Some(direct);
    }

    // Glob match
    if let Ok(entries) = fs::read_dir(phase_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.ends_with("-SUMMARY.md") {
                let stem = name_str.trim_end_matches("-SUMMARY.md");
                let parts: Vec<&str> = stem.split('-').collect();
                if parts.contains(&plan_id.as_ref()) {
                    return Some(entry.path());
                }
            }
        }
    }

    None
}

/// Extract the value of a frontmatter field.
fn frontmatter_field_value(frontmatter: &str, field_name: &str) -> Option<String> {
    let prefix = format!("{}:", field_name);
    for line in frontmatter.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim().trim_matches('"').trim();
            return Some(value.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_extract_frontmatter() {
        let content = "---\nphase: \"01\"\nplan: \"01\"\n---\n## Body";
        let fm = extract_frontmatter(content);
        assert!(fm.is_some());
        let fm = fm.unwrap();
        assert!(fm.contains("phase:"));
        assert!(fm.contains("plan:"));
    }

    #[test]
    fn test_extract_frontmatter_missing() {
        let content = "No frontmatter here";
        assert!(extract_frontmatter(content).is_none());
    }

    #[test]
    fn test_parse_depends_on_inline() {
        let fm = "depends_on: [\"01\", \"02\"]\ntitle: test";
        let deps = parse_depends_on(fm);
        assert_eq!(deps, vec!["01", "02"]);
    }

    #[test]
    fn test_parse_depends_on_yaml_list() {
        let fm = "depends_on:\n  - \"01\"\n  - \"02\"\ntitle: test";
        let deps = parse_depends_on(fm);
        assert_eq!(deps, vec!["01", "02"]);
    }

    #[test]
    fn test_parse_depends_on_empty() {
        let fm = "depends_on: []\ntitle: test";
        let deps = parse_depends_on(fm);
        assert!(deps.is_empty());
    }

    #[test]
    fn test_parse_cross_phase_deps() {
        let fm = "cross_phase_deps:\n  - \"phase:03:plan:01\"\ntitle: test";
        let deps = parse_cross_phase_deps(fm);
        assert_eq!(deps.len(), 1);
        assert_eq!(deps[0].phase, "03");
        assert_eq!(deps[0].plan, "01");
    }

    #[test]
    fn test_parse_cross_phase_deps_dash_format() {
        let fm = "cross_phase_deps: [\"03-01\", \"04-02\"]";
        let deps = parse_cross_phase_deps(fm);
        assert_eq!(deps.len(), 2);
        assert_eq!(deps[0].phase, "03");
        assert_eq!(deps[0].plan, "01");
        assert_eq!(deps[1].phase, "04");
        assert_eq!(deps[1].plan, "02");
    }

    #[test]
    fn test_cross_phase_dep_parse() {
        let dep = CrossPhaseDep::parse("phase:03:plan:01");
        assert!(dep.is_some());
        let dep = dep.unwrap();
        assert_eq!(dep.phase, "03");
        assert_eq!(dep.plan, "01");

        let dep2 = CrossPhaseDep::parse("03-01");
        assert!(dep2.is_some());

        assert!(CrossPhaseDep::parse("invalid").is_none());
    }

    #[test]
    fn test_validate_plan_depends_on_satisfied() {
        let dir = tempdir().unwrap();
        let phase_dir = dir.path().join("phases").join("09-validation");
        fs::create_dir_all(&phase_dir).unwrap();

        // Create the plan being validated
        let plan_path = phase_dir.join("09-02-PLAN.md");
        fs::write(
            &plan_path,
            "---\nphase: \"09\"\nplan: \"02\"\ndepends_on: [\"01\"]\n---\n## Tasks\n",
        )
        .unwrap();

        // Create the dependency plan
        fs::write(
            phase_dir.join("09-01-PLAN.md"),
            "---\nphase: \"09\"\nplan: \"01\"\n---\n## Tasks\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["depends_on"]["valid"], true);
        assert_eq!(parsed["depends_on"]["checked"], 1);
    }

    #[test]
    fn test_validate_plan_depends_on_missing() {
        let dir = tempdir().unwrap();
        let phase_dir = dir.path().join("phases").join("09-validation");
        fs::create_dir_all(&phase_dir).unwrap();

        // Create the plan with a dependency that doesn't exist
        let plan_path = phase_dir.join("09-02-PLAN.md");
        fs::write(
            &plan_path,
            "---\nphase: \"09\"\nplan: \"02\"\ndepends_on: [\"03\"]\n---\n## Tasks\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert!(code == 1 || code == 2);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
        let errors = parsed["errors"].as_array().unwrap();
        assert!(errors.iter().any(|e| e.as_str().unwrap().contains("plan 03 not found")));
    }

    #[test]
    fn test_validate_plan_no_depends_on() {
        let dir = tempdir().unwrap();
        let phase_dir = dir.path().join("phases").join("09-validation");
        fs::create_dir_all(&phase_dir).unwrap();

        // Create a plan without depends_on
        let plan_path = phase_dir.join("09-01-PLAN.md");
        fs::write(
            &plan_path,
            "---\nphase: \"09\"\nplan: \"01\"\ndepends_on: []\n---\n## Tasks\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
    }

    #[test]
    fn test_validate_plan_cross_phase_satisfied() {
        let dir = tempdir().unwrap();
        let phases_root = dir.path().join("phases");
        let phase_09 = phases_root.join("09-validation");
        let phase_08 = phases_root.join("08-token-opt");
        fs::create_dir_all(&phase_09).unwrap();
        fs::create_dir_all(&phase_08).unwrap();

        // Create the plan with cross-phase dep
        let plan_path = phase_09.join("09-01-PLAN.md");
        fs::write(
            &plan_path,
            "---\nphase: \"09\"\nplan: \"01\"\ndepends_on: []\ncross_phase_deps:\n  - \"08-01\"\n---\n## Tasks\n",
        )
        .unwrap();

        // Create the cross-phase SUMMARY.md with status: complete
        fs::write(
            phase_08.join("08-01-SUMMARY.md"),
            "---\nphase: \"08\"\nplan: \"01\"\nstatus: complete\n---\n## What Was Built\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_09.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0, "Output: {}", output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["cross_phase"]["valid"], true);
        assert_eq!(parsed["cross_phase"]["checked"], 1);
    }

    #[test]
    fn test_validate_plan_cross_phase_missing() {
        let dir = tempdir().unwrap();
        let phases_root = dir.path().join("phases");
        let phase_09 = phases_root.join("09-validation");
        fs::create_dir_all(&phase_09).unwrap();

        // Create the plan with cross-phase dep (no phase 08 dir)
        let plan_path = phase_09.join("09-01-PLAN.md");
        fs::write(
            &plan_path,
            "---\nphase: \"09\"\nplan: \"01\"\ndepends_on: []\ncross_phase_deps: [\"08-01\"]\n---\n## Tasks\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-plan".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_09.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert!(code == 1 || code == 2);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
    }

    #[test]
    fn test_plan_file_exists() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("09-01-PLAN.md"), "test").unwrap();

        assert!(plan_file_exists(dir.path(), "01"));
        assert!(!plan_file_exists(dir.path(), "03"));
    }

    #[test]
    fn test_frontmatter_field_value() {
        let fm = "status: complete\nphase: \"01\"";
        assert_eq!(frontmatter_field_value(fm, "status"), Some("complete".to_string()));
        assert_eq!(frontmatter_field_value(fm, "phase"), Some("01".to_string()));
        assert_eq!(frontmatter_field_value(fm, "missing"), None);
    }
}
