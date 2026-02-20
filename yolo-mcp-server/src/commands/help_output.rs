use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// Generate formatted help output from command frontmatter.
/// Scans commands/*.md, parses YAML frontmatter, groups by category, formats box output.
pub fn execute(args: &[String], _cwd: &Path) -> Result<(String, i32), String> {
    let plugin_root = resolve_plugin_root(args)?;
    let commands_dir = Path::new(&plugin_root).join("commands");

    if !commands_dir.is_dir() {
        return Err(format!("Commands directory not found: {}", commands_dir.display()));
    }

    let entries = scan_commands(&commands_dir);
    let version = read_version(Path::new(&plugin_root));
    let output = format_help(&entries, version.as_deref());

    Ok((output, 0))
}

/// A parsed command entry from frontmatter.
struct CommandEntry {
    name: String,
    description: String,
    category: String,
    hint: String,
}

/// Resolve the plugin root from args or environment.
fn resolve_plugin_root(args: &[String]) -> Result<String, String> {
    // args[0] = "help-output", args[1..] = optional plugin root
    if args.len() > 1 && !args[1].is_empty() {
        return Ok(args[1].clone());
    }

    if let Ok(root) = std::env::var("CLAUDE_PLUGIN_ROOT") {
        if !root.is_empty() {
            return Ok(root);
        }
    }

    // Fall back to cache directory scan
    let config_dir = std::env::var("CLAUDE_CONFIG_DIR")
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| String::from("."));
            format!("{}/.claude", home)
        });

    let cache_dir = format!("{}/plugins/cache/yolo-marketplace/yolo", config_dir);
    let cache_path = Path::new(&cache_dir);

    if !cache_path.is_dir() {
        return Err("Could not resolve plugin root".to_string());
    }

    let mut versions: Vec<String> = Vec::new();
    if let Ok(entries) = fs::read_dir(cache_path) {
        for entry in entries.flatten() {
            if entry.path().is_dir() {
                if let Some(name) = entry.file_name().to_str() {
                    versions.push(name.to_string());
                }
            }
        }
    }

    if versions.is_empty() {
        return Err("No plugin versions found in cache".to_string());
    }

    versions.sort_by(|a, b| version_cmp(a, b));
    let latest = versions.last().unwrap();
    Ok(format!("{}/{}", cache_dir, latest))
}

/// Compare version strings numerically (e.g., "1.2.3" vs "1.10.0").
fn version_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let parse = |s: &str| -> Vec<u64> {
        s.split('.').filter_map(|p| p.parse().ok()).collect()
    };
    let va = parse(a);
    let vb = parse(b);
    va.cmp(&vb)
}

/// Scan all .md files in commands_dir and parse frontmatter.
fn scan_commands(commands_dir: &Path) -> Vec<CommandEntry> {
    let mut entries = Vec::new();

    let mut files: Vec<_> = match fs::read_dir(commands_dir) {
        Ok(rd) => rd.flatten().filter(|e| {
            e.path().extension().map(|ext| ext == "md").unwrap_or(false)
        }).collect(),
        Err(_) => return entries,
    };
    files.sort_by_key(|e| e.file_name());

    for entry in files {
        if let Some(cmd) = parse_frontmatter(&entry.path()) {
            entries.push(cmd);
        }
    }

    entries
}

/// Parse YAML frontmatter from a command .md file.
fn parse_frontmatter(path: &Path) -> Option<CommandEntry> {
    let content = fs::read_to_string(path).ok()?;
    let mut lines = content.lines();

    // First line must be "---"
    let first = lines.next()?;
    if first.trim() != "---" {
        return None;
    }

    let mut name = String::new();
    let mut description = String::new();
    let mut category = String::new();
    let mut hint = String::new();

    for line in lines {
        if line.trim() == "---" {
            break;
        }

        if let Some(val) = line.strip_prefix("name:") {
            name = strip_yaml_value(val);
        } else if let Some(val) = line.strip_prefix("description:") {
            description = strip_yaml_value(val);
        } else if let Some(val) = line.strip_prefix("category:") {
            category = strip_yaml_value(val);
        } else if let Some(val) = line.strip_prefix("argument-hint:") {
            hint = strip_yaml_value(val);
        }
    }

    if name.is_empty() {
        return None;
    }

    Some(CommandEntry { name, description, category, hint })
}

/// Strip whitespace and optional quotes from a YAML value.
fn strip_yaml_value(val: &str) -> String {
    let trimmed = val.trim();
    let unquoted = trimmed.trim_matches('"');
    unquoted.to_string()
}

