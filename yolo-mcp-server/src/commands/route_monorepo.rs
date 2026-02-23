use serde_json::json;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

const PACKAGE_MARKERS: &[&str] = &["package.json", "Cargo.toml", "go.mod", "pyproject.toml"];
const SKIP_DIRS: &[&str] = &["node_modules", ".git", ".yolo-planning", ".planning", "target"];
const MAX_DEPTH: usize = 4;

/// Detect monorepo structure and output relevant package paths for a phase.
/// Scans *-PLAN.md Files: entries, maps file paths to package roots.
/// Output: JSON array of relevant package paths.
/// Fail-open: exit 0 always, outputs "[]" on error.
pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    // args: ["yolo", "route-monorepo", "<phase-dir>"]
    if args.len() < 3 {
        return Ok(("[]\n".to_string(), 0));
    }

    let phase_dir_str = &args[2];
    let phase_dir = if Path::new(phase_dir_str).is_absolute() {
        std::path::PathBuf::from(phase_dir_str)
    } else {
        cwd.join(phase_dir_str)
    };

    let planning_dir = cwd.join(".yolo-planning");
    let config_path = planning_dir.join("config.json");

    // Check feature flag
    if !read_bool_flag(&config_path, "v3_monorepo_routing") {
        return Ok(("[]\n".to_string(), 0));
    }

    if !phase_dir.is_dir() {
        return Ok(("[]\n".to_string(), 0));
    }

    let result = route_monorepo(cwd, &phase_dir);
    let json_arr: Vec<serde_json::Value> = result.into_iter().map(|s| json!(s)).collect();
    Ok((format!("{}\n", serde_json::to_string(&json_arr).unwrap_or_else(|_| "[]".to_string())), 0))
}

/// Core monorepo routing: find package roots, extract plan files, match them.
pub fn route_monorepo(cwd: &Path, phase_dir: &Path) -> Vec<String> {
    // Step 1: Detect package roots (sub-packages, not root-level)
    let package_roots = find_package_roots(cwd);
    if package_roots.is_empty() {
        return vec![];
    }

    // Step 2: Extract file paths from *-PLAN.md files in phase_dir
    let plan_files = extract_plan_file_paths(phase_dir);
    if plan_files.is_empty() {
        return vec![];
    }

    // Step 3: Match plan files to package roots
    let mut relevant: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();

    for plan_file in &plan_files {
        for root in &package_roots {
            if plan_file.starts_with(&format!("{}/", root)) && !seen.contains(root) {
                seen.insert(root.clone());
                relevant.push(root.clone());
            }
        }
    }

    relevant
}

/// Recursively find package marker files up to MAX_DEPTH, skipping root-level.
fn find_package_roots(cwd: &Path) -> Vec<String> {
    let mut roots: HashSet<String> = HashSet::new();
    scan_dir_for_markers(cwd, cwd, 0, &mut roots);
    let mut result: Vec<String> = roots.into_iter().collect();
    result.sort();
    result
}

fn scan_dir_for_markers(base: &Path, dir: &Path, depth: usize, roots: &mut HashSet<String>) {
    if depth > MAX_DEPTH {
        return;
    }

    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy();

        if path.is_dir() {
            if SKIP_DIRS.contains(&name.as_ref()) {
                continue;
            }
            scan_dir_for_markers(base, &path, depth + 1, roots);
        } else if path.is_file() && PACKAGE_MARKERS.contains(&name.as_ref()) {
            // Skip root-level markers (depth 0 means marker is at cwd itself)
            if depth > 0
                && let Ok(relative) = dir.strip_prefix(base)
            {
                let rel_str = relative.to_string_lossy().to_string();
                if !rel_str.is_empty() {
                    roots.insert(rel_str);
                }
            }
        }
    }
}

/// Extract file paths from **Files:** lines in *-PLAN.md files.
fn extract_plan_file_paths(phase_dir: &Path) -> Vec<String> {
    let mut files: Vec<String> = Vec::new();

    let entries = match fs::read_dir(phase_dir) {
        Ok(e) => e,
        Err(_) => return files,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.ends_with("-PLAN.md") {
            continue;
        }
        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        for line in content.lines() {
            if let Some(after) = extract_files_line(line) {
                for part in after.split(',') {
                    let trimmed = part
                        .trim()
                        .trim_start_matches('`')
                        .trim_end_matches('`')
                        .trim();
                    // Remove annotations like "(new)", "(append tests)"
                    let path_str = if let Some(paren_pos) = trimmed.find('(') {
                        trimmed[..paren_pos].trim()
                    } else {
                        trimmed
                    };
                    if !path_str.is_empty() {
                        files.push(path_str.to_string());
                    }
                }
            }
        }
    }

    files
}

