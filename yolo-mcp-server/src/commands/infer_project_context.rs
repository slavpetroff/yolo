use std::fs;
use std::path::Path;
use std::process::Command;
use serde_json::json;

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() > 2 && (args[2] == "--help" || args[2] == "-h") {
        return Ok((
            "Usage: yolo infer-project-context CODEBASE_DIR [REPO_ROOT]\n\n\
             Extract project context from codebase mapping files.\n\n\
               CODEBASE_DIR  Path to .yolo-planning/codebase/ mapping files\n\
               REPO_ROOT     Optional, defaults to current directory\n\n\
             Outputs structured JSON to stdout with source attribution per field.\n".to_string(),
            0
        ));
    }

    if args.len() < 3 {
        return Err("Error: CODEBASE_DIR is required\nUsage: yolo infer-project-context CODEBASE_DIR [REPO_ROOT]".to_string());
    }

    let codebase_dir = Path::new(&args[2]);
    let repo_root = if args.len() > 3 {
        Path::new(&args[3])
    } else {
        cwd
    };

    if !codebase_dir.exists() || !codebase_dir.is_dir() {
        return Err(format!("Error: CODEBASE_DIR does not exist: {}", codebase_dir.display()));
    }

    // --- Project name extraction (priority: git repo > plugin.json > directory) ---
    let mut name_value = String::new();
    let mut name_source = String::new();

    // Try git repo name
    let git_output = Command::new("git")
        .args(["-C", &repo_root.to_string_lossy(), "remote", "get-url", "origin"])
        .output();
    if let Ok(output) = git_output {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let url = stdout.trim();
        if !url.is_empty() {
            if let Some(pos) = url.rfind('/') {
                let mut repo_name = &url[pos + 1..];
                if repo_name.ends_with(".git") {
                    repo_name = &repo_name[..repo_name.len() - 4];
                }
                if !repo_name.is_empty() {
                    name_value = repo_name.to_string();
                    name_source = "repo".to_string();
                }
            }
        }
    }

    // Try plugin.json name
    if name_value.is_empty() {
        let plugin_json = repo_root.join(".claude-plugin").join("plugin.json");
        if plugin_json.exists() {
            if let Ok(content) = fs::read_to_string(&plugin_json) {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(n) = parsed.get("name").and_then(|v| v.as_str()) {
                        if !n.is_empty() {
                            name_value = n.to_string();
                            name_source = "plugin.json".to_string();
                        }
                    }
                }
            }
        }
    }

    // Fallback to directory name
    if name_value.is_empty() {
        if let Some(name) = repo_root.file_name().and_then(|n| n.to_str()) {
            name_value = name.to_string();
        } else {
            name_value = "unknown".to_string();
        }
        name_source = "directory".to_string();
    }

    let name_json = json!({
        "value": name_value,
        "source": name_source
    });

    // --- Tech stack extraction from STACK.md ---
    let mut stack_items = Vec::new();
    let mut stack_source = String::new();
    let stack_file = codebase_dir.join("STACK.md");
    if stack_file.exists() {
        if let Ok(content) = fs::read_to_string(&stack_file) {
            let mut in_languages = false;
            let mut in_key_tech = false;

            for line in content.lines() {
                if line.starts_with("## ") {
                    let heading_lower = line.to_lowercase();
                    if heading_lower.contains("language") {
                        in_languages = true;
                        in_key_tech = false;
                        continue;
                    } else if heading_lower.contains("framework")
                        || heading_lower.contains("technolog")
                        || heading_lower.contains("librar")
                    {
                        in_key_tech = true;
                        in_languages = false;
                        continue;
                    } else {
                        in_languages = false;
                        in_key_tech = false;
                        continue;
                    }
                }

                if in_languages {
                    // Table format: | Rust | ...
                    if line.starts_with("| ") && !line.starts_with("| Language") && !line.starts_with("|--") && !line.starts_with("|-") {
                        let parts: Vec<&str> = line.split('|').collect();
                        if parts.len() > 1 {
                            let lang = parts[1].trim();
                            if !lang.is_empty() {
                                stack_items.push(lang.to_string());
                            }
                        }
                    }
                    // Bullet format: - **Rust** (90 files) — ...
                    if line.starts_with("- ") {
                        let item = line.trim_start_matches("- ");
                        let item = item.trim_start_matches("**");
                        let name = if let Some(pos) = item.find("**") {
                            item[..pos].to_string()
                        } else if let Some(pos) = item.find(" (") {
                            item[..pos].to_string()
                        } else {
                            item.split_whitespace().next().unwrap_or("").to_string()
                        };
                        if !name.is_empty() {
                            stack_items.push(name);
                        }
                    }
                }

                if in_key_tech {
                    if line.starts_with("- ") {
                        let mut tech = line.trim_start_matches("- ").to_string();
                        tech = tech.trim_start_matches("**").to_string();
                        if let Some(pos) = tech.find("**") {
                            tech = tech[..pos].to_string();
                        }
                        if !tech.is_empty() {
                            stack_items.push(tech);
                        }
                    }
                }
            }
        }
        if !stack_items.is_empty() {
            stack_source = "STACK.md".to_string();
        }
    }

    // --- Manifest-based fallback when STACK.md yields no results ---
    if stack_items.is_empty() {
        let mut manifest_sources = Vec::new();

        // Cargo.toml → Rust
        if repo_root.join("Cargo.toml").exists() {
            stack_items.push("Rust".to_string());
            manifest_sources.push("Cargo.toml");
        }

        // pyproject.toml → Python + framework deps
        let pyproject = repo_root.join("pyproject.toml");
        if pyproject.exists() {
            stack_items.push("Python".to_string());
            manifest_sources.push("pyproject.toml");
            if let Ok(content) = fs::read_to_string(&pyproject) {
                let lower = content.to_lowercase();
                for fw in &["fastapi", "django", "flask"] {
                    if lower.contains(fw) {
                        stack_items.push(fw.to_string());
                    }
                }
            }
        }

        // requirements.txt → Python + framework deps
        let reqtxt = repo_root.join("requirements.txt");
        if reqtxt.exists() && !stack_items.contains(&"Python".to_string()) {
            stack_items.push("Python".to_string());
            manifest_sources.push("requirements.txt");
            if let Ok(content) = fs::read_to_string(&reqtxt) {
                let lower = content.to_lowercase();
                for fw in &["fastapi", "django", "flask"] {
                    if lower.contains(fw) && !stack_items.contains(&fw.to_string()) {
                        stack_items.push(fw.to_string());
                    }
                }
            }
        }

        // package.json → JavaScript/TypeScript + framework deps
        let pkgjson = repo_root.join("package.json");
        if pkgjson.exists() {
            stack_items.push("JavaScript/TypeScript".to_string());
            manifest_sources.push("package.json");
            if let Ok(content) = fs::read_to_string(&pkgjson) {
                let lower = content.to_lowercase();
                for fw in &["react", "vue", "next", "express"] {
                    if lower.contains(fw) {
                        stack_items.push(fw.to_string());
                    }
                }
            }
        }

        // go.mod → Go
        if repo_root.join("go.mod").exists() {
            stack_items.push("Go".to_string());
            manifest_sources.push("go.mod");
        }

        // Gemfile → Ruby
        if repo_root.join("Gemfile").exists() {
            stack_items.push("Ruby".to_string());
            manifest_sources.push("Gemfile");
        }

        // mix.exs → Elixir
        if repo_root.join("mix.exs").exists() {
            stack_items.push("Elixir".to_string());
            manifest_sources.push("mix.exs");
        }

        // composer.json → PHP
        if repo_root.join("composer.json").exists() {
            stack_items.push("PHP".to_string());
            manifest_sources.push("composer.json");
        }

        // pom.xml / build.gradle → Java
        if repo_root.join("pom.xml").exists() || repo_root.join("build.gradle").exists() {
            stack_items.push("Java".to_string());
            if repo_root.join("pom.xml").exists() {
                manifest_sources.push("pom.xml");
            }
            if repo_root.join("build.gradle").exists() {
                manifest_sources.push("build.gradle");
            }
        }

        if !manifest_sources.is_empty() {
            stack_source = format!("manifest:{}", manifest_sources.join(","));
        }
    }

    let stack_json = if !stack_items.is_empty() {
        json!({
            "value": stack_items,
            "source": stack_source
        })
    } else {
        json!({ "value": serde_json::Value::Null, "source": serde_json::Value::Null })
    };

    // --- Architecture extraction from ARCHITECTURE.md ---
    let mut arch_text = String::new();
    let arch_file = codebase_dir.join("ARCHITECTURE.md");
    if arch_file.exists() {
        if let Ok(content) = fs::read_to_string(&arch_file) {
            let mut in_overview = false;
            for line in content.lines() {
                if line == "## Overview" {
                    in_overview = true;
                    continue;
                }
                if in_overview {
                    if line.starts_with("##") {
                        break;
                    }
                    if !line.trim().is_empty() {
                        if !arch_text.is_empty() {
                            arch_text.push(' ');
                        }
                        arch_text.push_str(line.trim());
                    }
                }
            }
        }
    }

    let arch_json = if !arch_text.is_empty() {
        json!({
            "value": arch_text,
            "source": "ARCHITECTURE.md"
        })
    } else {
        json!({ "value": serde_json::Value::Null, "source": serde_json::Value::Null })
    };

    // --- Purpose extraction from CONCERNS.md ---
    let mut purpose_text = String::new();
    let mut concerns = Vec::new();
    let concerns_file = codebase_dir.join("CONCERNS.md");
    
    if concerns_file.exists() {
        if let Ok(content) = fs::read_to_string(&concerns_file) {
            for line in content.lines() {
                if line.starts_with("# ") && purpose_text.is_empty() {
                    purpose_text = line.trim_start_matches("# ").to_string();
                } else if line.starts_with("## ") {
                    concerns.push(line.trim_start_matches("## ").to_string());
                }
            }
        }
    }

    let purpose_json = if !purpose_text.is_empty() && !concerns.is_empty() {
        let concerns_str = concerns.join(", ");
        json!({
            "value": format!("{} — key concerns: {}", purpose_text, concerns_str),
            "source": "CONCERNS.md"
        })
    } else if !purpose_text.is_empty() {
        json!({
            "value": purpose_text,
            "source": "CONCERNS.md"
        })
    } else {
        json!({ "value": serde_json::Value::Null, "source": serde_json::Value::Null })
    };

    // --- Features extraction from INDEX.md ---
    let mut features = Vec::new();
    let index_file = codebase_dir.join("INDEX.md");
    
    if index_file.exists() {
        if let Ok(content) = fs::read_to_string(&index_file) {
            let mut in_themes = false;
            for line in content.lines() {
                if line == "## Cross-Cutting Themes" {
                    in_themes = true;
                    continue;
                }
                if in_themes {
                    if line.starts_with("##") {
                        break;
                    }
                    if line.starts_with("- ") {
                        let mut feature = line.trim_start_matches("- ").to_string();
                        feature = feature.trim_start_matches("**").to_string();
                        if let Some(pos) = feature.find("**: ") {
                            feature = feature[..pos].to_string();
                        } else if let Some(pos) = feature.find("**:") {
                            feature = feature[..pos].to_string();
                        } else if let Some(pos) = feature.find("**") {
                            feature = feature[..pos].to_string();
                        }
                        if !feature.is_empty() {
                            features.push(feature);
                        }
                    }
                }
            }
        }
    }

    let features_json = if !features.is_empty() {
        json!({
            "value": features,
            "source": "INDEX.md"
        })
    } else {
        json!({ "value": serde_json::Value::Null, "source": serde_json::Value::Null })
    };

    let out = json!({
        "name": name_json,
        "tech_stack": stack_json,
        "architecture": arch_json,
        "purpose": purpose_json,
        "features": features_json
    });

    Ok((serde_json::to_string_pretty(&out).unwrap() + "\n", 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_infer_missing_args() {
        let dir = tempdir().unwrap();
        let res = execute(&["yolo".to_string(), "infer".to_string()], dir.path());
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("CODEBASE_DIR is required"));
    }

    #[test]
    fn test_infer_success() {
        let dir = tempdir().unwrap();
        let codebase_dir = dir.path().join("codebase");
        fs::create_dir_all(&codebase_dir).unwrap();

        fs::write(codebase_dir.join("STACK.md"), "## Languages\n| Language |\n|--|\n| Rust |\n## Key Technologies\n- **Serde**: library\n## Other").unwrap();
        fs::write(codebase_dir.join("ARCHITECTURE.md"), "## Overview\nThis is a test architecture.\n## Details").unwrap();
        fs::write(codebase_dir.join("CONCERNS.md"), "# Test Project\n## Security\n## Performance").unwrap();
        fs::write(codebase_dir.join("INDEX.md"), "## Cross-Cutting Themes\n- **Logging**: detailed\n## Other").unwrap();

        let (out, _) = execute(&["yolo".to_string(), "infer".to_string(), codebase_dir.to_string_lossy().to_string(), dir.path().to_string_lossy().to_string()], dir.path()).unwrap();
        
        let parsed: serde_json::Value = serde_json::from_str(&out).unwrap();
        
        assert_eq!(parsed["name"]["source"].as_str().unwrap(), "directory");
        
        let tech = parsed["tech_stack"]["value"].as_array().unwrap();
        assert_eq!(tech.len(), 2);
        assert_eq!(tech[0].as_str().unwrap(), "Rust");
        assert_eq!(tech[1].as_str().unwrap(), "Serde");

        let arch = parsed["architecture"]["value"].as_str().unwrap();
        assert_eq!(arch, "This is a test architecture.");

        let purpose = parsed["purpose"]["value"].as_str().unwrap();
        assert_eq!(purpose, "Test Project — key concerns: Security, Performance");

        let features = parsed["features"]["value"].as_array().unwrap();
        assert_eq!(features.len(), 1);
        assert_eq!(features[0].as_str().unwrap(), "Logging");
    }
}
