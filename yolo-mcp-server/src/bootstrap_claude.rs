use std::fs;
use std::path::{Path, PathBuf};

const YOLO_SECTIONS: &[&str] = &[
    "## Active Context",
    "## YOLO Rules",
    "## Installed Skills",
    "## Project Conventions",
    "## Commands",
    "## Plugin Isolation",
];

const YOLO_DEPRECATED_SECTIONS: &[&str] = &[
    "## Key Decisions",
];

const GSD_STRONG_SECTIONS: &[&str] = &[
    "## Codebase Intelligence",
    "## Project Reference",
    "## GSD Rules",
    "## GSD Context",
];

const GSD_SOFT_SECTIONS: &[&str] = &[
    "## What This Is",
    "## Core Value",
    "## Context",
    "## Constraints",
];

fn generate_plugin_isolation() -> &'static str {
    "## Plugin Isolation\n\n- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.yolo-planning/`\n- YOLO agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`\n- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.\n\n### Context Isolation\n\n- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks \u{2014} these are GSD-generated and not relevant to YOLO workflows.\n- YOLO uses its own codebase mapping in `.yolo-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.\n- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into YOLO planning or vice versa.\n"
}

fn generate_yolo_sections() -> String {
    let mut out = String::new();
    out.push_str("## Active Context\n\n**Work:** No active milestone\n**Last shipped:** _(none yet)_\n**Next action:** Run /yolo:vibe to start a new milestone, or /yolo:status to review progress\n\n## YOLO Rules\n\n- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.\n- **Commit format:** `{type}({scope}): {description}` \u{2014} types: feat, fix, test, refactor, perf, docs, style, chore.\n- **One commit per task.** Each task in a plan gets exactly one atomic commit.\n- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.\n- **Plan before building.** Use /yolo:vibe for all lifecycle actions. Plans are the source of truth.\n- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.\n- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it, except when `.yolo-planning/config.json` intentionally sets `auto_push` to `always` or `after_phase`.\n\n## Installed Skills\n\n_(Run /yolo:skills to list)_\n\n## Project Conventions\n\n_(To be defined during project setup)_\n\n## Commands\n\nRun /yolo:status for current progress.\nRun /yolo:help for all available commands.\n\n");
    out.push_str(generate_plugin_isolation());
    out
}

fn is_managed_section(line: &str, allow_soft_gsd: bool) -> (bool, bool) {
    let t = line.trim_end();
    if YOLO_SECTIONS.contains(&t) { return (true, false); }
    if YOLO_DEPRECATED_SECTIONS.contains(&t) { return (true, true); }
    if GSD_STRONG_SECTIONS.contains(&t) { return (true, false); }
    if allow_soft_gsd && GSD_SOFT_SECTIONS.contains(&t) { return (true, false); }
    (false, false)
}

