# CLI Command Audit Report

**Date:** 2026-02-22
**Scope:** All CLI commands routed in `yolo-mcp-server/src/cli/router.rs`
**Criteria:** (a) Routed, (b) --help flag, (c) Error on bad input, (d) Has unit tests

## Summary

- **Total routed commands:** 56 (including bootstrap subcommands and inline handlers)
- **All modules declared in mod.rs:** YES (59 modules)
- **All routed commands have tests:** YES (59/59 files have `#[cfg(test)]`)
- **Commands with --help support:** 1/56 (only `infer`)
- **Commands with silent failures on bad input:** 7 flagged

## Status Table

| # | Command | Routed | --help | Error on bad input | Has tests | Notes |
|---|---------|--------|--------|--------------------|-----------|-------|
| 1 | `report` | YES | NO | YES (Err on missing db) | YES (router) | Inline in router.rs |
| 2 | `report-tokens` | YES | NO | YES (delegates) | YES | |
| 3 | `update-state` | YES | NO | YES (Err on <3 args) | YES | |
| 4 | `statusline` | YES | NO | YES (reads stdin) | YES | No args needed |
| 5 | `hard-gate` | YES | NO | YES (Err on <3 args) | YES | |
| 6 | `session-start` | YES | NO | OK (no args needed) | YES | |
| 7 | `metrics-report` | YES | NO | OK (optional arg) | YES | |
| 8 | `token-baseline` | YES | NO | YES (delegates) | YES | |
| 9 | `bootstrap` | YES | NO | YES (delegates) | YES | 4 subcommands |
| 10 | `bootstrap project` | YES | NO | YES (delegates) | YES | |
| 11 | `bootstrap requirements` | YES | NO | YES (delegates) | YES | |
| 12 | `bootstrap roadmap` | YES | NO | YES (delegates) | YES | |
| 13 | `bootstrap state` | YES | NO | YES (delegates) | YES | |
| 14 | `suggest-next` | YES | NO | OK (scans cwd) | YES | |
| 15 | `list-todos` | YES | NO | OK (scans cwd) | YES | |
| 16 | `phase-detect` | YES | NO | OK (scans cwd) | YES | |
| 17 | `detect-stack` | YES | NO | OK (scans cwd) | YES | |
| 18 | `infer` | YES | YES | YES (Err on <4 args) | YES | Only cmd with --help |
| 19 | `planning-git` | YES | NO | **SILENT** | YES | Returns Ok("",0) on missing args |
| 20 | `resolve-model` | YES | NO | YES (Err on <5 args) | YES | |
| 21 | `resolve-turns` | YES | NO | YES (Err on <5 args) | YES | |
| 22 | `log-event` | YES | NO | **SILENT** | YES | Returns Ok("",0) on <4 args |
| 23 | `collect-metrics` | YES | NO | **SILENT** | YES | Returns Ok("",0) on <4 args |
| 24 | `generate-contract` | YES | NO | **SILENT** | YES | Returns Ok("",0) on <3 args |
| 25 | `contract-revision` | YES | NO | **SILENT** | YES | Returns Ok("",0) on <4 args |
| 26 | `assess-risk` | YES | NO | YES (delegates) | YES | |
| 27 | `gate-policy` | YES | NO | YES (delegates) | YES | |
| 28 | `smart-route` | YES | NO | YES (delegates) | YES | |
| 29 | `route-monorepo` | YES | NO | YES (delegates) | YES | |
| 30 | `snapshot-resume` | YES | NO | **SILENT** | YES | Returns Ok("",0) on <2 args |
| 31 | `persist-state` | YES | NO | YES (delegates) | YES | |
| 32 | `recover-state` | YES | NO | YES (delegates) | YES | |
| 33 | `rolling-summary` | YES | NO | YES (delegates) | YES | |
| 34 | `gsd-index` | YES | NO | OK (no args needed) | YES | |
| 35 | `incidents` | YES | NO | YES (Err on <3 args) | YES | |
| 36 | `artifact` | YES | NO | YES (delegates) | YES | |
| 37 | `gsd-summary` | YES | NO | YES (delegates) | YES | |
| 38 | `cache-context` | YES | NO | YES (delegates) | YES | |
| 39 | `cache-nuke` | YES | NO | YES (delegates) | YES | |
| 40 | `delta-files` | YES | NO | YES (structured JSON) | YES | Fixed in Plan 03 |
| 41 | `map-staleness` | YES | NO | YES (delegates to hooks) | YES | |
| 42 | `token-budget` | YES | NO | YES (delegates) | YES | |
| 43 | `lock` | YES | NO | YES (Err on <3 args) | YES | Fixed in Plan 03 |
| 44 | `lease-lock` | YES | NO | YES (delegates) | YES | |
| 45 | `two-phase-complete` | YES | NO | YES (delegates) | YES | |
| 46 | `help-output` | YES | NO | OK (self-documenting) | YES | |
| 47 | `bump-version` | YES | NO | YES (delegates) | YES | |
| 48 | `doctor` | YES | NO | OK (scans cwd) | YES | |
| 49 | `auto-repair` | YES | NO | YES (delegates) | YES | |
| 50 | `rollout-stage` | YES | NO | YES (delegates) | YES | Alias: `rollout` |
| 51 | `verify` | YES | NO | YES (delegates) | YES | |
| 52 | `hook` | YES | NO | YES (Err on <3 args) | YES | Inline in router.rs |
| 53 | `install-hooks` | YES | NO | OK (no args) | YES | |
| 54 | `migrate-config` | YES | NO | YES (Err on <3 args) | YES | Inline in router.rs |
| 55 | `compile-context` | YES | NO | YES (Err on <4 args) | YES | Inline in router.rs |
| 56 | `install-mcp` | YES | NO | YES (checks script) | YES | Inline in router.rs |
| 57 | `migrate-orphaned-state` | YES | NO | YES (Err on <3 args) | YES | |
| 58 | `clean-stale-teams` | YES | NO | OK (no args needed) | YES | |
| 59 | `tmux-watchdog` | YES | NO | OK (no args needed) | YES | |
| 60 | `verify-init-todo` | YES | NO | OK (scans cwd) | YES | |
| 61 | `verify-vibe` | YES | NO | OK (scans cwd) | YES | |
| 62 | `verify-claude-bootstrap` | YES | NO | OK (scans cwd) | YES | |
| 63 | `pre-push` | YES | NO | OK (scans cwd) | YES | |

