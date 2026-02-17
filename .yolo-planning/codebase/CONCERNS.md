# YOLO Technical Concerns & Risk Assessment

Known limitations, technical debt, security considerations, and areas requiring monitoring.

## Critical Rules & Enforcement

### 1. NEVER Bypass /yolo:go Invocation
**Severity:** CRITICAL | **Date identified:** 2026-02-14 | **Status:** ENFORCED

**Concern:** Claude dismissed go.md as "not a workflow" and proceeded ad-hoc.

**Mitigation:**
- CLAUDE.md explicitly states: "NEVER bypass /yolo:go"
- All mode detection happens in go.md
- /yolo:debug, /yolo:fix, /yolo:research route through go.md
- Agent.disallowedTools includes EnterPlanMode, ExitPlanMode

### 2. EnterPlanMode / ExitPlanMode Strictly Prohibited
**Severity:** CRITICAL | **Date identified:** 2026-02-14 | **Status:** ENFORCED

**Concern:** Claude Code's built-in plan mode bypasses the YOLO 11-step workflow.

**Mitigation:** All agent.disallowedTools forbids these tools. CLAUDE.md rules this out.

### 3. No Ad-hoc Agent Spawning Outside YOLO Hierarchy
**Severity:** HIGH | **Date identified:** 2026-02-14 | **Status:** ENFORCED

**Concern:** Task tool to spawn custom agents breaks routing, escalation, and context isolation.

**Mitigation:** All agents spawned via /yolo:go -> lead -> specialist agents. File-guard.sh blocks undeclared modifications.

## Version Synchronization

**Severity:** MEDIUM | **Status:** AUTOMATED

Three files must stay in sync: VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json.

**Tools:** `scripts/bump-version.sh --verify` and `--set X.Y.Z`. Pre-push hook enforces. validate-commit.sh warns.

## QA Gate System (NEW in 0.2.x)

**Severity:** MEDIUM | **Date identified:** 2026-02-18 | **Status:** DEPLOYED

**Concern:** Three-level gate system (post-task, post-plan, post-phase) adds new failure modes. Flock-based serialization required in teammate mode.

**Implementation:**
- Post-task gate (qa-gate-post-task.sh): Scoped test execution after each Dev task, 30s timeout
- Post-plan gate (qa-gate-post-plan.sh): Full suite + must-have coverage check, 300s timeout
- Post-phase gate (qa-gate-post-phase.sh): Verification gate contract validation before QA agent spawn
- Result persistence: .qa-gate-results.jsonl (append-only, flock-serialized, jq-parseable JSONL)
- Config controls: qa_gates.{post_task, post_plan, post_phase} booleans, timeout_seconds, failure_threshold enum

**Mitigation:**
- All gates fail-open on infrastructure missing (bats not found, test-summary.sh missing)
- Timeout handling via run_with_timeout wrapper (handles missing timeout/gtimeout on macOS)
- Scoped mode (--scope flag) maps source files -> test files via naming convention
- Lock contention: exponential backoff (200ms base, 2x multiplier) with 5 max retries
- Config resolution: resolve-qa-config.sh merges project config with defaults, null-safe jq checks

**Risk:** Gate results drive remediation routing (Dev fix loop vs Senior escalation). Test failures in scope mode could miss unrelated regressions. Mitigated by --effort=balanced default (runs full suite post-plan).

## Review Ownership Enforcement (NEW in 0.2.x)

**Severity:** MEDIUM | **Date identified:** 2026-02-18 | **Status:** ENFORCED

**Concern:** 16 reviewing agents must take personal ownership of subordinate output. Non-reviewing agents must be excluded.

**Implementation:**
- All 16 reviewing agents (Senior, Lead, Architect, Owner, QA, QA-Code x 3 depts) have ## Review Ownership sections
- Sections reference review-ownership-patterns.md for ownership language templates
- Static test `agent-review-ownership.bats` validates coverage