fn migrate_key_decisions(buffer: &str, state_path: &Path) -> (bool, String) {
    let mut data_rows = Vec::new();
    for row in buffer.lines() {
        if row.trim().starts_with("| Decision") { continue; }
        if row.contains("_(No decisions yet)_") { continue; }
        if row.trim().starts_with('|') && row.trim().chars().all(|c| c == '|' || c == '-' || c.is_whitespace()) { continue; }
        if row.trim().starts_with('|') {
            data_rows.push(row.to_string());
        }
    }

    if data_rows.is_empty() {
        return (true, "".to_string()); // Return true to indicate successful (empty) migration so we don't emit user content unless there is non-table stuff
    }

    if !state_path.exists() {
        eprintln!("Warning: Cannot migrate {} Key Decisions row(s) — STATE.md not found at {}", data_rows.len(), state_path.display());
        return (false, "".to_string());
    }

    let state_content = match fs::read_to_string(state_path) {
        Ok(c) => c,
        Err(_) => {
            eprintln!("Warning: Cannot migrate {} Key Decisions row(s) — STATE.md not found at {}", data_rows.len(), state_path.display());
            return (false, "".to_string());
        }
    };

    if !state_content.lines().any(|l| l.trim_end() == "## Key Decisions") {
        eprintln!("Warning: Cannot migrate {} Key Decisions row(s) — no ## Key Decisions section in STATE.md", data_rows.len());
        return (false, "".to_string());
    }

    let mut unique_rows = Vec::new();
    for drow in &data_rows {
        let normalized_drow: String = drow.split_whitespace().collect::<Vec<_>>().join(" ");
        let mut found = false;
        for line in state_content.lines() {
            let normalized_line: String = line.split_whitespace().collect::<Vec<_>>().join(" ");
            if normalized_line == normalized_drow {
                found = true;
                break;
            }
        }
        if !found {
            unique_rows.push(drow.clone());
        }
    }

    if unique_rows.is_empty() {
        eprintln!("Skipped migration — all {} Key Decisions row(s) already in STATE.md", data_rows.len());
        return (true, "".to_string());
    }

    let mut tmp_state = String::new();
    let mut in_kd_section = false;
    let mut past_separator = false;
    let mut rows_inserted = false;

    let lines: Vec<&str> = state_content.lines().collect();
    for &sline in &lines {
        if sline == "## Key Decisions" {
            in_kd_section = true;
            past_separator = false;
            rows_inserted = false;
            tmp_state.push_str(sline);
            tmp_state.push('\n');
            continue;
        }

        if in_kd_section && sline.starts_with("## ") {
            if past_separator && !rows_inserted {
                for ur in &unique_rows {
                    tmp_state.push_str(ur);
                    tmp_state.push('\n');
                }
                rows_inserted = true;
            }
            tmp_state.push('\n'); // Ensure blank line before next section
            in_kd_section = false;
            tmp_state.push_str(sline);
            tmp_state.push('\n');
            continue;
        }

        if in_kd_section {
            if sline.trim().starts_with('|') && sline.trim().chars().all(|c| c == '|' || c == '-' || c.is_whitespace()) {
                past_separator = true;
                tmp_state.push_str(sline);
                tmp_state.push('\n');
                continue;
            }
            if sline.contains("_(No decisions yet)_") {
                continue;
            }
            if past_separator && sline.trim().is_empty() {
                continue;
            }
            tmp_state.push_str(sline);
            tmp_state.push('\n');
        } else {
            tmp_state.push_str(sline);
            tmp_state.push('\n');
        }
    }

    if in_kd_section && past_separator && !rows_inserted {
        for ur in &unique_rows {
            tmp_state.push_str(ur);
            tmp_state.push('\n');
        }
        rows_inserted = true;
    }

    if !past_separator {
        eprintln!("Warning: Cannot migrate {} Key Decisions row(s) — STATE.md Key Decisions section has no table", unique_rows.len());
        return (false, "".to_string());
    }

    let _ = fs::write(state_path, tmp_state);
    eprintln!("Migrated {} Key Decisions row(s) from CLAUDE.md to STATE.md", unique_rows.len());
    (true, "".to_string())
}

fn flush_deprecated_buffer(
    buffer: &str,
    has_user_content: bool,
    non_yolo_content: &mut String,
    found_non_yolo: &mut bool,
    state_path: &Path,
) {
    if buffer.is_empty() { return; }

    if has_user_content {
        let (migrated, _) = migrate_key_decisions(buffer, state_path);
        if !migrated {
            non_yolo_content.push_str(buffer);
            *found_non_yolo = true;
            return;
        }
    }

    let mut preserved = String::new();
    let mut section_label = String::new();
    let mut first_line = true;

    for bline in buffer.lines() {
        if first_line {
            first_line = false;
            if let Some(lbl) = bline.strip_prefix("## ") {
                section_label = lbl.trim_end().to_string();
            } else {
                section_label = bline.trim_start_matches('#').trim().to_string();
            }
            continue;
        }

        if bline.trim().starts_with("| Decision") { continue; }
        if bline.trim().starts_with('|') && bline.trim().chars().all(|c| c == '|' || c == '-' || c.is_whitespace()) { continue; }
        if bline.trim().starts_with('|') { continue; }

        preserved.push_str(bline);
        preserved.push('\n');
    }

    let clean_preserved = trim_newlines(&preserved);
    if !clean_preserved.is_empty() {
        non_yolo_content.push_str(&format!("## {} (Archived Notes)\n\n{}\n\n", section_label, clean_preserved));
        *found_non_yolo = true;
    }
}

fn trim_newlines(s: &str) -> String {
    let mut start = 0;
    let mut end = s.len();
    while start < end && &s[start..start+1] == "\n" { start += 1; }
    while end > start && &s[end-1..end] == "\n" { end -= 1; }
    s[start..end].to_string()
}

