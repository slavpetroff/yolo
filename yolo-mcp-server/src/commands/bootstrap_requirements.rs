use std::fs;
use std::path::Path;
use std::time::Instant;
use chrono::Local;

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    // args: ["requirements", OUTPUT_PATH, DISCOVERY_JSON_PATH, [RESEARCH_FILE]]
    if args.len() < 3 {
        let response = serde_json::json!({
            "ok": false,
            "cmd": "bootstrap-requirements",
            "error": "Usage: yolo bootstrap requirements <output_path> <discovery_json_path> [research_file]",
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let output_path = Path::new(&args[1]);
    let discovery_path = Path::new(&args[2]);
    let research_file = if args.len() > 3 { Some(args[3].as_str()) } else { None };

    if !discovery_path.exists() {
        return Err(format!("Error: Discovery file not found: {}", discovery_path.display()));
    }

    let discovery_content = fs::read_to_string(discovery_path)
        .map_err(|e| format!("Failed to read discovery: {}", e))?;
    let mut discovery: serde_json::Value = serde_json::from_str(&discovery_content)
        .map_err(|_| format!("Error: Invalid JSON in {}", discovery_path.display()))?;

    let created = Local::now().format("%Y-%m-%d").to_string();

    // Ensure parent directory exists
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
    }

    // Extract inferred requirements
    let inferred = discovery.get("inferred").and_then(|v| v.as_array());
    let inferred_count = inferred.map(|a| a.len()).unwrap_or(0);

    let mut out = String::new();
    out.push_str("# Requirements\n\n");
    out.push_str(&format!("Defined: {}\n\n", created));
    out.push_str("## Requirements\n\n");

    if inferred_count > 0 {
        let arr = inferred.unwrap();
        for (i, item) in arr.iter().enumerate() {
            let req_id = format!("REQ-{:02}", i + 1);
            let req_text = item.get("text").and_then(|v| v.as_str())
                .or_else(|| item.as_str())
                .unwrap_or("");
            let req_priority = item.get("priority").and_then(|v| v.as_str())
                .unwrap_or("Must-have");

            out.push_str(&format!("### {}: {}\n", req_id, req_text));
            out.push_str(&format!("**{}**\n\n", req_priority));
        }
    } else {
        out.push_str("_(No requirements defined yet)_\n\n");
    }

    out.push_str("## Out of Scope\n\n");
    out.push_str("_(To be defined)_\n\n");

    fs::write(output_path, &out)
        .map_err(|e| format!("Failed to write {}: {}", output_path.display(), e))?;

    // Update discovery.json with research metadata
    let research_available = research_file
        .map(|f| Path::new(f).exists())
        .unwrap_or(false);

    if research_available {
        // Extract domain from answered[] scope category
        let domain = discovery.get("answered")
            .and_then(|v| v.as_array())
            .and_then(|arr| {
                arr.iter().find(|item| {
                    item.get("category").and_then(|c| c.as_str()) == Some("scope")
                })
            })
            .and_then(|item| item.get("answer").and_then(|a| a.as_str()))
            .and_then(|answer| answer.split_whitespace().next())
            .unwrap_or("")
            .to_string();

        let date = Local::now().format("%Y-%m-%d").to_string();
        discovery["research_summary"] = serde_json::json!({
            "available": true,
            "domain": domain,
            "date": date,
            "key_findings": []
        });
    } else {
        discovery["research_summary"] = serde_json::json!({"available": false});
    }

    let updated_json = serde_json::to_string_pretty(&discovery)
        .map_err(|e| format!("Failed to serialize discovery: {}", e))?;
    fs::write(discovery_path, updated_json)
        .map_err(|e| format!("Failed to update discovery: {}", e))?;

    let response = serde_json::json!({
        "ok": true,
        "cmd": "bootstrap-requirements",
        "changed": [output_path.to_string_lossy(), discovery_path.to_string_lossy()],
        "delta": {
            "requirement_count": inferred_count,
            "research_available": research_available,
            "discovery_updated": true
        },
        "elapsed_ms": start.elapsed().as_millis() as u64
    });
    Ok((response.to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_with_inferred_requirements() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");

        fs::write(&discovery, r#"{
            "answered": [],
            "inferred": [
                {"text": "User authentication", "priority": "Must-have"},
                {"text": "Data export", "priority": "Nice-to-have"}
            ]
        }"#).unwrap();

        let (_, code) = execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("### REQ-01: User authentication"));
        assert!(content.contains("**Must-have**"));
        assert!(content.contains("### REQ-02: Data export"));
        assert!(content.contains("**Nice-to-have**"));
    }

    #[test]
    fn test_empty_inferred() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");

        fs::write(&discovery, r#"{"answered": [], "inferred": []}"#).unwrap();

        execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("_(No requirements defined yet)_"));
    }

    #[test]
    fn test_with_research_file() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");
        let research = dir.path().join("research.md");

        fs::write(&discovery, r#"{
            "answered": [{"category": "scope", "answer": "FinTech payments processing"}],
            "inferred": [{"text": "Payment API", "priority": "Must-have"}]
        }"#).unwrap();
        fs::write(&research, "# Research\nSome findings").unwrap();

        execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string(), research.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();

        let updated: serde_json::Value = serde_json::from_str(&fs::read_to_string(&discovery).unwrap()).unwrap();
        assert_eq!(updated["research_summary"]["available"], true);
        assert_eq!(updated["research_summary"]["domain"], "FinTech");
    }

    #[test]
    fn test_invalid_json_error() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");

        fs::write(&discovery, "not valid json").unwrap();

        let result = execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid JSON"));
    }

    #[test]
    fn test_missing_discovery_file() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["requirements".into(), "/tmp/out.md".into(), "/nonexistent/discovery.json".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    #[test]
    fn test_no_research_sets_unavailable() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");

        fs::write(&discovery, r#"{"answered": [], "inferred": []}"#).unwrap();

        execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();

        let updated: serde_json::Value = serde_json::from_str(&fs::read_to_string(&discovery).unwrap()).unwrap();
        assert_eq!(updated["research_summary"]["available"], false);
    }

    #[test]
    fn test_string_inferred_items() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("REQUIREMENTS.md");
        let discovery = dir.path().join("discovery.json");

        fs::write(&discovery, r#"{"answered": [], "inferred": ["Simple string requirement"]}"#).unwrap();

        execute(
            &["requirements".into(), output.to_string_lossy().to_string(), discovery.to_string_lossy().to_string()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("### REQ-01: Simple string requirement"));
        assert!(content.contains("**Must-have**"));
    }
}
