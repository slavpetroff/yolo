use serde_json::json;
use std::path::Path;

/// Extract the latest version section from CHANGELOG.md.
///
/// Usage: yolo extract-changelog [changelog_path]
///
/// Returns JSON: {"ok":true,"cmd":"extract-changelog","delta":{"version","date","body","found"}}
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let changelog_path = if args.len() > 2 {
        Path::new(&args[2]).to_path_buf()
    } else {
        cwd.join("CHANGELOG.md")
    };

    if !changelog_path.exists() {
        let response = json!({
            "ok": true,
            "cmd": "extract-changelog",
            "delta": {
                "version": null,
                "date": null,
                "body": "",
                "found": false
            }
        });
        return Ok((response.to_string(), 0));
    }

    let content = std::fs::read_to_string(&changelog_path)
        .map_err(|e| format!("Failed to read {}: {}", changelog_path.display(), e))?;

    match extract_latest_section(&content) {
        Some((version, date, body)) => {
            let response = json!({
                "ok": true,
                "cmd": "extract-changelog",
                "delta": {
                    "version": version,
                    "date": date,
                    "body": body.trim(),
                    "found": true
                }
            });
            Ok((response.to_string(), 0))
        }
        None => {
            let response = json!({
                "ok": true,
                "cmd": "extract-changelog",
                "delta": {
                    "version": null,
                    "date": null,
                    "body": "",
                    "found": false
                }
            });
            Ok((response.to_string(), 0))
        }
    }
}

/// Parse the first `## v{VERSION}` or `## [{VERSION}]` section from changelog content.
/// Returns (version, optional_date, body).
fn extract_latest_section(content: &str) -> Option<(String, Option<String>, String)> {
    let mut version: Option<String> = None;
    let mut date: Option<String> = None;
    let mut body_lines: Vec<&str> = Vec::new();
    let mut in_section = false;

    for line in content.lines() {
        if line.starts_with("## ") {
            if in_section {
                // Hit the next section header — stop collecting
                break;
            }
            // Try to parse version from this header
            let header = &line[3..].trim();
            if let Some(parsed) = parse_version_header(header) {
                version = Some(parsed.0);
                date = parsed.1;
                in_section = true;
                continue;
            }
        } else if in_section {
            body_lines.push(line);
        }
    }

    version.map(|v| (v, date, body_lines.join("\n")))
}

/// Parse a version header like "v2.9.5 (2026-02-24)" or "[2.9.5] - 2026-02-24".
/// Returns (version_string, optional_date).
fn parse_version_header(header: &str) -> Option<(String, Option<String>)> {
    let header = header.trim();

    // Pattern 1: v{VERSION} (DATE) — e.g. "v2.9.5 (2026-02-24)"
    if header.starts_with('v') {
        let rest = &header[1..];
        let (ver, remainder) = split_at_non_version(rest);
        if !ver.is_empty() && ver.contains('.') {
            let d = extract_date(remainder);
            return Some((ver.to_string(), d));
        }
    }

    // Pattern 2: [{VERSION}] — e.g. "[2.9.5] - 2026-02-24"
    if header.starts_with('[') {
        if let Some(end) = header.find(']') {
            let ver = &header[1..end];
            if !ver.is_empty() && ver.contains('.') {
                let remainder = &header[end + 1..];
                let d = extract_date(remainder);
                return Some((ver.to_string(), d));
            }
        }
    }

    // Pattern 3: bare VERSION — e.g. "2.9.5 (2026-02-24)"
    let (ver, remainder) = split_at_non_version(header);
    if !ver.is_empty() && ver.contains('.') {
        let d = extract_date(remainder);
        return Some((ver.to_string(), d));
    }

    None
}

/// Split at the first character that isn't part of a version (not digit or dot).
fn split_at_non_version(s: &str) -> (&str, &str) {
    let end = s
        .find(|c: char| !c.is_ascii_digit() && c != '.')
        .unwrap_or(s.len());
    (&s[..end], &s[end..])
}