pub fn execute(args: &[String], cwd: &Path) -> Result<(String, i32), String> {
    if args.len() < 4 {
        return Err("Usage: yolo bootstrap OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]".to_string());
    }

    let output_path = PathBuf::from(&args[1]);
    let project_name = &args[2];
    let core_value = &args[3];
    let existing_path = if args.len() > 4 { Some(PathBuf::from(&args[4])) } else { None };

    if project_name.is_empty() || core_value.is_empty() {
        return Err("Error: PROJECT_NAME and CORE_VALUE must not be empty".to_string());
    }

    if let Some(parent) = output_path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    if let Some(ep) = existing_path {
        if ep.exists() {
            let content = fs::read_to_string(&ep).unwrap_or_default();
            
            let mut allow_soft_gsd_strip = false;
            for line in content.lines() {
                if GSD_STRONG_SECTIONS.contains(&line.trim_end()) {
                    allow_soft_gsd_strip = true;
                    break;
                }
            }

            let mut non_yolo_content = String::new();
            let mut in_managed_section = false;
            let mut found_non_yolo = false;
            let mut in_deprecated_section = false;
            let mut deprecated_section_buffer = String::new();
            let mut deprecated_has_user_content = false;

            let state_path = if let Some(parent) = output_path.parent() {
                match parent.to_str() {
                    Some("") => cwd.join(".yolo-planning").join("STATE.md"),
                    _ => parent.join(".yolo-planning").join("STATE.md")
                }
            } else {
                cwd.join(".yolo-planning").join("STATE.md")
            };

            for line in content.lines() {
                let trimmed_line = line.trim_end();
                let (is_managed, is_deprecated) = is_managed_section(trimmed_line, allow_soft_gsd_strip);
                
                if is_managed {
                    flush_deprecated_buffer(&deprecated_section_buffer, deprecated_has_user_content, &mut non_yolo_content, &mut found_non_yolo, &state_path);
                    in_deprecated_section = false;
                    deprecated_section_buffer.clear();
                    deprecated_has_user_content = false;

                    if is_deprecated {
                        in_deprecated_section = true;
                        deprecated_section_buffer.push_str(line);
                        deprecated_section_buffer.push('\n');
                    }
                    in_managed_section = true;
                    continue;
                }

                if line.starts_with("## ") && !is_managed {
                    flush_deprecated_buffer(&deprecated_section_buffer, deprecated_has_user_content, &mut non_yolo_content, &mut found_non_yolo, &state_path);
                    in_deprecated_section = false;
                    deprecated_section_buffer.clear();
                    deprecated_has_user_content = false;
                    in_managed_section = false;
                }

                if in_deprecated_section {
                    deprecated_section_buffer.push_str(line);
                    deprecated_section_buffer.push('\n');
                    if !line.is_empty() && !(line.trim().starts_with('|') && line.trim().chars().all(|c| c == '|' || c == '-' || c.is_whitespace())) && !line.trim().starts_with("| Decision") {
                        deprecated_has_user_content = true;
                    }
                    continue;
                }

                if line.starts_with("# ") && !line.starts_with("## ") {
                    continue;
                }
                if line.starts_with("**Core value:**") {
                    continue;
                }

                if !in_managed_section {
                    non_yolo_content.push_str(line);
                    non_yolo_content.push('\n');
                    found_non_yolo = true;
                }
            }

            flush_deprecated_buffer(&deprecated_section_buffer, deprecated_has_user_content, &mut non_yolo_content, &mut found_non_yolo, &state_path);

            let mut final_out = String::new();
            final_out.push_str(&format!("# {}\n\n**Core value:** {}\n\n", project_name, core_value));
            
            if found_non_yolo {
                let clean_non_yolo = trim_newlines(&non_yolo_content);
                if !clean_non_yolo.is_empty() {
                    final_out.push_str(&clean_non_yolo);
                    final_out.push_str("\n\n");
                }
            }
            final_out.push_str(&generate_yolo_sections());
            let _ = fs::write(&output_path, final_out);
            return Ok(("Created".to_string(), 0));
        }
    }

    let mut out = String::new();
    out.push_str(&format!("# {}\n\n**Core value:** {}\n\n", project_name, core_value));
    out.push_str(&generate_yolo_sections());
    let _ = fs::write(&output_path, out);

    Ok(("Created".to_string(), 0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn run_bootstrap(args: &[&str], cwd: &Path) -> Result<(String, i32), String> {
        let mut string_args = Vec::new();
        // Skip args[0] in execute, so we provide an arbitrary "yolo" first arg
        string_args.push("yolo".to_string());
        for a in args {
            string_args.push(a.to_string());
        }
        execute(&string_args, cwd)
    }

    fn check(out: &Path, expected: &str) -> bool {
        let content = fs::read_to_string(out).unwrap_or_default();
        content.contains(expected)
    }

    fn assert_absent(out: &Path, expected: &str) {
        let content = fs::read_to_string(out).unwrap_or_default();
        assert!(!content.contains(expected), "Found unexpected string '{}' in file\nContent:\n{}", expected, content);
    }

    fn assert_regex(content: &str, regex_str: &str) {
        let re = regex::Regex::new(regex_str).unwrap();
        assert!(re.is_match(content), "Regex {} did not match content:\n{}", regex_str, content);
    }

    #[test]
    fn test_greenfield() {
        let dir = tempdir().unwrap();
        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Demo Project", "Demo core value"], dir.path()).unwrap();
        
        assert!(out.exists());
        let c = fs::read_to_string(&out).unwrap();
        assert!(c.contains("# Demo Project\n"));
        assert!(c.contains("**Core value:** Demo core value\n"));
        assert!(c.contains("## Active Context"));
        assert!(c.contains("## Project Conventions"));
        assert!(c.contains("## Plugin Isolation"));
        assert!(!c.contains("## Key Decisions"));
    }

    #[test]
    fn test_brownfield() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        
        let state_path = plan_dir.join("STATE.md");
        fs::write(&state_path, "# State\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| _(No decisions yet)_ | | |\n\n## Todos\n").unwrap();

        let existing = dir.path().join("existing.md");
        fs::write(&existing, "# Legacy Project\n\n**Core value:** Legacy value\n\n## Custom Notes\nKeep this section.\n\n## YOLO Rules\nOLD MANAGED CONTENT SHOULD BE REPLACED\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n\n## Codebase Intelligence\nOLD GSD CONTENT SHOULD BE STRIPPED\n\n## Project Reference\nOLD GSD PROJECT REFERENCE\n\n## GSD Rules\nOLD GSD RULES\n\n## GSD Context\nOLD GSD CONTEXT\n\n## What This Is\nOLD GSD WHAT THIS IS\n\n## Core Value\nOLD GSD CORE VALUE HEADER\n\n## Context\nOLD GSD CONTEXT HEADER\n\n## Constraints\nOLD GSD CONSTRAINTS HEADER\n\n## Team Notes\nKeep this too.\n").unwrap();

        let out = dir.path().join("CLAUDE.md");
        let sys_path = out.to_str().unwrap();
        run_bootstrap(&[sys_path, "Demo Project", "Demo core value", existing.to_str().unwrap()], dir.path()).unwrap();

        assert!(check(&out, "## Custom Notes"));
        assert!(check(&out, "## Team Notes"));
        assert_absent(&out, "OLD MANAGED CONTENT SHOULD BE REPLACED");
        assert_absent(&out, "## Key Decisions\n");
        assert_absent(&out, "Use widgets");
        assert!(check(&state_path, "Use widgets"));
        assert_absent(&out, "## Codebase Intelligence");
        assert_absent(&out, "## Project Reference");
        assert_absent(&out, "## GSD Rules");
        assert_absent(&out, "## GSD Context");
        assert_absent(&out, "## What This Is");
        assert_absent(&out, "## Context\n");
        assert_absent(&out, "## Constraints");

        let content = fs::read_to_string(&out).unwrap();
        let count = content.matches("## YOLO Rules").count();
        assert_eq!(count, 1);
    }

    #[test]
    fn test_idempotent() {
        let dir = tempdir().unwrap();
        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Demo Project", "Demo core value"], dir.path()).unwrap();
        let b1 = fs::read_to_string(&out).unwrap();
        run_bootstrap(&[out.to_str().unwrap(), "Demo Project", "Demo core value", out.to_str().unwrap()], dir.path()).unwrap();
        let b2 = fs::read_to_string(&out).unwrap();
        assert_eq!(b1, b2);
    }

    #[test]
    fn test_preserve_generic_custom() {
        let dir = tempdir().unwrap();
        let existing = dir.path().join("custom.md");
        fs::write(&existing, "# Team Project\n\n**Core value:** Team core value\n\n## Context\nThis is team-specific context and should be preserved.\n\n## Constraints\nThese are team-specific constraints and should be preserved.\n").unwrap();
        
        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Team Project", "Team core value", existing.to_str().unwrap()], dir.path()).unwrap();

        assert!(check(&out, "## Context"));
        assert!(check(&out, "## Constraints"));
        assert!(check(&out, "team-specific context"));
        assert!(check(&out, "team-specific constraints"));
    }

    #[test]
    fn test_edge_cases() {
        let dir = tempdir().unwrap();
        let out = dir.path().join("CLAUDE.md");
        assert!(run_bootstrap(&[out.to_str().unwrap(), "", "Some"], dir.path()).is_err());
        assert!(run_bootstrap(&[out.to_str().unwrap(), "Some", ""], dir.path()).is_err());
    }

    #[test]
    fn test_mixed_decisions() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state_path = plan_dir.join("STATE.md");
        fs::write(&state_path, "# State\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| _(No decisions yet)_ | | |\n").unwrap();

        let existing = dir.path().join("mixed.md");
        fs::write(&existing, "# Test Project\n\n**Core value:** Test value\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n\nrandom text\n- random text 2\n\n## Custom Section\nKeep this.\n").unwrap();

        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Test Project", "Test value", existing.to_str().unwrap()], dir.path()).unwrap();

        let c = fs::read_to_string(&out).unwrap();
        assert!(!c.contains("## Key Decisions\n"));
        assert!(!c.contains("Use widgets"));
        assert!(c.contains("random text"));
        assert!(c.contains("- random text 2"));
        assert!(c.contains("## Key Decisions (Archived Notes)"));
        assert!(check(&state_path, "Use widgets"));
    }

    #[test]
    fn test_deduplication() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state_path = plan_dir.join("STATE.md");
        fs::write(&state_path, "# State\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n\n## Todos\n").unwrap();

        let existing = dir.path().join("dup.md");
        fs::write(&existing, "# Test Project\n\n**Core value:** Test value\n\n## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n| New decision | 2025-02-01 | Fresh |\n\n## Custom Section\nKeep this.\n").unwrap();

        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Test Project", "Test value", existing.to_str().unwrap()], dir.path()).unwrap();

        let c = fs::read_to_string(&state_path).unwrap();
        let count = c.matches("Use widgets").count();
        assert_eq!(count, 1);
        assert!(c.contains("New decision"));
    }

    #[test]
    fn test_migration_warns_no_table() {
        let dir = tempdir().unwrap();
        let plan_dir = dir.path().join(".yolo-planning");
        fs::create_dir_all(&plan_dir).unwrap();
        let state_path = plan_dir.join("STATE.md");
        fs::write(&state_path, "# State\n\n## Key Decisions\n\n## Todos\n").unwrap();

        let existing = dir.path().join("notable.md");
        fs::write(&existing, "## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n").unwrap();

        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Test Project", "Test value", existing.to_str().unwrap()], dir.path()).unwrap();

        let c = fs::read_to_string(&out).unwrap();
        assert!(c.contains("## Key Decisions\n")); // Preserves as archived notes because no table in STATE.md
        assert!(c.contains("Use widgets"));
    }

    #[test]
    fn test_migration_warns_no_state() {
        let dir = tempdir().unwrap();
        let existing = dir.path().join("nostate.md");
        fs::write(&existing, "## Key Decisions\n\n| Decision | Date | Rationale |\n|---|---|---|\n| Use widgets | 2025-01-01 | They work |\n").unwrap();

        let out = dir.path().join("CLAUDE.md");
        run_bootstrap(&[out.to_str().unwrap(), "Test Project", "Test value", existing.to_str().unwrap()], dir.path()).unwrap();

        let c = fs::read_to_string(&out).unwrap();
        assert!(c.contains("## Key Decisions\n"));
        assert!(c.contains("Use widgets"));
    }
}
