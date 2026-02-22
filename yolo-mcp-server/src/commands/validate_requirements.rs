use serde_json::json;
use std::fs;
use std::path::Path;
use std::process::Command;

/// Validates that plan requirements (must_haves) are evidenced in deliverables.
///
/// Usage: yolo validate-requirements <plan_path> <phase_dir>
///
/// Checks:
/// 1. Read PLAN.md YAML frontmatter: extract must_haves array
/// 2. For each must_have: search for evidence in SUMMARY.md files in phase_dir
/// 3. Search in committed code: `git log --all --oneline --grep="{keyword}"`
/// 4. Mark as "verified" if evidence found, "unverified" if not
///
/// Exit codes: 0=all verified, 1=some unverified
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err(
            "Usage: yolo validate-requirements <plan_path> <phase_dir>".to_string(),
        );
    }

    let plan_path = Path::new(&args[2]);
    let phase_dir = Path::new(&args[3]);

    if !plan_path.exists() {
        let resp = json!({
            "ok": false,
            "cmd": "validate-requirements",
            "total": 0,
            "verified": 0,
            "unverified": 0,
            "requirements": [{"requirement": "N/A", "status": "unverified", "evidence": format!("Plan not found: {}", plan_path.display())}],
        });
        return Ok((resp.to_string(), 1));
    }

    let plan_content = fs::read_to_string(plan_path)
        .map_err(|e| format!("Failed to read plan: {}", e))?;

    let frontmatter = extract_frontmatter(&plan_content);
    let must_haves = match &frontmatter {
        Some(fm) => parse_list_field(fm, "must_haves"),
        None => Vec::new(),
    };

    if must_haves.is_empty() {
        let resp = json!({
            "ok": true,
            "cmd": "validate-requirements",
            "total": 0,
            "verified": 0,
            "unverified": 0,
            "requirements": [],
        });
        return Ok((resp.to_string(), 0));
    }

    // Collect SUMMARY content from phase_dir
    let summary_content = collect_summaries(phase_dir);

    let mut requirements = Vec::new();
    let mut verified_count = 0u32;
    let mut unverified_count = 0u32;

    for must_have in &must_haves {
        let keywords = extract_keywords(must_have);
        let mut evidence = String::new();
        let mut found = false;

        // Search in SUMMARY files
        for keyword in &keywords {
            let kw_lower = keyword.to_lowercase();
            if summary_content.to_lowercase().contains(&kw_lower) {
                evidence = format!("Found '{}' in SUMMARY files", keyword);
                found = true;
                break;
            }
        }

        // Search in git commits if not found in summaries
        if !found {
            for keyword in &keywords {
                if search_git_log(keyword, cwd) {
                    evidence = format!("Found '{}' in git commit log", keyword);
                    found = true;
                    break;
                }
            }
        }

        if found {
            verified_count += 1;
            requirements.push(json!({
                "requirement": must_have,
                "status": "verified",
                "evidence": evidence,
            }));
        } else {
            unverified_count += 1;
            requirements.push(json!({
                "requirement": must_have,
                "status": "unverified",
                "evidence": "No evidence found in SUMMARY files or git log",
            }));
        }
    }

    let ok = unverified_count == 0;
    let resp = json!({
        "ok": ok,
        "cmd": "validate-requirements",
        "total": must_haves.len(),
        "verified": verified_count,
        "unverified": unverified_count,
        "requirements": requirements,
    });

    Ok((resp.to_string(), if ok { 0 } else { 1 }))
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

/// Parse a YAML list field from frontmatter.
fn parse_list_field(frontmatter: &str, field_name: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut in_field = false;
    let prefix = format!("{}:", field_name);

    for line in frontmatter.lines() {
        let trimmed = line.trim();

        if trimmed.starts_with(&prefix) {
            let value = trimmed[prefix.len()..].trim();

            if value.starts_with('[') {
                let inner = value.trim_start_matches('[').trim_end_matches(']');
                if inner.trim().is_empty() {
                    return result;
                }
                for item in inner.split(',') {
                    let cleaned = item.trim().trim_matches('"').trim_matches('\'').trim();
                    if !cleaned.is_empty() {
                        result.push(cleaned.to_string());
                    }
                }
                return result;
            }

            if value == "[]" {
                return result;
            }

            in_field = true;
            continue;
        }

        if in_field {
            if trimmed.starts_with("- ") {
                let item = trimmed[2..].trim().trim_matches('"').trim_matches('\'');
                if !item.is_empty() {
                    result.push(item.to_string());
                }
            } else if !trimmed.is_empty() {
                break;
            }
        }
    }

    result
}

