use std::fs;
use std::path::Path;
use std::time::Instant;
use serde_json::json;

/// Parse YAML frontmatter from a markdown file and return all key-value pairs as JSON.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();

    if args.len() < 3 {
        return Err(r#"{"error":"Usage: yolo parse-frontmatter <file_path>"}"#.to_string());
    }

    let file_path_str = &args[2];
    let file_path = Path::new(file_path_str);
    let resolved = if file_path.is_absolute() {
        file_path.to_path_buf()
    } else {
        cwd.join(file_path)
    };

    if !resolved.exists() {
        let out = json!({"error": format!("file not found: {}", file_path_str)});
        return Ok((serde_json::to_string(&out).unwrap() + "\n", 1));
    }

    let content = fs::read_to_string(&resolved)
        .map_err(|e| format!("{{\"error\":\"failed to read file: {}\"}}", e))?;

    let frontmatter = parse_frontmatter_content(&content);
    let has_frontmatter = frontmatter.is_some();
    let fm_value = frontmatter.unwrap_or_else(|| serde_json::Map::new());

    let elapsed = start.elapsed().as_millis();
    let out = json!({
        "ok": true,
        "cmd": "parse-frontmatter",
        "frontmatter": fm_value,
        "has_frontmatter": has_frontmatter,
        "elapsed_ms": elapsed
    });

    Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
}

/// Parse frontmatter from raw content string. Returns None if no frontmatter block found.
fn parse_frontmatter_content(content: &str) -> Option<serde_json::Map<String, serde_json::Value>> {
    let mut lines = content.lines();

    // First line must be "---"
    let first = lines.next()?;
    if first.trim() != "---" {
        return None;
    }

    let mut map = serde_json::Map::new();
    let mut current_key: Option<String> = None;
    let mut current_list: Vec<serde_json::Value> = Vec::new();
    let mut found_end = false;

    for line in lines {
        if line.trim() == "---" {
            // Flush any pending list
            if let Some(key) = current_key.take() {
                if !current_list.is_empty() {
                    map.insert(key, serde_json::Value::Array(current_list.drain(..).collect()));
                }
            }
            found_end = true;
            break;
        }

        // Check for list item (  - "value" or  - value)
        let trimmed = line.trim();
        if trimmed.starts_with("- ") {
            if current_key.is_some() {
                let item = trimmed.strip_prefix("- ").unwrap().trim();
                let item = item.trim_matches('"').trim_matches('\'');
                current_list.push(serde_json::Value::String(item.to_string()));
            }
            continue;
        }

        // Key-value line
        if let Some((key_part, val_part)) = line.split_once(':') {
            // Flush any pending list
            if let Some(key) = current_key.take() {
                if !current_list.is_empty() {
                    map.insert(key, serde_json::Value::Array(current_list.drain(..).collect()));
                }
            }

            let key = key_part.trim().to_string();
            let val_raw = val_part.trim();

            if val_raw.is_empty() {
                // Multi-line value (list) coming next
                current_key = Some(key);
                current_list.clear();
            } else if let Some(inner) = val_raw.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
                // Inline array: key: [a, b, c]
                let items: Vec<serde_json::Value> = inner
                    .split(',')
                    .map(|s| {
                        let s = s.trim().trim_matches('"').trim_matches('\'');
                        serde_json::Value::String(s.to_string())
                    })
                    .collect();
                map.insert(key, serde_json::Value::Array(items));
            } else {
                // Simple scalar value
                let val = val_raw.trim_matches('"').trim_matches('\'');
                map.insert(key, serde_json::Value::String(val.to_string()));
            }
        }
    }

    if !found_end {
        // No closing --- found
        return None;
    }

    Some(map)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_standard_frontmatter() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("test.md");
        fs::write(&file, "---\nphase: \"01\"\nplan: \"02\"\ntitle: \"Test Plan\"\n---\n# Body\n").unwrap();

        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), file.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["has_frontmatter"], true);
        assert_eq!(parsed["frontmatter"]["phase"], "01");
        assert_eq!(parsed["frontmatter"]["plan"], "02");
        assert_eq!(parsed["frontmatter"]["title"], "Test Plan");
    }

    #[test]
    fn test_no_frontmatter() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("plain.md");
        fs::write(&file, "# Just a heading\nSome text.\n").unwrap();

        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), file.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["has_frontmatter"], false);
        assert!(parsed["frontmatter"].as_object().unwrap().is_empty());
    }

    #[test]
    fn test_array_values() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("array.md");
        fs::write(&file, "---\nmust_haves:\n  - \"item1\"\n  - \"item2\"\n  - \"item3\"\n---\n").unwrap();

        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), file.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        let arr = parsed["frontmatter"]["must_haves"].as_array().unwrap();
        assert_eq!(arr.len(), 3);
        assert_eq!(arr[0], "item1");
        assert_eq!(arr[1], "item2");
        assert_eq!(arr[2], "item3");
    }

    #[test]
    fn test_missing_file() {
        let dir = tempdir().unwrap();
        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), "/nonexistent/file.md".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 1);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(parsed["error"].as_str().unwrap().contains("file not found"));
    }

    #[test]
    fn test_empty_frontmatter() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("empty.md");
        fs::write(&file, "---\n---\n# Content\n").unwrap();

        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), file.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["has_frontmatter"], true);
        assert!(parsed["frontmatter"].as_object().unwrap().is_empty());
    }

    #[test]
    fn test_inline_array() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("inline.md");
        fs::write(&file, "---\ndepends_on: [01, 02]\ntitle: \"test\"\n---\n").unwrap();

        let (out, code) = execute(
            &["yolo".into(), "parse-frontmatter".into(), file.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        let arr = parsed["frontmatter"]["depends_on"].as_array().unwrap();
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0], "01");
        assert_eq!(arr[1], "02");
    }
}
