use std::path::Path;

/// Unified verify dispatcher.
/// Usage: yolo verify <name>
/// Names: vibe, init-todo, bootstrap, pre-push
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 3 {
        return Err("Usage: yolo verify {vibe|init-todo|bootstrap|pre-push}".to_string());
    }

    let name = &args[2];

    match name.as_str() {
        "vibe" => super::verify_vibe::execute(args, cwd),
        "init-todo" => super::verify_init_todo::execute(args, cwd),
        "bootstrap" => super::verify_claude_bootstrap::execute(args, cwd),
        "pre-push" => super::pre_push_hook::execute(args, cwd),
        _ => Err(format!(
            "Unknown verify target: '{}'. Use: vibe, init-todo, bootstrap, pre-push",
            name
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_insufficient_args() {
        let args = vec!["yolo".to_string(), "verify".to_string()];
        let result = execute(&args, Path::new("/tmp"));
        assert!(result.is_err());
    }

    #[test]
    fn test_unknown_target() {
        let args = vec![
            "yolo".to_string(),
            "verify".to_string(),
            "unknown".to_string(),
        ];
        let result = execute(&args, Path::new("/tmp"));
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Unknown verify target"));
    }

    #[test]
    fn test_dispatch_routes() {
        // Verify that known names don't error on routing (they may fail on actual checks)
        let known = ["vibe", "init-todo", "bootstrap", "pre-push"];
        for name in &known {
            let args = vec![
                "yolo".to_string(),
                "verify".to_string(),
                name.to_string(),
            ];
            // Just check it doesn't return Err from routing
            // The actual verify functions may return Ok or Err depending on environment
            let _ = execute(&args, Path::new("/tmp"));
        }
    }
}