/// Read VERSION file if it exists.
fn read_version(plugin_root: &Path) -> Option<String> {
    let version_path = plugin_root.join("VERSION");
    fs::read_to_string(version_path).ok().map(|s| s.trim().to_string())
}

/// Format the full help output with box, sections, and footer.
fn format_help(entries: &[CommandEntry], version: Option<&str>) -> String {
    let mut out = String::new();

    // Group entries by category
    let mut groups: BTreeMap<&str, Vec<&CommandEntry>> = BTreeMap::new();
    for entry in entries {
        let cat = match entry.category.as_str() {
            "lifecycle" | "monitoring" | "supporting" | "advanced" => entry.category.as_str(),
            _ => "other",
        };
        groups.entry(cat).or_default().push(entry);
    }

    // Sort entries within each group by name
    for group in groups.values_mut() {
        group.sort_by(|a, b| a.name.cmp(&b.name));
    }

    // Header box
    let header = if let Some(v) = version {
        format!("YOLO Help — v{}", v)
    } else {
        "YOLO Help".to_string()
    };

    out.push_str("╔══════════════════════════════════════════════════════════════════════════╗\n");
    let padding = 72usize.saturating_sub(header.len());
    out.push_str(&format!("║ {}{:>pad$}║\n", header, "", pad = padding));
    out.push_str("╚══════════════════════════════════════════════════════════════════════════╝\n");
    out.push('\n');

    // Sections in defined order
    let sections = [
        ("lifecycle", "Lifecycle", "The Main Loop"),
        ("monitoring", "Monitoring", "Trust But Verify"),
        ("supporting", "Supporting", "The Safety Net"),
        ("advanced", "Advanced", "For When You're Feeling Ambitious"),
        ("other", "Other", "Uncategorized"),
    ];

    for (key, title, subtitle) in &sections {
        if let Some(cmds) = groups.get(key) {
            if !cmds.is_empty() {
                format_section(&mut out, title, subtitle, cmds);
            }
        }
    }

    // Footer
    out.push_str("  /yolo:help <command>                      Details on a specific command\n");
    out.push_str("  /yolo:config                              View and change settings\n");
    out.push('\n');
    out.push_str("  Getting Started: /yolo:init → /yolo:vibe → /yolo:vibe --archive\n");

    out
}

