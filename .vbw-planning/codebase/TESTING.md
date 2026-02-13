# Testing Infrastructure

## Formal Test Suite

There is no formal test suite. The project has no unit tests, integration tests, or end-to-end test framework. No test runner is configured (no jest, vitest, pytest, bats, or similar).

## Verification as Testing

YOLO replaces traditional testing with a multi-layered verification system:

### Continuous Verification (Hooks)

| Hook | Script | What It Checks |
|------|--------|----------------|
| PostToolUse (Write/Edit) | validate-summary.sh | SUMMARY.md structure: frontmatter, required sections |
| PostToolUse (Write/Edit) | validate-frontmatter.sh | YAML frontmatter validity |
| PostToolUse (Bash) | validate-commit.sh | Commit message format `{type}({scope}): {desc}` |
| PostToolUse (Write/Edit/Bash) | state-updater.sh | Auto-update STATE.md, ROADMAP.md progress |
| PreToolUse (Read/Glob/Grep/Write/Edit) | security-filter.sh | Block access to sensitive files |
| PreToolUse (Write/Edit) | file-guard.sh | Block undeclared file modifications |
| TeammateIdle | qa-gate.sh | SUMMARY.md completeness gap detection |
| TaskCompleted | task-verify.sh | Task completion verification |

### On-Demand Verification (/yolo:qa)

Three-tier system defined in `references/verification-protocol.md`:

| Tier | Checks | Scope |
|------|--------|-------|
| Quick | 5-10 | Artifact existence, frontmatter, key strings, no placeholders |
| Standard | 15-25 | + Structure, links, imports, conventions, anti-patterns |
| Deep | 30+ | + Requirement mapping, cross-file consistency, dead code |

Tier auto-selection based on effort level:
- turbo = skip, fast = quick, balanced = standard, thorough = deep
- Override: >15 requirements or last phase before ship forces Deep

### Goal-Backward Methodology

Verification starts from desired outcomes, not from code:
1. Extract must_haves from PLAN.md (truths, artifacts, key_links)
2. Derive testable conditions from success criteria
3. Execute checks against actual artifacts
4. Classify PASS/FAIL/PARTIAL with evidence

### Self-Review (Lead Agent)

The yolo-lead agent performs self-review during planning (Stage 3):
- Requirements coverage
- No circular dependencies
- No same-wave file conflicts
- Success criteria union = phase goals
- 3-5 tasks per plan
- Context refs present

## Version Sync Verification

`bump-version.sh --verify` checks version consistency across:
- VERSION
- .claude-plugin/plugin.json
- marketplace.json
- CHANGELOG.md

This is triggered by the validate-commit.sh hook when working on the YOLO plugin itself.

## Pre-Push Hook

`scripts/pre-push-hook.sh` installed via `scripts/install-hooks.sh` as a git pre-push hook. Provides a gate before pushing to remote.

## What's Missing

- No shell script testing (no bats/shunit2)
- No mock framework for hook stdin/JSON testing
- No CI/CD pipeline (no .github/workflows)
- No linting (no shellcheck)
- No coverage metrics
- No snapshot testing for command output
- No regression test for hook behavior changes
