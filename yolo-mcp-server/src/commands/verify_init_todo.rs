use std::fs;
use std::path::Path;

/// Execute the init/todo contract verification.
/// Validates consistency across templates/STATE.md and commands/todo.md.
pub fn execute(_args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let mut output = String::new();
    let mut total_pass = 0u32;
    let mut total_fail = 0u32;

    let template_path = cwd.join("templates/STATE.md");
    let todo_cmd_path = cwd.join("commands/todo.md");

    output.push_str("=== Template + Command Contracts ===\n");

    // INIT-01: template has ## Todos section
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "INIT-01",
        "template has ## Todos section",
        file_has_line(&template_path, "## Todos"),
    );

    // INIT-02: template has no ### Pending Todos subsection (flat)
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "INIT-02",
        "template has no ### Pending Todos subsection (flat)",
        !file_has_line(&template_path, "### Pending Todos"),
    );

    // TODO-01: todo command anchors insertion on ## Todos
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "TODO-01",
        "todo command anchors insertion on ## Todos",
        file_contains(&todo_cmd_path, "## Todos"),
    );

    // TODO-02: todo command does not reference Pending Todos
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "TODO-02",
        "todo command does not reference Pending Todos",
        !file_contains(&todo_cmd_path, "Pending Todos"),
    );

    output.push_str("\n=== Bootstrap Output Contracts ===\n");

    // Bootstrap checks: run bootstrap_state to temp dir and verify output
    let temp_dir = std::env::temp_dir().join(format!(
        "yolo-init-todo-{}",
        std::process::id()
    ));
    let _ = fs::create_dir_all(&temp_dir);
    let bootstrap_state_path = temp_dir.join("STATE.md");

    let bootstrap_args = vec![
        "state".to_string(),
        bootstrap_state_path.to_string_lossy().to_string(),
        "Test Project".to_string(),
        "Test Milestone".to_string(),
        "2".to_string(),
    ];

    let boot_ok = super::bootstrap_state::execute(&bootstrap_args, cwd).is_ok();
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "BOOT-01",
        "bootstrap script executes",
        boot_ok,
    );

    // BOOT-02: bootstrap output has ## Todos section
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "BOOT-02",
        "bootstrap output has ## Todos section",
        file_has_line(&bootstrap_state_path, "## Todos"),
    );

    // BOOT-03: bootstrap output has no ### Pending Todos (flat)
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "BOOT-03",
        "bootstrap output has no ### Pending Todos (flat)",
        !file_has_line(&bootstrap_state_path, "### Pending Todos"),
    );

    // BOOT-04: bootstrap output initializes empty todo placeholder
    check(
        &mut output,
        &mut total_pass,
        &mut total_fail,
        "BOOT-04",
        "bootstrap output initializes empty todo placeholder",
        file_has_line(&bootstrap_state_path, "None."),
    );

    // Cleanup
    let _ = fs::remove_dir_all(&temp_dir);

    output.push_str("\n===============================\n");
    output.push_str(&format!("TOTAL: {total_pass} PASS, {total_fail} FAIL\n"));
    output.push_str("===============================\n");

    if total_fail == 0 {
        output.push_str("All init/todo contract checks passed.\n");
        Ok((output, 0))
    } else {
        output.push_str("Init/todo contract checks failed.\n");
        Ok((output, 1))
    }
}

fn check(
    output: &mut String,
    pass: &mut u32,
    fail: &mut u32,
    req: &str,
    desc: &str,
    result: bool,
) {
    if result {
        output.push_str(&format!("PASS  {req}: {desc}\n"));
        *pass += 1;
    } else {
        output.push_str(&format!("FAIL  {req}: {desc}\n"));
        *fail += 1;
    }
}

fn file_has_line(path: &Path, line_content: &str) -> bool {
    if let Ok(content) = fs::read_to_string(path) {
        content
            .lines()
            .any(|line| line.trim() == line_content)
    } else {
        false
    }
}

fn file_contains(path: &Path, pattern: &str) -> bool {
    if let Ok(content) = fs::read_to_string(path) {
        content.contains(pattern)
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_file_has_line() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("test.md");
        fs::write(&file, "## Todos\nSome content\n### Other\n").unwrap();

        assert!(file_has_line(&file, "## Todos"));
        assert!(!file_has_line(&file, "## Missing"));
        assert!(file_has_line(&file, "Some content"));
    }

    #[test]
    fn test_file_contains() {
        let dir = tempdir().unwrap();
        let file = dir.path().join("test.md");
        fs::write(&file, "Find `## Todos` and insert").unwrap();

        assert!(file_contains(&file, "## Todos"));
        assert!(!file_contains(&file, "Missing Pattern"));
    }

    #[test]
    fn test_file_has_line_missing_file() {
        assert!(!file_has_line(Path::new("/nonexistent"), "test"));
    }

    #[test]
    fn test_check_pass() {
        let mut output = String::new();
        let mut pass = 0;
        let mut fail = 0;
        check(&mut output, &mut pass, &mut fail, "TEST-01", "test check", true);
        assert_eq!(pass, 1);
        assert_eq!(fail, 0);
        assert!(output.contains("PASS"));
    }

    #[test]
    fn test_check_fail() {
        let mut output = String::new();
        let mut pass = 0;
        let mut fail = 0;
        check(&mut output, &mut pass, &mut fail, "TEST-01", "test check", false);
        assert_eq!(pass, 0);
        assert_eq!(fail, 1);
        assert!(output.contains("FAIL"));
    }
}