/// Format a single category section.
fn format_section(out: &mut String, title: &str, subtitle: &str, cmds: &[&CommandEntry]) {
    out.push_str(&format!("  {} — {}\n", title, subtitle));
    out.push_str("  ──────────────────────────────────────────────────────────────────────\n");

    for cmd in cmds {
        let entry = if cmd.hint.is_empty() {
            format!("  /{}", cmd.name)
        } else {
            format!("  /{} {}", cmd.name, cmd.hint)
        };
        out.push_str(&format!("{:<42} {}\n", entry, cmd.description));
    }

    out.push('\n');
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn write_command(dir: &Path, filename: &str, name: &str, category: &str, desc: &str, hint: &str) {
        let content = format!(
            "---\nname: {}\ncategory: {}\ndescription: \"{}\"\nargument-hint: \"{}\"\n---\n\n# Test\n",
            name, category, desc, hint
        );
        fs::write(dir.join(filename), content).unwrap();
    }

    #[test]
    fn test_parse_frontmatter_valid() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("test.md");
        fs::write(&path, "---\nname: yolo:test\ncategory: lifecycle\ndescription: \"Test command\"\nargument-hint: \"[--flag]\"\n---\n\n# Body\n").unwrap();

        let entry = parse_frontmatter(&path).unwrap();
        assert_eq!(entry.name, "yolo:test");
        assert_eq!(entry.category, "lifecycle");
        assert_eq!(entry.description, "Test command");
        assert_eq!(entry.hint, "[--flag]");
    }

    #[test]
    fn test_parse_frontmatter_no_name() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("empty.md");
        fs::write(&path, "---\ncategory: lifecycle\n---\n").unwrap();

        assert!(parse_frontmatter(&path).is_none());
    }

    #[test]
    fn test_parse_frontmatter_no_frontmatter() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("plain.md");
        fs::write(&path, "# Just a heading\n\nNo frontmatter here.\n").unwrap();

        assert!(parse_frontmatter(&path).is_none());
    }

    #[test]
    fn test_scan_commands_groups_by_category() {
        let dir = TempDir::new().unwrap();
        let cmd_dir = dir.path().join("commands");
        fs::create_dir_all(&cmd_dir).unwrap();

        write_command(&cmd_dir, "vibe.md", "yolo:vibe", "lifecycle", "The one command", "[intent]");
        write_command(&cmd_dir, "status.md", "yolo:status", "monitoring", "Show status", "");
        write_command(&cmd_dir, "help.md", "yolo:help", "supporting", "Show help", "[cmd]");

        let entries = scan_commands(&cmd_dir);
        assert_eq!(entries.len(), 3);

        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"yolo:vibe"));
        assert!(names.contains(&"yolo:status"));
        assert!(names.contains(&"yolo:help"));
    }

    #[test]
    fn test_format_help_with_version() {
        let entries = vec![
            CommandEntry {
                name: "yolo:vibe".to_string(),
                description: "The one command".to_string(),
                category: "lifecycle".to_string(),
                hint: "[intent]".to_string(),
            },
            CommandEntry {
                name: "yolo:status".to_string(),
                description: "Show status".to_string(),
                category: "monitoring".to_string(),
                hint: "".to_string(),
            },
        ];

        let output = format_help(&entries, Some("2.1.1"));
        assert!(output.contains("YOLO Help — v2.1.1"));
        assert!(output.contains("Lifecycle — The Main Loop"));
        assert!(output.contains("/yolo:vibe [intent]"));
        assert!(output.contains("Monitoring — Trust But Verify"));
        assert!(output.contains("/yolo:status"));
        assert!(output.contains("Getting Started"));
    }

    #[test]
    fn test_format_help_without_version() {
        let entries = vec![];
        let output = format_help(&entries, None);
        assert!(output.contains("YOLO Help"));
        assert!(!output.contains("— v"));
    }

    #[test]
    fn test_format_help_unknown_category_goes_to_other() {
        let entries = vec![
            CommandEntry {
                name: "yolo:custom".to_string(),
                description: "Custom thing".to_string(),
                category: "nonexistent".to_string(),
                hint: "".to_string(),
            },
        ];

        let output = format_help(&entries, None);
        assert!(output.contains("Other — Uncategorized"));
        assert!(output.contains("/yolo:custom"));
    }

    #[test]
    fn test_strip_yaml_value() {
        assert_eq!(strip_yaml_value(" hello "), "hello");
        assert_eq!(strip_yaml_value(" \"quoted\" "), "quoted");
        assert_eq!(strip_yaml_value("  "), "");
    }

    #[test]
    fn test_version_cmp() {
        assert_eq!(version_cmp("1.2.3", "1.2.3"), std::cmp::Ordering::Equal);
        assert_eq!(version_cmp("1.2.3", "1.10.0"), std::cmp::Ordering::Less);
        assert_eq!(version_cmp("2.0.0", "1.99.99"), std::cmp::Ordering::Greater);
    }

    #[test]
    fn test_read_version_exists() {
        let dir = TempDir::new().unwrap();
        fs::write(dir.path().join("VERSION"), "3.0.0\n").unwrap();
        assert_eq!(read_version(dir.path()), Some("3.0.0".to_string()));
    }

    #[test]
    fn test_read_version_missing() {
        let dir = TempDir::new().unwrap();
        assert_eq!(read_version(dir.path()), None);
    }

    #[test]
    fn test_execute_with_real_commands() {
        let dir = TempDir::new().unwrap();
        let cmd_dir = dir.path().join("commands");
        fs::create_dir_all(&cmd_dir).unwrap();
        fs::write(dir.path().join("VERSION"), "1.0.0\n").unwrap();

        write_command(&cmd_dir, "init.md", "yolo:init", "lifecycle", "Init project", "");
        write_command(&cmd_dir, "config.md", "yolo:config", "advanced", "Configure settings", "[key] [value]");

        let args = vec!["help-output".to_string(), dir.path().to_string_lossy().to_string()];
        let (output, code) = execute(&args, dir.path()).unwrap();

        assert_eq!(code, 0);
        assert!(output.contains("YOLO Help — v1.0.0"));
        assert!(output.contains("/yolo:init"));
        assert!(output.contains("/yolo:config [key] [value]"));
    }

    #[test]
    fn test_execute_missing_commands_dir() {
        let dir = TempDir::new().unwrap();
        let args = vec!["help-output".to_string(), dir.path().to_string_lossy().to_string()];
        let result = execute(&args, dir.path());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Commands directory not found"));
    }
}
