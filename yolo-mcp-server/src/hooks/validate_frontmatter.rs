use serde_json::{json, Value};
use std::fs;

/// PostToolUse handler that validates YAML frontmatter `description:` field in .md files.
/// Non-blocking: always returns exit code 0.
///
/// Checks:
/// 1. File is .md
/// 2. Starts with `---` (has frontmatter)
/// 3. Has `description:` field
/// 4. Description is not empty
/// 5. Description is not multi-line (block scalar `|`/`>` or continuation lines)
pub fn validate_frontmatter(input: &Value) -> (Value, i32) {
    let file_path = extract_file_path(input);

    // Only check .md files
    if !file_path.ends_with(".md") {
        return (Value::Null, 0);
    }

    let content = match fs::read_to_string(&file_path) {
        Ok(c) => c,
        Err(_) => return (Value::Null, 0),
    };

    match check_frontmatter_description(&content) {
        FrontmatterResult::Ok | FrontmatterResult::Skip => (Value::Null, 0),
        FrontmatterResult::MultiLine => {
            let output = json!({
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": format!(
                        "Frontmatter warning: description field in {} must be a single line. \
                         Multi-line descriptions break plugin command/skill discovery. Fix: collapse to one line.",
                        file_path
                    )
                }
            });
            (output, 0)
        }
        FrontmatterResult::Empty => {
            let output = json!({
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": format!(
                        "Frontmatter warning: description field in {} is empty. \
                         Empty descriptions break plugin command/skill discovery. Fix: add a single-line description.",
                        file_path
                    )
                }
            });
            (output, 0)
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum FrontmatterResult {
    Ok,
    Skip,
    MultiLine,
    Empty,
}

fn extract_file_path(input: &Value) -> String {
    input
        .get("tool_input")
        .and_then(|ti| ti.get("file_path").and_then(|v| v.as_str()))
        .unwrap_or("")
        .to_string()
}

/// Extract frontmatter block between first and second `---` lines.
pub fn extract_frontmatter(content: &str) -> Option<String> {
    let mut lines = content.lines();

    // First line must be `---`
    if lines.next() != Some("---") {
        return None;
    }

    let mut fm_lines = Vec::new();
    for line in lines {
        if line == "---" {
            break;
        }
        fm_lines.push(line);
    }

    if fm_lines.is_empty() {
        return None;
    }

    Some(fm_lines.join("\n"))
}

/// Check the description field in frontmatter content.
pub fn check_frontmatter_description(content: &str) -> FrontmatterResult {
    let frontmatter = match extract_frontmatter(content) {
        Some(fm) => fm,
        None => return FrontmatterResult::Skip,
    };

    // Find description: line
    let mut found_desc = false;
    let mut desc_value = String::new();
    let mut has_continuation = false;

    for line in frontmatter.lines() {
        if found_desc {
            // Check for indented continuation lines
            if line.starts_with(' ') || line.starts_with('\t') {
                has_continuation = true;
            } else {
                break;
            }
        } else if line.starts_with("description:") {
            found_desc = true;
            desc_value = line
                .strip_prefix("description:")
                .unwrap_or("")
                .trim()
                .to_string();
        }
    }

    if !found_desc {
        return FrontmatterResult::Skip;
    }

    // Check for block scalar indicators (| or >)
    if desc_value.starts_with('|') || desc_value.starts_with('>') {
        return FrontmatterResult::MultiLine;
    }

    // Empty description value
    if desc_value.is_empty() {
        if has_continuation {
            return FrontmatterResult::MultiLine;
        }
        return FrontmatterResult::Empty;
    }

    // Non-empty but has continuation lines
    if has_continuation {
        return FrontmatterResult::MultiLine;
    }

    FrontmatterResult::Ok
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_single_line_description() {
        let content = "---\ntitle: Test\ndescription: A single line\n---\n# Body";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::Ok
        );
    }

    #[test]
    fn test_block_scalar_pipe() {
        let content = "---\ntitle: Test\ndescription: |\n  line1\n  line2\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::MultiLine
        );
    }

    #[test]
    fn test_block_scalar_gt() {
        let content = "---\ntitle: Test\ndescription: >\n  line1\n  line2\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::MultiLine
        );
    }

    #[test]
    fn test_empty_description() {
        let content = "---\ntitle: Test\ndescription:\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::Empty
        );
    }

    #[test]
    fn test_empty_with_continuation() {
        let content = "---\ntitle: Test\ndescription:\n  continued line\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::MultiLine
        );
    }

    #[test]
    fn test_multiline_continuation() {
        let content = "---\ntitle: Test\ndescription: first\n  continued\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::MultiLine
        );
    }

    #[test]
    fn test_no_frontmatter() {
        let content = "# Just a heading\nSome text";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::Skip
        );
    }

    #[test]
    fn test_no_description_field() {
        let content = "---\ntitle: Test\nauthor: Someone\n---\n";
        assert_eq!(
            check_frontmatter_description(content),
            FrontmatterResult::Skip
        );
    }

    #[test]
    fn test_non_md_file_skipped() {
        let input = json!({"tool_input": {"file_path": "/foo/bar.rs"}});
        let (output, code) = validate_frontmatter(&input);
        assert_eq!(code, 0);
        assert_eq!(output, Value::Null);
    }

    #[test]
    fn test_extract_frontmatter_basic() {
        let content = "---\nfoo: bar\nbaz: qux\n---\nbody";
        let fm = extract_frontmatter(content).unwrap();
        assert_eq!(fm, "foo: bar\nbaz: qux");
    }

    #[test]
    fn test_extract_frontmatter_none() {
        let content = "no frontmatter here";
        assert!(extract_frontmatter(content).is_none());
    }

    #[test]
    fn test_validate_frontmatter_with_real_file() {
        let dir = tempfile::tempdir().unwrap();
        let md_path = dir.path().join("test.md");
        std::fs::write(&md_path, "---\ndescription: |\n  multi\n---\n").unwrap();

        let input = json!({"tool_input": {"file_path": md_path.to_str().unwrap()}});
        let (output, code) = validate_frontmatter(&input);
        assert_eq!(code, 0);
        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("must be a single line"));
    }

    #[test]
    fn test_validate_frontmatter_empty_real_file() {
        let dir = tempfile::tempdir().unwrap();
        let md_path = dir.path().join("test.md");
        std::fs::write(&md_path, "---\ndescription:\n---\n").unwrap();

        let input = json!({"tool_input": {"file_path": md_path.to_str().unwrap()}});
        let (output, code) = validate_frontmatter(&input);
        assert_eq!(code, 0);
        let ctx = output["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap();
        assert!(ctx.contains("is empty"));
    }
}
