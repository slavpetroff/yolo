use std::fs;
use std::path::Path;
use serde_json::json;

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let include_brownfield = args.iter().any(|a| a == "--brownfield");
    // Find first positional arg (non-flag) after "detect-stack"
    let project_dir = args.iter().skip(2).find(|a| !a.starts_with("--"))
        .map(|s| Path::new(s.as_str()))
        .unwrap_or(cwd);

    let mappings_path = project_dir.join("config").join("stack-mappings.json");
    if !mappings_path.exists() {
        return Err(r#"{"error":"stack-mappings.json not found"}"#.to_string());
    }

    // --- Collect installed skills ---
    let mut installed_global = String::new();
    let mut installed_project = String::new();
    let mut installed_agents = String::new();

    let home_dir_str = std::env::var("HOME").unwrap_or_else(|_| "".to_string());
    let home_dir = Path::new(&home_dir_str);
    
    // Global Claude skills (using standard path logic)
    let claude_global = home_dir.join(".claude").join("skills");
    if claude_global.exists() {
        if let Ok(entries) = fs::read_dir(&claude_global) {
            let mut skills = Vec::new();
            for e in entries.filter_map(|x| x.ok()) {
                if let Some(name) = e.file_name().to_str() {
                    skills.push(name.to_string());
                }
            }
            installed_global = skills.join(",");
        }
    }

    // Agent skills
    let agent_global = home_dir.join(".agents").join("skills");
    if agent_global.exists() {
        if let Ok(entries) = fs::read_dir(&agent_global) {
            let mut skills = Vec::new();
            for e in entries.filter_map(|x| x.ok()) {
                if let Some(name) = e.file_name().to_str() {
                    skills.push(name.to_string());
                }
            }
            installed_agents = skills.join(",");
        }
    }

    // Project skills
    let claude_project = project_dir.join(".claude").join("skills");
    if claude_project.exists() {
        if let Ok(entries) = fs::read_dir(&claude_project) {
            let mut skills = Vec::new();
            for e in entries.filter_map(|x| x.ok()) {
                if let Some(name) = e.file_name().to_str() {
                    skills.push(name.to_string());
                }
            }
            installed_project = skills.join(",");
        }
    }

    let mut all_installed = Vec::new();
    for s in installed_global.split(',') { if !s.is_empty() { all_installed.push(s.to_string()); } }
    for s in installed_project.split(',') { if !s.is_empty() { all_installed.push(s.to_string()); } }
    for s in installed_agents.split(',') { if !s.is_empty() { all_installed.push(s.to_string()); } }

    // --- Read manifest files ---
    fn read_manifest(filename: &str, project_dir: &Path) -> String {
        let mut content = String::new();
        
        let root_file = project_dir.join(filename);
        if root_file.exists() {
            if let Ok(c) = fs::read_to_string(&root_file) {
                content.push_str(&c);
                content.push('\n');
            }
        }

        // Basic directory traversal up to depth 3
        let dirs_to_search = ["packages", "apps", "src"];
        for dir_name in dirs_to_search {
            let search_dir = project_dir.join(dir_name);
            if search_dir.exists() && search_dir.is_dir() {
                if let Ok(entries) = fs::read_dir(&search_dir) {
                    for e in entries.filter_map(|x| x.ok()) {
                        let path = e.path();
                        if path.is_dir() {
                            let manifest = path.join(filename);
                            if manifest.exists() {
                                if let Ok(c) = fs::read_to_string(&manifest) {
                                    content.push_str(&c);
                                    content.push('\n');
                                }
                            }
                        }
                    }
                }
            }
        }
        content
    }

    let pkg_json = read_manifest("package.json", project_dir);
    let requirements_txt = read_manifest("requirements.txt", project_dir);
    let pyproject_toml = read_manifest("pyproject.toml", project_dir);
    let gemfile = read_manifest("Gemfile", project_dir);
    let cargo_toml = read_manifest("Cargo.toml", project_dir);
    let go_mod = read_manifest("go.mod", project_dir);
    let composer_json = read_manifest("composer.json", project_dir);
    let mix_exs = read_manifest("mix.exs", project_dir);
    let pom_xml = read_manifest("pom.xml", project_dir);
    let build_gradle = read_manifest("build.gradle", project_dir);

    /// Minimal glob match: supports `*.ext` and `prefix*` patterns.
    fn glob_matches(pattern: &str, name: &str) -> bool {
        if let Some(suffix) = pattern.strip_prefix('*') {
            // *.ext — match any name ending with suffix
            name.ends_with(suffix)
        } else if let Some(prefix) = pattern.strip_suffix('*') {
            // prefix* — match any name starting with prefix
            name.starts_with(prefix)
        } else if let Some(star_pos) = pattern.find('*') {
            // pre*suf — match prefix and suffix
            let prefix = &pattern[..star_pos];
            let suffix = &pattern[star_pos + 1..];
            name.starts_with(prefix) && name.ends_with(suffix) && name.len() >= prefix.len() + suffix.len()
        } else {
            pattern == name
        }
    }

    fn check_pattern(pattern: &str, project_dir: &Path, manifests: &[(&str, &str)]) -> bool {
        if pattern.contains(':') {
            let parts: Vec<&str> = pattern.splitn(2, ':').collect();
            let file = parts[0];
            let dep = parts[1];

            for (m_file, m_content) in manifests {
                if file == *m_file {
                    if file.ends_with(".json") {
                        if m_content.contains(&format!("\"{}\"", dep)) {
                            return true;
                        }
                    } else {
                        // Very naive word match for non-json
                        if m_content.to_lowercase().contains(&dep.to_lowercase()) {
                            return true;
                        }
                    }
                }
            }
            false
        } else if pattern.contains('*') {
            // Glob-style: scan directory entries for matching filenames
            fn scan_dir_glob(dir: &Path, pattern: &str, glob_fn: &dyn Fn(&str, &str) -> bool) -> bool {
                if let Ok(entries) = fs::read_dir(dir) {
                    for e in entries.filter_map(|x| x.ok()) {
                        if let Some(name) = e.file_name().to_str() {
                            if glob_fn(pattern, name) {
                                return true;
                            }
                        }
                    }
                }
                false
            }
            // Check project root
            if scan_dir_glob(project_dir, pattern, &glob_matches) {
                return true;
            }
            // Check subdirectories
            let dirs_to_search = ["packages", "apps", "src", "tests"];
            for dir_name in dirs_to_search {
                let search_dir = project_dir.join(dir_name);
                if search_dir.exists() && search_dir.is_dir() {
                    if scan_dir_glob(&search_dir, pattern, &glob_matches) {
                        return true;
                    }
                    // Check one level deeper
                    if let Ok(entries) = fs::read_dir(&search_dir) {
                        for e in entries.filter_map(|x| x.ok()) {
                            if e.path().is_dir() && scan_dir_glob(&e.path(), pattern, &glob_matches) {
                                return true;
                            }
                        }
                    }
                }
            }
            false
        } else {
            // File or directory pattern
            let path = project_dir.join(pattern);
            if path.exists() {
                return true;
            }
            // Check subdirectories
            let basename = Path::new(pattern).file_name().and_then(|n| n.to_str()).unwrap_or(pattern);
            let dirs_to_search = ["packages", "apps", "src", "tests"];
            for dir_name in dirs_to_search {
                let search_dir = project_dir.join(dir_name);
                if search_dir.exists() && search_dir.is_dir() {
                    if let Ok(entries) = fs::read_dir(&search_dir) {
                        for e in entries.filter_map(|x| x.ok()) {
                            if e.file_name().to_string_lossy() == basename {
                                return true;
                            }
                            if e.path().is_dir() {
                                let nested = e.path().join(basename);
                                if nested.exists() {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
            false
        }
    }

    let manifests = vec![
        ("package.json", pkg_json.as_str()),
        ("requirements.txt", requirements_txt.as_str()),
        ("pyproject.toml", pyproject_toml.as_str()),
        ("Gemfile", gemfile.as_str()),
        ("Cargo.toml", cargo_toml.as_str()),
        ("go.mod", go_mod.as_str()),
        ("composer.json", composer_json.as_str()),
        ("mix.exs", mix_exs.as_str()),
        ("pom.xml", pom_xml.as_str()),
        ("build.gradle", build_gradle.as_str()),
    ];

    let mut detected = Vec::new();
    let mut recommended_skills = Vec::new();

    if let Ok(mappings_content) = fs::read_to_string(&mappings_path) {
        if let Ok(mappings) = serde_json::from_str::<serde_json::Value>(&mappings_content) {
            if let Some(obj) = mappings.as_object() {
                for (cat_key, cat_val) in obj {
                    if cat_key.starts_with('_') { continue; }
                    
                    if let Some(items) = cat_val.as_object() {
                        for (item_key, item_val) in items {
                            let mut matched = false;
                            
                            if let Some(detect_arr) = item_val.get("detect").and_then(|v| v.as_array()) {
                                for pat in detect_arr {
                                    if let Some(pattern_str) = pat.as_str() {
                                        if check_pattern(pattern_str, project_dir, &manifests) {
                                            matched = true;
                                            break;
                                        }
                                    }
                                }
                            }

                            if matched {
                                detected.push(item_key.to_string());
                                
                                if let Some(skills_arr) = item_val.get("skills").and_then(|v| v.as_array()) {
                                    for skill in skills_arr {
                                        if let Some(skill_str) = skill.as_str() {
                                            if !recommended_skills.contains(&skill_str.to_string()) {
                                                recommended_skills.push(skill_str.to_string());
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Compute suggestions ---
    let mut suggestions = Vec::new();
    for rec in &recommended_skills {
        if !all_installed.contains(rec) {
            suggestions.push(rec.to_string());
        }
    }

    // --- check find-skills availability ---
    let mut find_skills = false;
    if claude_global.join("find-skills").exists() || agent_global.join("find-skills").exists() {
        find_skills = true;
    }

    let mut out = json!({
        "detected_stack": detected,
        "installed": {
            "global": installed_global.split(',').filter(|s| !s.is_empty()).collect::<Vec<&str>>(),
            "project": installed_project.split(',').filter(|s| !s.is_empty()).collect::<Vec<&str>>(),
            "agents": installed_agents.split(',').filter(|s| !s.is_empty()).collect::<Vec<&str>>()
        },
        "recommended_skills": recommended_skills,
        "suggestions": suggestions,
        "find_skills_available": find_skills
    });

    if include_brownfield {
        let brownfield = match std::process::Command::new("git")
            .args(["ls-files", "."])
            .current_dir(project_dir)
            .output()
        {
            Ok(output) => !String::from_utf8_lossy(&output.stdout).trim().is_empty(),
            Err(_) => false,
        };
        out.as_object_mut().unwrap().insert("brownfield".to_string(), json!(brownfield));
    }

    Ok((serde_json::to_string_pretty(&out).unwrap() + "\n", 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_detect_stack_missing_mappings() {
        let dir = tempdir().unwrap();
        let res = execute(&["yolo".to_string(), "detect-stack".to_string(), dir.path().to_string_lossy().to_string()], dir.path());
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("stack-mappings.json not found"));
    }

    #[test]
    fn test_detect_stack_success() {
        let dir = tempdir().unwrap();
        
        // Define stack mappings
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        let mappings_path = config_dir.join("stack-mappings.json");
        fs::write(&mappings_path, r#"{
            "frontend": {
                "react": { "description": "React", "skills": ["react-patterns"], "detect": ["package.json:react"] }
            }
        }"#).unwrap();

        // Create a fake package.json
        fs::write(dir.path().join("package.json"), r#"{"dependencies": {"react": "^18.0.0"}}"#).unwrap();

        let (out, _) = execute(&["yolo".to_string(), "detect-stack".to_string(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
        
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        let detected = parsed.get("detected_stack").unwrap().as_array().unwrap();
        assert_eq!(detected.len(), 1);
        assert_eq!(detected[0].as_str().unwrap(), "react");
        
        let recommended = parsed.get("recommended_skills").unwrap().as_array().unwrap();
        assert_eq!(recommended.len(), 1);
        assert_eq!(recommended[0].as_str().unwrap(), "react-patterns");
    }

    #[test]
    fn test_detect_stack_glob_pattern() {
        let dir = tempdir().unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("stack-mappings.json"), r#"{
            "languages": {
                "dotnet": { "skills": ["dotnet-skill"], "detect": ["*.csproj"] }
            }
        }"#).unwrap();
        fs::write(dir.path().join("MyApp.csproj"), "<Project/>").unwrap();
        let (out, _) = execute(&["yolo".into(), "detect-stack".into(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(parsed["detected_stack"].as_array().unwrap().iter().any(|v| v == "dotnet"),
            "Expected dotnet in detected_stack, got: {}", out);
    }

    #[test]
    fn test_detect_stack_glob_no_match() {
        let dir = tempdir().unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("stack-mappings.json"), r#"{
            "languages": {
                "dotnet": { "skills": ["dotnet-skill"], "detect": ["*.csproj"] }
            }
        }"#).unwrap();
        // No .csproj file present
        let (out, _) = execute(&["yolo".into(), "detect-stack".into(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(parsed["detected_stack"].as_array().unwrap().is_empty(),
            "Expected empty detected_stack, got: {}", out);
    }

    #[test]
    fn test_detect_stack_glob_sln_pattern() {
        let dir = tempdir().unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("stack-mappings.json"), r#"{
            "languages": {
                "dotnet": { "skills": ["dotnet-skill"], "detect": ["*.sln"] }
            }
        }"#).unwrap();
        fs::write(dir.path().join("MyApp.sln"), "").unwrap();
        let (out, _) = execute(&["yolo".into(), "detect-stack".into(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(parsed["detected_stack"].as_array().unwrap().iter().any(|v| v == "dotnet"),
            "Expected dotnet via *.sln pattern, got: {}", out);
    }

    #[test]
    fn test_detect_stack_brownfield_in_git_repo() {
        let dir = tempdir().unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("stack-mappings.json"), r#"{"_meta":{}}"#).unwrap();

        // Init a git repo with tracked files
        std::process::Command::new("git").args(["init", "-q"]).current_dir(dir.path()).output().unwrap();
        std::process::Command::new("git").args(["config", "user.email", "test@test.com"]).current_dir(dir.path()).output().unwrap();
        std::process::Command::new("git").args(["config", "user.name", "Test"]).current_dir(dir.path()).output().unwrap();
        fs::write(dir.path().join("dummy.txt"), "x").unwrap();
        std::process::Command::new("git").args(["add", "dummy.txt"]).current_dir(dir.path()).output().unwrap();
        std::process::Command::new("git").args(["commit", "-q", "-m", "init"]).current_dir(dir.path()).output().unwrap();

        let (out, code) = execute(&[
            "yolo".into(), "detect-stack".into(),
            dir.path().to_string_lossy().to_string(),
            "--brownfield".into(),
        ], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["brownfield"], json!(true));
    }

    #[test]
    fn test_detect_stack_no_brownfield_key_without_flag() {
        let dir = tempdir().unwrap();
        let config_dir = dir.path().join("config");
        fs::create_dir_all(&config_dir).unwrap();
        fs::write(config_dir.join("stack-mappings.json"), r#"{"_meta":{}}"#).unwrap();

        let (out, code) = execute(&[
            "yolo".into(), "detect-stack".into(),
            dir.path().to_string_lossy().to_string(),
        ], dir.path()).unwrap();
        assert_eq!(code, 0);
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert!(parsed.get("brownfield").is_none(), "brownfield key should not be present without flag");
    }
}
