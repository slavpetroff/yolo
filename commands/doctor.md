---
name: yolo:doctor
category: supporting
disable-model-invocation: true
description: Run health checks on YOLO installation and project setup.
allowed-tools: Read, Bash, Glob, Grep
---

# YOLO Doctor

## Context

Working directory: `!`pwd``
Version: `!`cat VERSION 2>/dev/null || echo "none"``

## Checks

Run ALL checks below. For each, report PASS or FAIL with a one-line detail.

### 1. jq installed
`jq --version 2>/dev/null || echo "MISSING"`
FAIL if missing: "Install jq: brew install jq (macOS) or apt install jq (Linux)"

### 2. VERSION file exists
Check `VERSION` in repo root. FAIL if missing.

### 3. Version sync
`yolo bump-version --verify 2>&1`
FAIL if mismatch detected.

### 4. Plugin cache present
Check `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/cache/yolo-marketplace/yolo/` exists and has at least one version directory. FAIL if empty or missing.

### 5. hooks.json valid
Parse `hooks/hooks.json` with `jq empty`. FAIL if parse error.

### 6. Agent files present
Glob `agents/yolo-*.md`. Expect 5 files (lead, dev, debugger, architect, docs). FAIL if any missing.

### 7. Config valid (project only)
If `.yolo-planning/config.json` exists, parse with `jq empty`. FAIL if parse error. SKIP if no project initialized.

### 8. Scripts executable
Check that the `yolo` binary exists at `$HOME/.cargo/bin/yolo` and is executable.

### 9. gh CLI available
`gh --version 2>/dev/null || echo "MISSING"`
WARN if missing: "Install gh for /yolo:release GitHub integration."

### 10. sort -V support
`echo -e "1.0.2\n1.0.10" | sort -V 2>/dev/null | tail -1`
PASS if result is "1.0.10". WARN if sort -V unavailable (fallback will be used).

### Runtime Health

### 11. Stale teams
Run `yolo doctor-cleanup scan 2>/dev/null` and count lines starting with `stale_team|`.
PASS if 0. WARN if any, show count.

### 12. Orphaned processes
Count lines starting with `orphan_process|` from the scan output.
PASS if 0. WARN if any, show count.

### 13. Dangling PIDs
Count lines starting with `dangling_pid|` from the scan output.
PASS if 0. WARN if any, show count.

### 14. Stale markers
Count lines starting with `stale_marker|` from the scan output.
PASS if 0. WARN if any, list which markers.

### 15. Watchdog status
If $TMUX is set, check if .yolo-planning/.watchdog-pid exists and process is alive via kill -0.
PASS if alive or not in tmux. WARN if dead watchdog in tmux.

## Output Format

```
YOLO Doctor v{version}

  1. jq installed          {PASS|FAIL} {detail}
  2. VERSION file          {PASS|FAIL}
  3. Version sync          {PASS|FAIL} {detail}
  4. Plugin cache          {PASS|FAIL} {detail}
  5. hooks.json valid      {PASS|FAIL}
  6. Agent files           {PASS|FAIL} {count}/5
  7. Config valid          {PASS|FAIL|SKIP}
  8. Scripts executable    {PASS|WARN} {detail}
  9. gh CLI                {PASS|WARN}
 10. sort -V support       {PASS|WARN}
 11. Stale teams          {PASS|WARN} {count}
 12. Orphaned processes   {PASS|WARN} {count}
 13. Dangling PIDs        {PASS|WARN} {count}
 14. Stale markers        {PASS|WARN} {markers}
 15. Watchdog status      {PASS|WARN}

Result: {N}/15 passed, {W} warnings, {F} failures
```

Use checkmark for PASS, warning triangle for WARN, X for FAIL.

### Cleanup

If any WARN from checks 11-14:
- Show cleanup preview listing all findings
- Display: "Run `/yolo:doctor --cleanup` to apply cleanup"

If user invoked with `--cleanup` (check for this in the command arguments):
- Run `yolo doctor-cleanup cleanup 2>&1`
- Report what was cleaned
- Show updated counts
