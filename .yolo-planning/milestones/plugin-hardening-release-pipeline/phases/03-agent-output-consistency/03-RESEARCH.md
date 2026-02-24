# Phase 3 Research: Agent Output Consistency

## Findings

### 1. commit_hashes validation (verify_plan_completion.rs)
- Check 4 validates regex `^[0-9a-fA-F]{7,}$` only — no git existence check
- `_cwd` parameter unused (underscore prefix) — needs promoting to `cwd` for git calls
- Pattern: `std::process::Command` already used in diff_against_plan.rs for `git show`
- Insertion point: inside `invalid.is_empty()` pass branch, add git rev-parse loop
- Must handle "not a git repo" case (skip check, warn) vs "hash not found" (hard fail)

### 2. diff-against-plan --commits flag
- No flag parsing exists — all args beyond index 2 ignored
- `parse_flag()` pattern from qa_suite.rs is the template
- Override point: between frontmatter extraction (line 47) and `get_git_files()` call (line 54)
- `get_git_files()` accepts arbitrary hash slices — no change needed
- qa-suite does NOT need --commits passthrough (per context decision)

### 3. SUMMARY naming (dev agent template)
- yolo-dev.md line 43: `{phase-dir}/{NN-MM}-SUMMARY.md` — implicit template
- SKILL.md line 708: same pattern in Step 3c
- Phase/plan IDs always available via Task subject (`Execute {NN-MM}: {title}`) and PLAN.md frontmatter
- Fix: make derivation explicit — read `phase` + `plan` from PLAN.md frontmatter

## Relevant Patterns
- git Command pattern: `Command::new("git").args([...]).current_dir(cwd).output()`
- rev-parse syntax: `git rev-parse --verify {hash}^{commit}` (Rust format: `"{}^{{commit}}"`)
- Flag parsing: `parse_flag(args, "--flag")` returns `Option<String>`
- Check result: `json!({"name", "status", "detail", "fixable_by"})`

## Risks
- Tests use tempdir (not git repo) — git rev-parse will fail; need "not a git repo" fallback
- `--commits ""` produces empty vec — treat as "flag not passed", fall back to frontmatter
- SUMMARY naming is agent behavior (prompt change), not enforced by code

## Recommendations
- 3 plans: (1) commit_hashes validation, (2) --commits flag, (3) SUMMARY naming
- All independent (wave 1) — no cross-plan file conflicts
- Plans 1-2 are Rust code changes; Plan 3 is plugin instruction edits
