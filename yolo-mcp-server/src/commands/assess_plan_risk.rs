use std::collections::HashSet;
use std::fs;
use std::path::Path;

/// Classify plan risk as low/medium/high based on metadata signals.
/// Scoring: task_count>5 (+1), file_count>8 (+1), cross_phase_deps (+1),
///          must_haves>4 (+1). Score 0-1=low, 2=medium, 3+=high.
/// Fail-open: defaults to "medium" on any error.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // args: ["yolo", "assess-risk", "<plan-path>"]
    if args.len() < 3 {
        return Ok(("medium\n".to_string(), 0));
    }

    let plan_path_str = &args[2];
    let plan_path = if Path::new(plan_path_str).is_absolute() {
        std::path::PathBuf::from(plan_path_str)
    } else {
        cwd.join(plan_path_str)
    };

    let content = match fs::read_to_string(&plan_path) {
        Ok(c) => c,
        Err(_) => return Ok(("medium\n".to_string(), 0)),
    };

    let risk = assess_risk(&content);
    Ok((format!("{}\n", risk), 0))
}

/// Core risk assessment logic operating on plan content string.
pub fn assess_risk(content: &str) -> &'static str {
    let mut score: u32 = 0;

    // Count tasks from "## Task N:" or "### Task N:" headings
    let task_count = content
        .lines()
        .filter(|line| {
            let trimmed = line.trim_start_matches('#');
            let hashes = line.len() - trimmed.len();
            if hashes < 2 || hashes > 3 {
                return false;
            }
            trimmed.trim_start().starts_with("Task ")
                && trimmed
                    .trim_start()
                    .trim_start_matches("Task ")
                    .starts_with(|c: char| c.is_ascii_digit())
        })
        .count();
    if task_count > 5 {
        score += 1;
    }

    // Count unique file paths from **Files:** lines
    let mut unique_files: HashSet<String> = HashSet::new();
    for line in content.lines() {
        if let Some(after) = line.strip_prefix("**Files:**") {
            let cleaned = after.trim();
            for part in cleaned.split(',') {
                let trimmed = part
                    .trim()
                    .trim_start_matches('`')
                    .trim_end_matches('`')
                    .trim();
                // Remove annotations like "(new)", "(append tests)"
                let path = if let Some(paren_pos) = trimmed.find('(') {
                    trimmed[..paren_pos].trim()
                } else {
                    trimmed
                };
                if !path.is_empty() {
                    unique_files.insert(path.to_string());
                }
            }
        }
    }
    if unique_files.len() > 8 {
        score += 1;
    }

    // Check for cross_phase_deps in frontmatter
    let in_frontmatter = is_in_frontmatter(content, "cross_phase_deps:");
    if in_frontmatter {
        score += 1;
    }

    // Count must_haves list items in frontmatter
    let mh_count = count_frontmatter_list(content, "must_haves:");
    if mh_count > 4 {
        score += 1;
    }

    // Classify
    match score {
        0..=1 => "low",
        2 => "medium",
        _ => "high",
    }
}

/// Check if a key exists anywhere in the YAML frontmatter.
fn is_in_frontmatter(content: &str, key: &str) -> bool {
    let mut in_front = false;
    for line in content.lines() {
        if line.trim() == "---" {
            if !in_front {
                in_front = true;
                continue;
            } else {
                break;
            }
        }
        if in_front && line.contains(key) {
            return true;
        }
    }
    false
}