**Mitigation:**
- Ownership matrix in review-ownership-patterns.md maps agent -> artifact -> review authority -> step
- Templates enforce: analyze thoroughly, document reasoning, escalate conflicts, no rubber-stamp approvals
- Violations caught by CI static tests

## Escalation Timeout System (NEW in Phase 5)

**Severity:** MEDIUM | **Date identified:** 2026-02-18 | **Status:** IMPLEMENTED

**Concern:** Timeout-based auto-escalation (300s default) may produce false positives for complex design decisions or be too lenient for simple clarifications. Unbounded escalation array could grow in long-running phases.

**Implementation:**
- Configurable timeout via escalation.timeout_seconds in config/defaults.json
- Per-level tracking prevents premature escalation (level + last_escalated_at fields)
- max_round_trips (default 2) caps per-escalation bounce
- check-escalation-timeout.sh reads state and config, returns structured JSON
- Escalation state committed immediately to .execution-state.json (crash recovery)

**Mitigation:**
- Timeout configurable per project (300s default, can increase for complex projects)
- Auto-escalation only fires if current level has NOT already escalated upward
- Resolved escalations marked (not removed) for audit trail
- escalations array is per-phase (reset each phase), post-phase cleanup can archive
- User response to AskUserQuestion has no timeout (blocks until answered)

**Risk:** Short timeout for complex Architect decisions. Mitigated by: timeout triggers escalation to next level (adds context), not auto-resolution. By user level, question should be concrete with options.

## Teammate API Stability

**Severity:** MEDIUM | **Date identified:** 2026-02-16 | **Status:** MITIGATED

**Concern:** Teammate API is experimental (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var). API may change or become unavailable.

**Mitigation:**
- 3-tier fallback cascade: Teammate API -> Task tool -> Error (terminal)
- `resolve-team-mode.sh` validates env var and config before activating
- `team_mode=auto` defaults to task mode when env var is absent
- Per-department fallback isolation (one department's failure doesn't cascade)
- Circuit breaker pattern in Lead agent: 2 failures = open, probe after 5 minutes
- Health tracking via SendMessage response patterns (no custom heartbeat)
- All 876 tests pass in both task and teammate modes

**Risk:** Mid-execution Teammate API failure could leave orphan teams or summary.jsonl corruption.
**Mitigation:** Shutdown protocol with 30s deadline, timeout logging, force-proceed with artifact verification. Summary ownership split: task mode = Dev writes, teammate mode = Lead writes (Dev skips Stage 3).

## Context Isolation (GSD vs YOLO)

**Severity:** MEDIUM | **Status:** MONITORED

GSD uses `.planning/`, YOLO uses `.yolo-planning/`. Enforced by hooks. CLAUDE.md instructs to ignore `<codebase-intelligence>` tags from GSD.

## Plugin Cache Resolution & Versioning

**Severity:** MEDIUM | **Status:** IMPLEMENTED

Cache: `~/.claude/plugins/cache/yolo-marketplace/yolo/{version}/`. Resolution: `ls | sort -V | tail -1`. Vdir: `/tmp/yolo-vdir-$(id -u)`.

## Hook Graceful Degradation (DXP-01)

**Severity:** LOW-MEDIUM | **Status:** MITIGATED

PreToolUse: fail-closed for security (security-filter.sh denies on parse failure). file-guard.sh: fail-open. qa-gate.sh: fail-open (structural checks only). All errors logged to .hook-errors.log.

## Department Cross-Communication

**Severity:** MEDIUM | **Status:** ENFORCED (Backend Only)

department-guard.sh blocks cross-dept writes. Only Backend currently active (frontend: false, uiux: false). Multi-department not yet E2E tested.

Cross-team communication in teammate mode: ALWAYS file-based (SendMessage only works within a team). This is by design for context isolation.

## Dynamic Persona System

**Severity:** LOW | **Date identified:** 2026-02-16 | **Status:** IMPLEMENTED

**Concern:** Project type detection uses weighted pattern matching; edge cases may misclassify.
**Mitigation:** Generic fallback always available. User can override via config.

## Reference Package Staleness