## Silent Failure Commands (Priority Fixes)

These commands return `Ok(("".to_string(), 0))` when given insufficient arguments, making debugging difficult:

| Command | File | Line | Current behavior | Recommended fix |
|---------|------|------|------------------|-----------------|
| `collect-metrics` | collect_metrics.rs:83 | `args.len() < 4` | Ok("", 0) | Err("Usage: ...") |
| `log-event` | log_event.rs:153 | `args.len() < 4` | Ok("", 0) | Err("Usage: ...") |
| `generate-contract` | generate_contract.rs:261 | `args.len() < 3` | Ok("", 0) | Err("Usage: ...") |
| `contract-revision` | contract_revision.rs:141 | `args.len() < 4` | Ok("", 0) | Err("Usage: ...") |
| `snapshot-resume` | snapshot_resume.rs:10 | `args.len() < 2` | Ok("", 0) | Err("Usage: ...") |

**Note:** `planning-git` also returns `Ok("", 0)` in many code paths, but this is intentional — it's a fire-and-forget commit helper where silent no-ops are the desired behavior (e.g., no git repo, nothing to commit).

## Observations

1. **--help support is nearly absent.** Only `infer` handles `--help`/`-h`. All other 55+ commands lack it. This is low priority since `help-output` provides centralized help.
2. **All modules are routed.** The Plan 04 fixes (verify-init-todo, verify-vibe, pre-push, clean-stale-teams, tmux-watchdog, verify-claude-bootstrap) closed the routing gap.
3. **All 59 command files have test sections.** No module is missing `#[cfg(test)]`.
4. **5 commands have silent failures** on missing required arguments (listed above). These are the highest-priority fixes.
5. **`unwrap_or_default()` usage** is widespread (60+ occurrences) but mostly appropriate — used on optional file reads and JSON parsing where graceful degradation is correct behavior.