/// Count list items under a frontmatter key (items starting with "  - ").
fn count_frontmatter_list(content: &str, key: &str) -> usize {
    let mut in_front = false;
    let mut in_list = false;
    let mut count = 0;

    for line in content.lines() {
        if line.trim() == "---" {
            if !in_front {
                in_front = true;
                continue;
            } else {
                break;
            }
        }
        if !in_front {
            continue;
        }
        if line.starts_with(key) || line.starts_with(&format!("  {}", key)) {
            in_list = true;
            continue;
        }
        if in_list {
            let trimmed = line.trim_start();
            if trimmed.starts_with("- ") {
                count += 1;
            } else if !trimmed.is_empty() && !trimmed.starts_with('#') {
                // Non-list, non-empty line ends the list section
                break;
            }
        }
    }
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_low_risk() {
        let content = r#"---
title: "Simple plan"
must_haves:
  - "one"
  - "two"
---

## Task 1: Do something

**Files:** `src/main.rs`
"#;
        assert_eq!(assess_risk(content), "low");
    }

    #[test]
    fn test_medium_risk() {
        let content = r#"---
title: "Medium plan"
cross_phase_deps: [1, 2]
must_haves:
  - "one"
  - "two"
---

## Task 1: A
**Files:** `a.rs`
## Task 2: B
**Files:** `b.rs`
## Task 3: C
**Files:** `c.rs`
## Task 4: D
**Files:** `d.rs`
## Task 5: E
**Files:** `e.rs`
## Task 6: F
**Files:** `f.rs`
"#;
        // task_count=6 > 5 (+1), cross_phase_deps (+1) = score 2 = medium
        assert_eq!(assess_risk(content), "medium");
    }

    #[test]
    fn test_high_risk() {
        let content = r#"---
title: "High risk plan"
cross_phase_deps: [1, 2, 3]
must_haves:
  - "one"
  - "two"
  - "three"
  - "four"
  - "five"
---

## Task 1: A
**Files:** `a.rs`, `b.rs`, `c.rs`
## Task 2: B
**Files:** `d.rs`, `e.rs`, `f.rs`
## Task 3: C
**Files:** `g.rs`, `h.rs`, `i.rs`
## Task 4: D
**Files:** `j.rs`
## Task 5: E
**Files:** `k.rs`
## Task 6: F
**Files:** `l.rs`
"#;
        // task_count=6 > 5 (+1), file_count=12 > 8 (+1), cross_phase_deps (+1), must_haves=5 > 4 (+1) = 4 = high
        assert_eq!(assess_risk(content), "high");
    }

    #[test]
    fn test_empty_content_is_low() {
        assert_eq!(assess_risk(""), "low");
    }

    #[test]
    fn test_no_frontmatter_is_low() {
        let content = "## Task 1: A\n**Files:** `a.rs`\n";
        assert_eq!(assess_risk(content), "low");
    }

    #[test]
    fn test_file_count_with_annotations() {
        let content = r#"---
title: "test"
---

## Task 1: A
**Files:** `a.rs` (new), `b.rs` (append tests), `c.rs`, `d.rs`, `e.rs`, `f.rs`, `g.rs`, `h.rs`, `i.rs`
"#;
        // file_count=9 > 8 (+1), task_count=1 <= 5, no cross_phase_deps, no must_haves = score 1 = low
        assert_eq!(assess_risk(content), "low");
    }

    #[test]
    fn test_triple_hash_tasks() {
        let content = r#"---
title: "test"
---

### Task 1: A
**Files:** `a.rs`
### Task 2: B
**Files:** `b.rs`
### Task 3: C
**Files:** `c.rs`
### Task 4: D
**Files:** `d.rs`
### Task 5: E
**Files:** `e.rs`
### Task 6: F
**Files:** `f.rs`
"#;
        // task_count=6 > 5 (+1) = score 1 = low
        assert_eq!(assess_risk(content), "low");
    }

    #[test]
    fn test_execute_missing_args() {
        let args: Vec<String> = vec!["yolo".into(), "assess-risk".into()];
        let cwd = std::path::PathBuf::from(".");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(out.trim(), "medium");
        assert_eq!(code, 0);
    }

    #[test]
    fn test_execute_missing_file() {
        let args: Vec<String> = vec![
            "yolo".into(),
            "assess-risk".into(),
            "/nonexistent/plan.md".into(),
        ];
        let cwd = std::path::PathBuf::from(".");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(out.trim(), "medium");
        assert_eq!(code, 0);
    }
}