**Severity:** LOW | **Date identified:** 2026-02-16 | **Status:** MONITORED

**Concern:** Pre-compiled `references/packages/{role}.toon` could become stale if source protocols change.
**Mitigation:** `build-reference-packages.sh` regenerates from source. Not auto-triggered.

## Verification Gate Contract

**Severity:** CRITICAL | **Date identified:** 2026-02-16 | **Status:** ENFORCED

Entry gates verify predecessor artifacts. Exit gates commit state. Skip gates track reason. Mandatory on every step -- no exceptions for fast/turbo. 11 steps tracked in enforcement contract table (execute-protocol.md). validate-gates.sh enforces contract per step.

## summary.jsonl Ownership Split

**Severity:** MEDIUM | **Date identified:** 2026-02-17 | **Status:** ENFORCED

**Concern:** In teammate mode, multiple Devs could conflict on summary.jsonl writes.

**Mitigation:** Clean ownership split:
- task mode: Dev writes summary.jsonl (unchanged)
- teammate mode: Lead aggregates task_complete messages and writes summary.jsonl (Dev skips Stage 3)
- In both modes, exactly one agent writes summary.jsonl per plan

## FLock Serialization in Teammate Mode

**Severity:** MEDIUM | **Status:** IMPLEMENTED

**Concern:** Concurrent Dev task completions could race on .qa-gate-results.jsonl writes.

**Mitigation:**
- qa-gate-post-task.sh uses flock (or mkdir fallback) with exponential backoff
- Max 5 retries, 200ms base delay, 2x multiplier (max ~3.2s total)
- Non-fatal lock failure: logs warning to stderr, continues (fail-open)
- Results file is append-only

## Security Considerations

### Secrets Handling -- GOOD
security-filter.sh blocks .env, .pem, .key, .p12, credentials, tokens. Fails-closed on parse error.

### Hook Input Validation -- GOOD
All hooks use jq for JSON parsing (fail-safe). security-filter.sh fails-closed on jq errors.

### Plugin Cache Permissions -- NEEDS MONITORING
Per-user vdir cache at `/tmp/yolo-vdir-$(id -u)`. Multi-user systems could have /tmp leakage.

### Agent Tool Restrictions -- GOOD
Each agent has explicit allowedTools list. Tool permissions now project-type-aware via tool-permissions.json.

### Serialized Commit Safety -- GOOD
flock-based locking in git-commit-serialized.sh prevents index.lock conflicts in parallel Dev execution.

## Known Limitations

1. **Single Branch Per Project** -- YOLO commits to main (no branch-per-milestone). Config option reserved for future.
2. **Context Regeneration Per Run** -- .toon files regenerated per execute. Reference packages reduce this for role context.
3. **No Built-in Rollback** -- Phase completion requires manual git operations to undo.
4. **GSD Import One-Way** -- Moving .planning/ to .yolo-planning/gsd-archive/ is irreversible.
5. **No Custom Agent Roles** -- Fixed roster of 26 agents across 4 departments.
6. **Teammate API Experimental** -- Depends on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var. Not yet GA.
7. **QA Gate Human Output** -- Symbols and formatting defined in qa-output-patterns.md but not yet wired into Notification hook display.
8. **Test Coverage in Scope Mode** -- Scoped post-task gates use filename matching; may miss unrelated regressions.

## Recommendations

### High Priority (Before 1.0)
1. Complete multi-department E2E tests (including teammate mode)
2. Implement /yolo:rollback command
3. Add security audit enforcement for critical projects
4. Auto-rebuild reference packages when source protocols change
5. Wire human-readable gate output (qa-output-patterns.md symbols) into Notification hook

### Medium Priority
1. Monitor hook error logs for patterns
2. Add cache invalidation strategy for .toon files
3. Implement context compression for large codebases
4. Live integration testing with Teammate API (beyond mocks)
5. Test coverage expansion: full E2E with FE/UX departments

### Low Priority
1. Branch-per-milestone mode
2. Rollback snapshot feature
3. Agent customization UI
4. Cross-project learning

---
