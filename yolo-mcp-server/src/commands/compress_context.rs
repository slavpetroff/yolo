use std::path::Path;
use super::tier_context::minify_markdown;

/// Finds `.context-*.md` files in a directory, applies markdown minification,
/// and reports per-file savings. With `--analyze-only`, files are not modified.
///
/// Usage: yolo compress-context [--analyze-only] [--phase-dir <path>]
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let analyze_only = args.iter().any(|a| a == "--analyze-only");

    // Determine phase directory
    let phase_dir = args.iter()
        .position(|a| a == "--phase-dir")
        .and_then(|i| args.get(i + 1))
        .map(|p| {
            let path = Path::new(p);
            if path.is_absolute() { path.to_path_buf() } else { cwd.join(p) }
        })
        .unwrap_or_else(|| cwd.join(".yolo-planning/phases"));

    if !phase_dir.is_dir() {
        return Ok((
            serde_json::json!({
                "ok": false,
                "cmd": "compress-context",
                "error": format!("Phase directory not found: {}", phase_dir.display())
            }).to_string(),
            1,
        ));
    }

    // Find all .context-*.md files
    let entries = std::fs::read_dir(&phase_dir).map_err(|e| e.to_string())?;
    let mut files_report = Vec::new();
    let mut total_original: usize = 0;
    let mut total_minified: usize = 0;

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.starts_with(".context-") && name_str.ends_with(".md") {
            let path = entry.path();
            let content = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
            let original_bytes = content.len();
            let minified = minify_markdown(&content);
            let minified_bytes = minified.len();
            let savings_bytes = original_bytes.saturating_sub(minified_bytes);
            let savings_pct = if original_bytes > 0 {
                (savings_bytes as f64 / original_bytes as f64) * 100.0
            } else {
                0.0
            };

            total_original += original_bytes;
            total_minified += minified_bytes;

            files_report.push(serde_json::json!({
                "file": name_str.to_string(),
                "original_bytes": original_bytes,
                "original_tokens_est": original_bytes / 4,
                "minified_bytes": minified_bytes,
                "savings_bytes": savings_bytes,
                "savings_pct": format!("{:.1}%", savings_pct)
            }));

            // Write back minified content unless analyze-only
            if !analyze_only {
                std::fs::write(&path, &minified).map_err(|e| e.to_string())?;
            }
        }
    }

    let total_savings = total_original.saturating_sub(total_minified);
    let total_pct = if total_original > 0 {
        (total_savings as f64 / total_original as f64) * 100.0
    } else {
        0.0
    };

    let result = serde_json::json!({
        "ok": true,
        "cmd": "compress-context",
        "analyze_only": analyze_only,
        "files": files_report,
        "total_original_bytes": total_original,
        "total_minified_bytes": total_minified,
        "total_savings_bytes": total_savings,
        "total_savings_pct": format!("{:.1}%", total_pct)
    });

    Ok((result.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_compress_context_analyze_only() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        fs::create_dir_all(&phases).unwrap();

        // Write a context file with excessive whitespace
        let content = "--- TIER 1: SHARED BASE ---\n\n\n\nSome content\n\n\n\nMore content\n---\nEnd\n";
        fs::write(phases.join(".context-dev.md"), content).unwrap();

        let args = vec![
            "yolo".to_string(),
            "compress-context".to_string(),
            "--analyze-only".to_string(),
            "--phase-dir".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["analyze_only"], true);
        assert!(json["total_savings_bytes"].as_u64().unwrap() > 0);

        // File should be unchanged (analyze-only)
        let after = fs::read_to_string(phases.join(".context-dev.md")).unwrap();
        assert_eq!(after, content);
    }

    #[test]
    fn test_compress_context_writes_files() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let phases = tmp.path().join("phases");
        fs::create_dir_all(&phases).unwrap();

        let content = "Header\n\n\n\n\nBody\n---\nEnd\n";
        fs::write(phases.join(".context-lead.md"), content).unwrap();

        let args = vec![
            "yolo".to_string(),
            "compress-context".to_string(),
            "--phase-dir".to_string(),
            phases.to_string_lossy().to_string(),
        ];
        let (output, code) = execute(&args, tmp.path()).unwrap();
        assert_eq!(code, 0);

        let json: serde_json::Value = serde_json::from_str(&output).unwrap();
        assert_eq!(json["ok"], true);
        assert_eq!(json["analyze_only"], false);

        // File should be modified (minified)
        let after = fs::read_to_string(phases.join(".context-lead.md")).unwrap();
        assert!(after.len() < content.len());
        // Bare separator removed, empty lines collapsed
        assert!(!after.contains("\n\n\n"));
    }
}
