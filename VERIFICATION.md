---
phase: 06-stale-team-cleanup-in-doctor
tier: standard
result: FAIL
passed: 10
failed: 2
total: 12
date: 2026-02-15
---

## Must-Have Checks

| # | Truth/Condition | Status | Evidence |
|---|----------------|--------|----------|
| 1 | doctor-cleanup.sh scan mode has all 4 categories | PASS | scan_stale_teams, scan_orphaned_processes, scan_dangling_pids, scan_stale_markers all present and called in scan mode |
| 2 | doctor-cleanup.sh cleanup mode has all 4 cleanup functions | PASS | cleanup_stale_teams, cleanup_orphaned_processes, cleanup_dangling_pids, cleanup_stale_markers all present and called |
| 3 | Output format is `{category}\|{item}\|{detail}` | PASS | All scan functions output correct format: stale_team\|...\|..., orphan_process\|...\|..., dangling_pid\|...\|..., stale_marker\|...\|... |
| 4 | Cross-platform stat (macOS/Linux) | PASS | get_mtime() function checks OSTYPE for darwin vs Linux, uses stat -f %m vs stat -c %Y |
| 5 | Fail-silent on individual items | PASS | Uses `2>/dev/null \|\| true` pattern, graceful continue on errors |

## Artifact Checks

| Artifact | Exists | Contains | Status |
|----------|--------|----------|--------|
| scripts/doctor-cleanup.sh | YES | 252 lines, scan/cleanup modes, all 4 categories | PASS |
| scripts/clean-stale-teams.sh | YES | Atomic cleanup, logging, pairs tasks with teams | PASS |
| commands/doctor.md | YES | Extended to 15 checks (was 10), runtime health section | PASS |
| scripts/resolve-claude-dir.sh | YES | Sourced in doctor-cleanup.sh line 17 | PASS |

## Anti-Pattern Scan

| Pattern | Found | Location | Severity |
|---------|-------|----------|----------|
| `local` keyword outside function | YES | doctor-cleanup.sh:234-237 (cleanup case block) | CRITICAL |
| Unquoted variables | NO | All variables properly quoted | - |
| Missing error handling | NO | Proper guards: `[ ! -d ] && return`, `[ -z ] && continue` | - |
| Empty file edge cases | NO | Proper checks for empty inbox dirs, missing PID files | - |

## Convention Compliance

| Convention | File | Status | Detail |
|-----------|------|--------|--------|
| set -euo pipefail for critical scripts | doctor-cleanup.sh | PASS | Line 2: set -euo pipefail |
| set -euo pipefail for critical scripts | clean-stale-teams.sh | PASS | Line 8: set -euo pipefail |
| Kebab-case script naming | doctor-cleanup.sh, clean-stale-teams.sh | PASS | Both follow pattern |
| jq for JSON parsing (N/A) | - | SKIP | No JSON parsing in these scripts |
| Source resolve-claude-dir.sh | doctor-cleanup.sh | PASS | Line 17 sources the canonical resolver |

## Additional Checks

| Check | Status | Evidence |
|-------|--------|----------|
| doctor.md checks 11-15 exist | PASS | Lines 55-74 define runtime health checks 11-15 |
| doctor.md has cleanup section | PASS | Lines 101-110 define --cleanup behavior and preview |
| ISO 8601 timestamps | PASS | Line 35: date -u +"%Y-%m-%dT%H:%M:%SZ" |
| No regressions to existing 10 checks | PASS | Original checks 1-10 preserved, diff shows only additions |
| Pattern consistency with VBW scripts | PARTIAL | Logging, fail-silent, platform detection all match patterns, BUT local keyword issue breaks consistency |
| Numeric PID validation | PASS | Lines 84, 166: grep -qE '^[0-9]+$' before kill -0 |
| Process existence validation | PASS | kill -0 used correctly at lines 86, 97, 149, 168, 197 |

## Summary

Tier: standard
Result: FAIL
Passed: 10/12
Failed: [local-keyword-outside-function, shellcheck-SC2168-errors]

### Critical Issues

**1. Local keyword used outside function (SC2168)**
- Lines 234-237 use `local` in case block, not in a function
- This causes runtime error: "bash: local: can only be used in a function"
- Variables will fail to initialize, causing cleanup mode to break
- Fix: Remove `local` keyword or wrap cleanup logic in a function

**2. Shellcheck errors**
- 4 SC2168 errors at lines 234-237
- Multiple SC2155 warnings about declare-and-assign masking return values (non-critical)