/// Collect content from all SUMMARY.md files in the phase directory.
fn collect_summaries(phase_dir: &Path) -> String {
    let mut content = String::new();

    if phase_dir.is_dir() {
        if let Ok(entries) = fs::read_dir(phase_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                let name = path.file_name().unwrap_or_default().to_string_lossy();
                if name.contains("SUMMARY") && name.ends_with(".md") {
                    if let Ok(c) = fs::read_to_string(&path) {
                        content.push_str(&c);
                        content.push('\n');
                    }
                }
            }
        }
    }

    // Also check if phase_dir itself is a SUMMARY file
    if phase_dir.is_file() {
        if let Ok(c) = fs::read_to_string(phase_dir) {
            content.push_str(&c);
        }
    }

    content
}

/// Extract meaningful keywords from a requirement string.
/// Filters out common stop words and returns words of 3+ chars.
fn extract_keywords(requirement: &str) -> Vec<String> {
    let stop_words = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "must", "shall", "can", "need", "dare",
        "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by",
        "from", "as", "into", "through", "during", "before", "after", "above",
        "below", "between", "out", "off", "over", "under", "again", "further",
        "then", "once", "and", "but", "or", "nor", "not", "so", "yet", "both",
        "either", "neither", "each", "every", "all", "any", "few", "more",
        "most", "other", "some", "such", "no", "only", "own", "same", "than",
        "too", "very", "just", "that", "this", "these", "those", "it", "its",
    ];

    requirement
        .split(|c: char| !c.is_alphanumeric() && c != '-' && c != '_')
        .filter(|w| w.len() >= 3 && !stop_words.contains(&w.to_lowercase().as_str()))
        .map(|w| w.to_string())
        .collect()
}

/// Search git log for a keyword.
fn search_git_log(keyword: &str, cwd: &Path) -> bool {
    let output = Command::new("git")
        .args(["log", "--all", "--oneline", "--grep", keyword])
        .current_dir(cwd)
        .output();

    match output {
        Ok(o) => {
            o.status.success()
                && !String::from_utf8_lossy(&o.stdout).trim().is_empty()
        }
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_found_requirements_verified() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("PLAN.md");
        let phase_dir = dir.path().join("phase");
        fs::create_dir_all(&phase_dir).unwrap();

        fs::write(
            &plan_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"Test\"
wave: 1
depends_on: []
must_haves:
  - \"QA verification commands work\"
  - \"Commit linting passes\"
---

### Task 1: Build it
",
        )
        .unwrap();

        // Create a SUMMARY that contains evidence
        fs::write(
            phase_dir.join("01-SUMMARY.md"),
            "\
# Summary

QA verification commands implemented and tested.
Commit linting passes for all conventional commits.
",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-requirements".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0, "Expected exit 0, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["verified"], 2);
        assert_eq!(parsed["unverified"], 0);
    }

    #[test]
    fn test_missing_requirement_unverified() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("PLAN.md");
        let phase_dir = dir.path().join("phase");
        fs::create_dir_all(&phase_dir).unwrap();

        fs::write(
            &plan_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"Test\"
wave: 1
depends_on: []
must_haves:
  - \"Quantum flux capacitor integration\"
---

### Task 1: Build it
",
        )
        .unwrap();

        // Empty summary - no evidence
        fs::write(
            phase_dir.join("01-SUMMARY.md"),
            "# Summary\n\nNothing relevant here.\n",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-requirements".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 1, "Expected exit 1, got {}: {}", code, output);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["unverified"], 1);
        let reqs = parsed["requirements"].as_array().unwrap();
        assert_eq!(reqs[0]["status"], "unverified");
    }

    #[test]
    fn test_extract_keywords() {
        let keywords = extract_keywords("QA verification commands work correctly");
        assert!(keywords.contains(&"verification".to_string()));
        assert!(keywords.contains(&"commands".to_string()));
        assert!(keywords.contains(&"correctly".to_string()));
        // "work" is 4 chars and not a stop word
        assert!(keywords.contains(&"work".to_string()));
    }

    #[test]
    fn test_empty_must_haves_passes() {
        let dir = tempdir().unwrap();
        let plan_path = dir.path().join("PLAN.md");
        let phase_dir = dir.path().join("phase");
        fs::create_dir_all(&phase_dir).unwrap();

        fs::write(
            &plan_path,
            "\
---
phase: \"04\"
plan: \"01\"
title: \"Test\"
wave: 1
depends_on: []
must_haves: []
---
",
        )
        .unwrap();

        let args = vec![
            "yolo".to_string(),
            "validate-requirements".to_string(),
            plan_path.to_string_lossy().to_string(),
            phase_dir.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["total"], 0);
    }
}