/// Try to extract a date from a remainder string like " (2026-02-24)" or " - 2026-02-24".
fn extract_date(s: &str) -> Option<String> {
    // Look for YYYY-MM-DD pattern
    let s = s.trim().trim_start_matches('-').trim().trim_start_matches('(').trim();
    if s.len() >= 10 {
        let candidate = &s[..10];
        if candidate.chars().filter(|&c| c == '-').count() == 2
            && candidate.chars().all(|c| c.is_ascii_digit() || c == '-')
        {
            return Some(candidate.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn s(v: &str) -> String {
        v.to_string()
    }

    #[test]
    fn test_extract_normal() {
        let dir = tempdir().unwrap();
        fs::write(
            dir.path().join("CHANGELOG.md"),
            "# Changelog\n\n## v2.9.5 (2026-02-24)\n\n### Added\n- Feature A\n- Feature B\n\n## v2.9.1 (2026-02-23)\n\n### Fixed\n- Bug X\n",
        )
        .unwrap();

        let (out, code) = execute(&[s("yolo"), s("extract-changelog")], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["delta"]["found"], true);
        assert_eq!(parsed["delta"]["version"], "2.9.5");
        assert_eq!(parsed["delta"]["date"], "2026-02-24");
        let body = parsed["delta"]["body"].as_str().unwrap();
        assert!(body.contains("Feature A"));
        assert!(body.contains("Feature B"));
        // Should NOT contain content from v2.9.1
        assert!(!body.contains("Bug X"));
    }

    #[test]
    fn test_extract_missing_file() {
        let dir = tempdir().unwrap();
        // No CHANGELOG.md
        let (out, code) = execute(&[s("yolo"), s("extract-changelog")], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["delta"]["found"], false);
        assert_eq!(parsed["delta"]["body"], "");
    }

    #[test]
    fn test_extract_empty_changelog() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("CHANGELOG.md"), "# Changelog\n\nNo releases yet.\n").unwrap();

        let (out, code) = execute(&[s("yolo"), s("extract-changelog")], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["delta"]["found"], false);
    }

    #[test]
    fn test_extract_with_date() {
        let dir = tempdir().unwrap();
        fs::write(
            dir.path().join("CHANGELOG.md"),
            "# Changelog\n\n## v1.0.0 (2026-01-15)\n\n### Initial\n- First release\n",
        )
        .unwrap();

        let (out, code) = execute(&[s("yolo"), s("extract-changelog")], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["delta"]["version"], "1.0.0");
        assert_eq!(parsed["delta"]["date"], "2026-01-15");
        assert_eq!(parsed["delta"]["found"], true);
    }

    #[test]
    fn test_extract_bracket_format() {
        let dir = tempdir().unwrap();
        fs::write(
            dir.path().join("CHANGELOG.md"),
            "# Changelog\n\n## [3.2.1] - 2026-02-20\n\n### Changed\n- Something\n",
        )
        .unwrap();

        let (out, code) = execute(&[s("yolo"), s("extract-changelog")], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["delta"]["version"], "3.2.1");
        assert_eq!(parsed["delta"]["date"], "2026-02-20");
        assert_eq!(parsed["delta"]["found"], true);
    }

    #[test]
    fn test_extract_custom_path() {
        let dir = tempdir().unwrap();
        let custom = dir.path().join("CHANGES.md");
        fs::write(&custom, "# Changes\n\n## v0.1.0\n\n- Init\n").unwrap();

        let (out, code) = execute(
            &[s("yolo"), s("extract-changelog"), custom.to_str().unwrap().to_string()],
            dir.path(),
        )
        .unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["delta"]["version"], "0.1.0");
        assert_eq!(parsed["delta"]["found"], true);
        assert!(parsed["delta"]["date"].is_null());
    }
}
