use std::fs;
use std::path::Path;
use std::time::Instant;

pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let start = Instant::now();
    // args: ["project", OUTPUT_PATH, NAME, DESCRIPTION, [CORE_VALUE]]
    if args.len() < 4 {
        let response = serde_json::json!({
            "ok": false,
            "cmd": "bootstrap-project",
            "error": "Usage: yolo bootstrap project <output_path> <name> <description> [core_value]",
            "elapsed_ms": start.elapsed().as_millis() as u64
        });
        return Ok((response.to_string(), 1));
    }

    let output_path = Path::new(&args[1]);
    let name = &args[2];
    let description = &args[3];
    let core_value = if args.len() > 4 { &args[4] } else { description };

    // Ensure parent directory exists
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed to create directory: {}", e))?;
    }

    let content = format!(
        "# {name}\n\
         \n\
         {description}\n\
         \n\
         **Core value:** {core_value}\n\
         \n\
         ## Requirements\n\
         \n\
         ### Validated\n\
         \n\
         ### Active\n\
         \n\
         ### Out of Scope\n\
         \n\
         ## Constraints\n\
         - **Zero dependencies**: No package.json, npm, or build step\n\
         - **Bash + Markdown only**: All logic in shell scripts and markdown commands\n\
         \n\
         ## Key Decisions\n\
         \n\
         | Decision | Rationale | Outcome |\n\
         |----------|-----------|---------|\n",
        name = name,
        description = description,
        core_value = core_value,
    );

    let section_count = content.matches("\n## ").count();

    fs::write(output_path, &content)
        .map_err(|e| format!("Failed to write {}: {}", output_path.display(), e))?;

    let response = serde_json::json!({
        "ok": true,
        "cmd": "bootstrap-project",
        "changed": [output_path.to_string_lossy()],
        "delta": {
            "name": name,
            "description": description,
            "section_count": section_count,
            "has_requirements": true,
            "has_constraints": true
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
    fn test_basic_generation() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("PROJECT.md");

        let (_, code) = execute(
            &["project".into(), output.to_string_lossy().to_string(), "MyApp".into(), "A task manager".into()],
            dir.path(),
        ).unwrap();
        assert_eq!(code, 0);

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.starts_with("# MyApp\n"));
        assert!(content.contains("A task manager"));
        assert!(content.contains("**Core value:** A task manager"));
        assert!(content.contains("## Requirements"));
        assert!(content.contains("## Key Decisions"));
    }

    #[test]
    fn test_core_value_override() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("PROJECT.md");

        execute(
            &["project".into(), output.to_string_lossy().to_string(), "MyApp".into(), "A task manager".into(), "Simplify life".into()],
            dir.path(),
        ).unwrap();

        let content = fs::read_to_string(&output).unwrap();
        assert!(content.contains("**Core value:** Simplify life"));
    }

    #[test]
    fn test_missing_args() {
        let dir = tempdir().unwrap();
        let result = execute(
            &["project".into(), "/tmp/test.md".into()],
            dir.path(),
        );
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Usage:"));
    }

    #[test]
    fn test_creates_parent_dirs() {
        let dir = tempdir().unwrap();
        let output = dir.path().join("nested").join("deep").join("PROJECT.md");

        execute(
            &["project".into(), output.to_string_lossy().to_string(), "Test".into(), "Desc".into()],
            dir.path(),
        ).unwrap();

        assert!(output.exists());
    }
}
