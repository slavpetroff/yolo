use std::fs;
use std::path::Path;

/// Execute the vibe command consolidation verification.
/// Checks all 25 requirements (REQ-01 through REQ-25) across 6 groups.
/// Read-only: never modifies any files.
pub fn execute(_args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    let vibe = cwd.join("commands/vibe.md");
    let protocol = cwd.join("skills/execute-protocol/SKILL.md");
    let commands_dir = cwd.join("commands");
    let readme = cwd.join("README.md");
    let claude_md = cwd.join("CLAUDE.md");
    let help = cwd.join("commands/help.md");
    let suggest = cwd.join("yolo-mcp-server/src/commands/suggest_next.rs");
    let mkt_root = cwd.join("marketplace.json");
    let mkt_plugin = cwd.join(".claude-plugin/marketplace.json");

    let mut output = String::new();
    let mut total_pass = 0u32;
    let mut total_fail = 0u32;

    // GROUP 1: Core Router (REQ-01 to REQ-05)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 1: Core Router (REQ-01 to REQ-05) ===\n");

        chk(&mut output, &mut gp, &mut gf, "REQ-01", "vibe.md contains planning_dir_exists", file_contains(&vibe, "planning_dir_exists"));
        chk(&mut output, &mut gp, &mut gf, "REQ-01", "vibe.md contains phase_count=0", file_contains(&vibe, "phase_count=0"));
        chk(&mut output, &mut gp, &mut gf, "REQ-01", "vibe.md contains next_phase_state", file_contains(&vibe, "next_phase_state"));
        chk(&mut output, &mut gp, &mut gf, "REQ-02", "vibe.md has Natural language intent section", file_contains(&vibe, "Natural language intent"));
        chk(&mut output, &mut gp, &mut gf, "REQ-02", "vibe.md has interpret user intent", file_contains(&vibe, "interpret user intent"));
        chk(&mut output, &mut gp, &mut gf, "REQ-03", "vibe.md maps --plan to Plan mode", file_contains(&vibe, "--plan") && file_contains(&vibe, "Plan mode"));
        chk(&mut output, &mut gp, &mut gf, "REQ-03", "vibe.md maps --execute to Execute mode", file_contains(&vibe, "--execute") && file_contains(&vibe, "Execute mode"));
        chk(&mut output, &mut gp, &mut gf, "REQ-03", "vibe.md maps --discuss to Discuss mode", file_contains(&vibe, "--discuss") && file_contains(&vibe, "Discuss mode"));
        chk(&mut output, &mut gp, &mut gf, "REQ-04", "vibe.md references AskUserQuestion", file_contains(&vibe, "AskUserQuestion"));
        chk(&mut output, &mut gp, &mut gf, "REQ-05", "vibe.md describes --yolo flag", file_contains(&vibe, "--yolo"));
        chk(&mut output, &mut gp, &mut gf, "REQ-05", "vibe.md describes --yolo skipping confirmations", file_contains(&vibe, "skip") && file_contains(&vibe, "confirmation"));

        group_end(&mut output, "Core Router", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // GROUP 2: Mode Implementation (REQ-06 to REQ-15)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 2: Mode Implementation (REQ-06 to REQ-15) ===\n");

        let mode_headers = [
            ("REQ-06", "Mode: Init Redirect"),
            ("REQ-06", "Mode: Bootstrap"),
            ("REQ-07", "Mode: Scope"),
            ("REQ-10", "Mode: Discuss"),
            ("REQ-11", "Mode: Assumptions"),
            ("REQ-08", "Mode: Plan"),
            ("REQ-09", "Mode: Execute"),
            ("REQ-12", "Mode: Add Phase"),
            ("REQ-13", "Mode: Insert Phase"),
            ("REQ-14", "Mode: Remove Phase"),
            ("REQ-15", "Mode: Archive"),
        ];
        for (req, header) in &mode_headers {
            chk(&mut output, &mut gp, &mut gf, req, &format!("{header} header"), file_contains(&vibe, &format!("### {header}")));
        }

        chk(&mut output, &mut gp, &mut gf, "REQ-06", "Bootstrap references PROJECT.md", file_contains(&vibe, "PROJECT.md"));
        chk(&mut output, &mut gp, &mut gf, "REQ-09", "Execute mode references execute-protocol.md", file_contains(&vibe, "execute-protocol.md"));
        chk(&mut output, &mut gp, &mut gf, "REQ-15", "Archive mode has audit matrix", file_contains(&vibe, "audit"));

        group_end(&mut output, "Mode Implementation", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // GROUP 3: Execution Protocol (REQ-16, REQ-17)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 3: Execution Protocol (REQ-16, REQ-17) ===\n");

        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md exists in skills/", protocol.exists());
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol.md NOT in commands/", !commands_dir.join("execute-protocol.md").exists());
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md has name: frontmatter", file_has_line(&protocol, "name:"));
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md contains Step 2", file_contains(&protocol, "Step 2"));
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md contains Step 3", file_contains(&protocol, "Step 3"));
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md contains Step 4", file_contains(&protocol, "Step 4"));
        chk(&mut output, &mut gp, &mut gf, "REQ-16", "execute-protocol SKILL.md contains Step 5", file_contains(&protocol, "Step 5"));
        chk(&mut output, &mut gp, &mut gf, "REQ-17", "vibe.md Execute mode reads execute-protocol.md", file_contains(&vibe, "Read") && file_contains(&vibe, "execute-protocol"));

        group_end(&mut output, "Execution Protocol", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // GROUP 4: Command Surface (REQ-18 to REQ-20)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 4: Command Surface (REQ-18 to REQ-20) ===\n");

        let absorbed = [
            "implement", "plan", "execute", "discuss", "assumptions",
            "add-phase", "insert-phase", "remove-phase", "archive", "audit",
        ];
        for cmd in &absorbed {
            chk(&mut output, &mut gp, &mut gf, "REQ-18", &format!("commands/{cmd}.md does not exist"), !commands_dir.join(format!("{cmd}.md")).exists());
        }

        // Count .md files in commands/
        let cmd_count = count_md_files(&commands_dir);
        chk(&mut output, &mut gp, &mut gf, "REQ-18", &format!("commands/ has exactly 20 .md files (found {cmd_count})"), cmd_count == 20);

        chk(&mut output, &mut gp, &mut gf, "REQ-20", "README.md has no '29 commands'", !file_contains(&readme, "29 commands"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", "marketplace.json has no '29 commands'", !file_contains(&mkt_root, "29 commands"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", ".claude-plugin/marketplace.json has no '29 commands'", !file_contains(&mkt_plugin, "29 commands"));

        chk(&mut output, &mut gp, &mut gf, "REQ-20", "suggest_next.rs has no /yolo:implement", !file_contains(&suggest, "/yolo:implement"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", "help.md has no /yolo:implement", !file_contains(&help, "/yolo:implement"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", "README.md has no /yolo:implement", !file_contains(&readme, "/yolo:implement"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", "CLAUDE.md has no /yolo:implement", !file_contains(&claude_md, "/yolo:implement"));

        chk(&mut output, &mut gp, &mut gf, "REQ-20", "suggest_next.rs references /yolo:vibe", file_contains(&suggest, "/yolo:vibe"));
        chk(&mut output, &mut gp, &mut gf, "REQ-20", "help.md references /yolo:vibe", file_contains(&help, "/yolo:vibe"));

        group_end(&mut output, "Command Surface", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // GROUP 5: NL Parsing (REQ-21, REQ-22)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 5: NL Parsing (REQ-21, REQ-22) ===\n");

        chk(&mut output, &mut gp, &mut gf, "REQ-21", "vibe.md has no regex patterns", !file_contains(&vibe, "regex"));
        chk(&mut output, &mut gp, &mut gf, "REQ-21", "vibe.md has no import statements", !file_has_line_starting_with(&vibe, "import "));
        chk(&mut output, &mut gp, &mut gf, "REQ-21", "vibe.md has keyword-based intent matching", file_contains(&vibe, "keywords"));
        chk(&mut output, &mut gp, &mut gf, "REQ-22", "vibe.md handles ambiguous intents", file_contains(&vibe, "Ambiguous"));
        chk(&mut output, &mut gp, &mut gf, "REQ-22", "vibe.md offers 2-3 options for ambiguity", file_contains(&vibe, "2-3") && file_contains(&vibe, "options"));

        group_end(&mut output, "NL Parsing", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // GROUP 6: Flags (REQ-23 to REQ-25)
    {
        let mut gp = 0u32;
        let mut gf = 0u32;
        output.push_str("\n=== GROUP 6: Flags (REQ-23 to REQ-25) ===\n");

        let flag_count = count_flag_lines(&vibe);
        chk(&mut output, &mut gp, &mut gf, "REQ-23", &format!("vibe.md has >= 9 mode flags (found {flag_count})"), flag_count >= 9);

        chk(&mut output, &mut gp, &mut gf, "REQ-24", "vibe.md has --effort modifier", file_contains(&vibe, "--effort"));
        chk(&mut output, &mut gp, &mut gf, "REQ-24", "vibe.md has --skip-qa modifier", file_contains(&vibe, "--skip-qa"));
        chk(&mut output, &mut gp, &mut gf, "REQ-24", "vibe.md has --skip-audit modifier", file_contains(&vibe, "--skip-audit"));
        chk(&mut output, &mut gp, &mut gf, "REQ-24", "vibe.md has --plan=NN modifier", file_contains(&vibe, "--plan=NN"));

        chk(&mut output, &mut gp, &mut gf, "REQ-25", "vibe.md documents bare integer support", file_contains_ci(&vibe, "bare integer"));
        chk(&mut output, &mut gp, &mut gf, "REQ-25", "vibe.md bare integer targets phase N", file_contains(&vibe, "phase N"));

        group_end(&mut output, "Flags", gp, gf);
        total_pass += gp;
        total_fail += gf;
    }

    // Summary
    output.push_str("\n===============================\n");
    output.push_str(&format!("  TOTAL: {total_pass} PASS, {total_fail} FAIL\n"));
    output.push_str("===============================\n");

    if total_fail == 0 {
        output.push_str("  All checks passed.\n");
        Ok((output, 0))
    } else {
        output.push_str("  Some checks failed.\n");
        Ok((output, 1))
    }
}

fn chk(output: &mut String, pass: &mut u32, fail: &mut u32, req: &str, desc: &str, result: bool) {
    if result {
        output.push_str(&format!("  PASS  {req}: {desc}\n"));
        *pass += 1;
    } else {
        output.push_str(&format!("  FAIL  {req}: {desc}\n"));
        *fail += 1;
    }
}

fn group_end(output: &mut String, label: &str, gp: u32, gf: u32) {
    if gf == 0 {
        output.push_str(&format!("  >> {label}: ALL PASS ({gp} checks)\n"));
    } else {
        output.push_str(&format!("  >> {label}: {gf} FAIL, {gp} pass\n"));
    }
}

fn file_contains(path: &Path, pattern: &str) -> bool {
    fs::read_to_string(path)
        .map(|c| c.contains(pattern))
        .unwrap_or(false)
}

fn file_contains_ci(path: &Path, pattern: &str) -> bool {
    fs::read_to_string(path)
        .map(|c| c.to_lowercase().contains(&pattern.to_lowercase()))
        .unwrap_or(false)
}

fn file_has_line(path: &Path, prefix: &str) -> bool {
    fs::read_to_string(path)
        .map(|c| c.lines().any(|l| l.starts_with(prefix)))
        .unwrap_or(false)
}

fn file_has_line_starting_with(path: &Path, prefix: &str) -> bool {
    fs::read_to_string(path)
        .map(|c| c.lines().any(|l| l.starts_with(prefix)))
        .unwrap_or(false)
}

fn count_md_files(dir: &Path) -> usize {
    fs::read_dir(dir)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| {
                    e.path()
                        .extension()
                        .map(|ext| ext == "md")
                        .unwrap_or(false)
                })
                .count()
        })
        .unwrap_or(0)
}

fn count_flag_lines(path: &Path) -> usize {
    fs::read_to_string(path)
        .map(|c| {
            c.lines()
                .filter(|l| l.starts_with("- `--"))
                .count()
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_file_contains_present() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("test.md");
        fs::write(&f, "Hello world").unwrap();
        assert!(file_contains(&f, "world"));
    }

    #[test]
    fn test_file_contains_absent() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("test.md");
        fs::write(&f, "Hello world").unwrap();
        assert!(!file_contains(&f, "missing"));
    }

    #[test]
    fn test_file_contains_ci() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("test.md");
        fs::write(&f, "Bare Integer support").unwrap();
        assert!(file_contains_ci(&f, "bare integer"));
    }

    #[test]
    fn test_count_md_files() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("a.md"), "").unwrap();
        fs::write(dir.path().join("b.md"), "").unwrap();
        fs::write(dir.path().join("c.txt"), "").unwrap();
        assert_eq!(count_md_files(dir.path()), 2);
    }

    #[test]
    fn test_count_flag_lines() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("test.md");
        fs::write(&f, "- `--plan` Plan mode\n- `--execute` Execute mode\nSome other line\n- `--discuss` Discuss mode\n").unwrap();
        assert_eq!(count_flag_lines(&f), 3);
    }

    #[test]
    fn test_chk_pass() {
        let mut output = String::new();
        let mut p = 0;
        let mut f = 0;
        chk(&mut output, &mut p, &mut f, "TEST-01", "test", true);
        assert_eq!(p, 1);
        assert_eq!(f, 0);
        assert!(output.contains("PASS"));
    }

    #[test]
    fn test_chk_fail() {
        let mut output = String::new();
        let mut p = 0;
        let mut f = 0;
        chk(&mut output, &mut p, &mut f, "TEST-01", "test", false);
        assert_eq!(p, 0);
        assert_eq!(f, 1);
        assert!(output.contains("FAIL"));
    }
}