/// Extract the file list portion from a **Files:** markdown line.
fn extract_files_line(line: &str) -> Option<&str> {
    // Match both "**Files:** ..." and "- **Files:** ..."
    let trimmed = line.trim().trim_start_matches("- ");
    if let Some(rest) = trimmed.strip_prefix("**Files:**") {
        Some(rest.trim())
    } else {
        None
    }
}

/// Read a boolean flag from config.json. Returns false on any error.
fn read_bool_flag(config_path: &Path, key: &str) -> bool {
    let content = match fs::read_to_string(config_path) {
        Ok(c) => c,
        Err(_) => return false,
    };
    let config: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };
    config.get(key).and_then(|v| v.as_bool()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn create_test_dir() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    #[test]
    fn test_no_feature_flag() {
        let args: Vec<String> = vec!["yolo".into(), "route-monorepo".into(), "/tmp".into()];
        let cwd = std::path::PathBuf::from("/tmp/nonexistent-monorepo-test");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(code, 0);
        assert_eq!(out.trim(), "[]");
    }

    #[test]
    fn test_extract_files_line_basic() {
        assert_eq!(
            extract_files_line("**Files:** `src/main.rs`, `src/lib.rs`"),
            Some("`src/main.rs`, `src/lib.rs`")
        );
    }

    #[test]
    fn test_extract_files_line_with_dash() {
        assert_eq!(
            extract_files_line("- **Files:** `a.rs`"),
            Some("`a.rs`")
        );
    }

    #[test]
    fn test_extract_files_line_no_match() {
        assert_eq!(extract_files_line("Some other line"), None);
    }

    #[test]
    fn test_find_package_roots_with_nested_packages() {
        let tmp = create_test_dir();
        let base = tmp.path();

        // Root-level marker (should be skipped)
        fs::write(base.join("package.json"), "{}").unwrap();

        // Nested package (should be found)
        let pkg = base.join("packages").join("core");
        fs::create_dir_all(&pkg).unwrap();
        fs::write(pkg.join("package.json"), "{}").unwrap();

        let backend = base.join("backend");
        fs::create_dir_all(&backend).unwrap();
        fs::write(backend.join("Cargo.toml"), "[package]").unwrap();

        let roots = find_package_roots(base);
        assert!(roots.contains(&"packages/core".to_string()));
        assert!(roots.contains(&"backend".to_string()));
        assert_eq!(roots.len(), 2);
    }

    #[test]
    fn test_find_package_roots_skips_node_modules() {
        let tmp = create_test_dir();
        let base = tmp.path();

        let nm = base.join("node_modules").join("pkg");
        fs::create_dir_all(&nm).unwrap();
        fs::write(nm.join("package.json"), "{}").unwrap();

        let roots = find_package_roots(base);
        assert!(roots.is_empty());
    }

    #[test]
    fn test_route_monorepo_matches_plan_to_packages() {
        let tmp = create_test_dir();
        let base = tmp.path();

        // Create package roots
        let pkg_core = base.join("packages").join("core");
        fs::create_dir_all(&pkg_core).unwrap();
        fs::write(pkg_core.join("package.json"), "{}").unwrap();

        let pkg_web = base.join("apps").join("web");
        fs::create_dir_all(&pkg_web).unwrap();
        fs::write(pkg_web.join("package.json"), "{}").unwrap();

        // Create phase dir with plan file
        let phase_dir = base.join("phase-01");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(
            phase_dir.join("01-PLAN.md"),
            "## Task 1\n**Files:** `packages/core/src/index.ts`, `apps/web/src/app.ts`\n",
        )
        .unwrap();

        let result = route_monorepo(base, &phase_dir);
        assert!(result.contains(&"packages/core".to_string()));
        assert!(result.contains(&"apps/web".to_string()));
    }

    #[test]
    fn test_route_monorepo_no_packages() {
        let tmp = create_test_dir();
        let base = tmp.path();

        let phase_dir = base.join("phase-01");
        fs::create_dir_all(&phase_dir).unwrap();
        fs::write(phase_dir.join("01-PLAN.md"), "## Task 1\n**Files:** `src/main.rs`\n").unwrap();

        let result = route_monorepo(base, &phase_dir);
        assert!(result.is_empty());
    }

    #[test]
    fn test_execute_missing_args() {
        let args: Vec<String> = vec!["yolo".into(), "route-monorepo".into()];
        let cwd = std::path::PathBuf::from(".");
        let (out, code) = execute(&args, &cwd).unwrap();
        assert_eq!(code, 0);
        assert_eq!(out.trim(), "[]");
    }
}