### Positive Findings

- All 4 scan categories implemented correctly
- All 4 cleanup functions present
- Output format consistent
- Cross-platform stat handling correct
- Fail-silent patterns properly used
- doctor.md extended from 10 to 15 checks as required
- Cleanup section with --cleanup flag documented
- ISO 8601 timestamps implemented
- resolve-claude-dir.sh sourced correctly
- No regressions to existing checks
- Proper edge case handling for empty files, missing directories

### Verification Notes

- Syntax check passes (bash -n)
- Shellcheck identifies the local keyword bug immediately
- Manual bash test confirms: `local` in case block fails at runtime
- All other patterns follow VBW conventions correctly
- The bug is isolated to lines 234-237, fix is straightforward

---

# VBW Hook Bash Classifier Verification (REQ-10)

**Date:** 2026-02-19
**Requirement:** REQ-10 — Audit bash permission patterns against CC 2.1.47's stricter classifier
**Claude Code Version:** 2.1.47
**Result:** ✅ PASS — All patterns validated, no changes required

## Summary

Audited all 26 VBW hook bash commands in `hooks/hooks.json` against Claude Code 2.1.47's stricter bash permission classifier. All patterns pass validation without requiring modifications.

## Test Coverage

### Patterns Validated

- **Hook count:** 26 hook entries across 11 event types
- **Unique scripts:** 21 unique hook scripts
- **Common pattern:** All hooks use identical dual-resolution wrapper pattern

### Key Findings

1. **Wrapper Pattern is Classifier-Safe**
   - Version-sorted plugin cache resolution: `ls -1 | sort -V | tail -1`
   - Safe piping: ls → sort → tail (auto-allowed by classifier)
   - Dual fallback: cache → CLAUDE_PLUGIN_ROOT
   - Graceful exit 0 on missing target

2. **bash-guard.sh Pattern Matching is Safe**
   - Uses `grep -iqE` with patterns from trusted config files
   - Pattern files (`config/destructive-commands.txt`) are stripped of comments/empty lines
   - No user input in pattern construction
   - jq JSON parsing with safe defaults: `.tool_input.command // ""`
   - stdin via `cat`, not complex substitution
   - Correct PreToolUse contract: exit 0 (allow), exit 2 (block)

3. **Script Invocations are Simple**
   - All arguments are literal strings (no nested command substitution)
   - Examples: `agent-health.sh start`, `skill-hook-dispatch.sh PostToolUse`
   - No inline piping in script invocations (only in wrapper resolution)

4. **Integration Tests Confirm End-to-End Functionality**
   - hook-wrapper.sh successfully executes bash-guard.sh
   - bash-guard.sh correctly blocks destructive patterns (exit 2)
   - bash-guard.sh correctly allows safe commands (exit 0)
   - No permission prompts observed during test execution

## Test Results

**New test file:** `tests/hooks-bash-classifier.bats`
**Test count:** 55 tests
**Pass rate:** 100% (55/55)

### Test Categories

1. **Pattern Documentation** (21 tests) — Verify all 21 unique scripts documented
2. **Hook Resolution** (8 tests) — Validate wrapper pattern components
3. **Script Invocation** (7 tests) — Test individual script invocation patterns
4. **bash-guard.sh Audit** (9 tests) — Validate pattern matching safety
5. **Integration Tests** (6 tests) — End-to-end execution under CC 2.1.47
6. **Manual Test Procedure** (1 test) — Documented reproducible test steps

## Conclusion

**No changes required to hooks.json.** All VBW hook bash patterns are compatible with Claude Code 2.1.47's stricter bash permission classifier.

The dual-resolution wrapper pattern, bash-guard.sh pattern matching logic, and all 21 hook script invocations pass validation without requiring adjustments.

## Evidence

- **BATS test suite:** `tests/hooks-bash-classifier.bats` (55 tests, all passing)
- **Integration test procedure:** Documented in test file for future CC version validation
- **Git commits:**
  - a5d0881 — Document hook patterns
  - c7f86f5 — Validate hook-wrapper.sh resolution
  - 45e592e — Validate script invocations
  - 687339e — Audit bash-guard.sh
  - aaf1062 — Integration tests

## Recommendations

1. **Continue running integration tests** on future Claude Code releases to detect classifier changes
2. **Monitor `.vbw-planning/.hook-errors.log`** for any hook execution failures in production
3. **No immediate action required** — all patterns validated as safe
