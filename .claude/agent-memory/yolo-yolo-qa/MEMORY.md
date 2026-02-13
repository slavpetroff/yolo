# YOLO QA Agent Memory

## Verification Patterns

- **grep for references with variable prefixes**: `grep "bump-version.sh --verify"` misses `$ROOT/scripts/bump-version.sh --verify`. Use `grep "bump-version.sh.*--verify"` for flexible matching.
- **Exit code capture in pipes**: `echo '...' | bash script.sh; echo "EXIT: $?"` may not print the exit code after a pipe. Use `&& echo PASS || echo FAIL` instead.
- **Hook convention**: PostToolUse hooks use `set -u` (not `set -e`), always exit 0, output via `hookSpecificOutput.additionalContext` JSON. Standalone scripts (detect-stack, pre-push) use `set -eo pipefail`.
- **Non-blocking invariant**: `grep -c "exit [^0]"` is a reliable check for non-blocking hook compliance.

## Project Structure

- 4 version files: VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json, marketplace.json
- Hooks in hooks/hooks.json use cache resolution pattern: `ls | sort -V | tail -1`
- Convention file: `.yolo-planning/codebase/CONVENTIONS.md`
- Plans at: `.yolo-planning/phases/{phase-name}/{plan}-PLAN.md`
- Summaries at: `.yolo-planning/phases/{phase-name}/{plan}-SUMMARY.md`

## Phase 1 Status

- All 3 plans verified PASS (25/25 checks) on 2026-02-09
- Verification written to `.yolo-planning/phases/01-silent-failure-remediation/01-VERIFICATION.md`
