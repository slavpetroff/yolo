# 03-03 FINDINGS: Test Coverage Gap Analysis and Defaults Audit

## Task 1: Command Coverage Matrix

Cross-reference of 23 command markdown files (`commands/*.md`) against 72 bats test files (`tests/*.bats`).

### Coverage Matrix

| # | Command | Dedicated Test File | Indirect Coverage | Status |
|---|---------|-------------------|-------------------|--------|
| 1 | `config` | `config-read.bats`, `config-migration.bats` | Multiple test files reference config | **Covered** |
| 2 | `debug` | None | `hard-gates.bats` references debug context | **Indirect only** |
| 3 | `discuss` | None | No test references found | **No coverage** |
| 4 | `doctor` | None | No test references found | **No coverage** |
| 5 | `fix` | None | `qa-commands.bats`, `task-verify.bats` reference fix context | **Indirect only** |
| 6 | `help` | None | `token-economics.bats` references help output | **Indirect only** |
| 7 | `init` | None | `sessionstart-compact-hooks.bats`, `planning-git.bats` exercise init paths | **Indirect only** |
| 8 | `list-todos` | `list-todos.bats` | `persist-state-after-ship.bats` also exercises | **Covered** |
| 9 | `map` | None | `sessionstart-compact-hooks.bats`, `persist-state-after-ship.bats` reference codebase map | **Indirect only** |
| 10 | `pause` | None | No test references found | **No coverage** |
| 11 | `profile` | None | `resolve-agent-model.bats`, `token-budgets.bats` test model profiles | **Indirect only** |
| 12 | `release` | `archive-release.bats` | `mcp-integration.bats` also references release | **Covered** |
| 13 | `research` | `research-persistence.bats`, `discovery-research.bats`, `research-warn.bats` | `tier-cache.bats` | **Covered** |
| 14 | `resume` | None | `runtime-foundations.bats` exercises snapshot-resume | **Indirect only** |
| 15 | `skills` | None | `persist-state-after-ship.bats` references skills section | **Indirect only** |
| 16 | `status` | `statusline-cache-isolation.bats` | Many test files check status | **Covered** |
| 17 | `teach` | None | No test references found | **No coverage** |
| 18 | `todo` | `list-todos.bats` | `persist-state-after-ship.bats`, `discovered-issues-surfacing.bats` | **Covered** |
| 19 | `uninstall` | None | No test references found | **No coverage** |
| 20 | `update` | `update-state.bats`, `state-updater.bats` | `planning-git.bats` | **Covered** |
| 21 | `verify` | `task-verify.bats`, `validate-commit.bats` | `phase0-bugfix-verify.bats` | **Covered** |
| 22 | `vibe` | `vibe-mode-split.bats` | `phase4-integration.bats` | **Covered** |
| 23 | `whats-new` | None | No test references found | **No coverage** |

### Summary

- **Directly tested:** 9 commands (config, list-todos, release, research, status, todo, update, verify, vibe)
- **Indirect coverage only:** 7 commands (debug, fix, help, init, map, profile, resume, skills)
- **No coverage at all:** 6 commands (discuss, doctor, pause, teach, uninstall, whats-new)

### Recommendations

| Command | Priority | Recommendation |
|---------|----------|---------------|
| `doctor` | High | Health-check command with system diagnostics. Should have dedicated tests for each check it performs. |
| `pause` | Medium | State management command. Needs tests for pause/resume state transitions. |
| `resume` | Medium | Companion to pause. Needs tests for resume from various paused states. |
| `teach` | Low | Skill teaching command. Needs basic invocation and output format tests. |
| `uninstall` | Medium | Destructive operation (removes plugin). Needs tests to verify clean removal without side effects. |
| `whats-new` | Low | Changelog display command. Needs basic output format test. |
| `discuss` | Low | Interactive discussion command. Harder to test but could verify prompt generation. |

---

## Task 2: Rust Command Test Coverage

Cross-reference of 79 Rust command modules (`yolo-mcp-server/src/commands/*.rs`) against bats tests that invoke `$YOLO_BIN <command>`.

### Internal/Helper Modules (not CLI commands, no test needed)

- `mod.rs` -- module declarations only
- `utils.rs` -- shared utility functions
- `atomic_io.rs` -- atomic file I/O primitives
- `domain_types.rs` -- shared type definitions
- `feature_flags.rs` -- flag enum and reader (has Rust unit tests)
- `structured_response.rs` -- JSON response helpers

### CLI Commands Tested via Bats (45 commands)

| Rust Module | CLI Command | Test File(s) |
|-------------|-------------|-------------|
| `auto_repair` | `auto-repair` | `hard-gates.bats` |
| `bootstrap_claude` | `bootstrap claude` | `persist-state-after-ship.bats` |
| `bootstrap_project` | `bootstrap project` | `persist-state-after-ship.bats` |
| `bootstrap_requirements` | `bootstrap requirements` | `discovery-research.bats` |
| `bootstrap_state` | `bootstrap state` | `persist-state-after-ship.bats` |
| `bump_version` | (via archive-release flow) | `archive-release.bats` |
| `cache_context` | `compile-context` (cache path) | `tier-cache.bats`, `context-index.bats` |
| `cache_nuke` | `cache-nuke` | `statusline-cache-isolation.bats` |
| `check_regression` | `check-regression` | `phase0-bugfix-verify.bats` |
| `commit_lint` | `commit-lint` | `validate-commit.bats` |
| `compile_progress` | `compile-context` | `compile-progress.bats` |
| `compress_context` | `compile-context` | `tier-cache.bats`, `phase4-integration.bats`, `control-plane.bats` |
| `config_read` | `config-read` | `config-read.bats` |
| `contract_revision` | `contract-revision` | `contract-lite.bats` |
| `delta_files` | `delta-files` | `delta-context.bats` |
| `detect_stack` | `detect-stack` | `detect-stack.bats`, `hooks-isolation-lifecycle.bats` |
| `generate_contract` | `generate-contract` | `hard-gates.bats`, `control-plane.bats` |
| `generate_incidents` | `incidents` | `incidents-generation.bats` |
| `git_state` | `git-state` | `git-state.bats` |
| `hard_gate` | `hard-gate` | `hard-gates.bats`, `flag-gated-code-paths.bats`, `control-plane.bats` |
| `lease_lock` | `lease-lock` | `control-plane.bats`, `advanced-scale.bats` |
| `list_todos` | `list-todos` | `list-todos.bats`, `persist-state-after-ship.bats` |
| `lock_lite` | `lock` | `lock-lite.bats`, `control-plane.bats` |
| `log_event` | `log-event` | `runtime-foundations.bats`, `event-id.bats`, `event-type-validation.bats`, `review-loop.bats` |
| `metrics_report` | `metrics-report` | `metrics-segmentation.bats` |
| `migrate_config` | `migrate-config` | `config-migration.bats`, `schema-validation.bats` |
| `migrate_orphaned_state` | `migrate-orphaned-state` | `persist-state-after-ship.bats` |
| `parse_frontmatter` | `parse-frontmatter` | `parse-frontmatter.bats` |
| `persist_state` | `persist-state` | `persist-state-after-ship.bats` |
| `phase_detect` | `phase-detect` | `phase-detect.bats` |
| `planning_git` | `planning-git` | `planning-git.bats` |
| `recover_state` | `recover-state` | `runtime-foundations.bats` |
| `resolve_model` | `resolve-model` | `resolve-agent-model.bats`, `tier-cache.bats` |
| `resolve_plugin_root` | `resolve-plugin-root` | `resolve-plugin-root.bats` |
| `resolve_turns` | `resolve-turns` | `resolve-agent-max-turns.bats` |
| `review_plan` | `review-plan` | `review-plan.bats`, `review-loop.bats` |
| `rollout_stage` | `rollout-stage` | `rollout-stage.bats` |
| `route_monorepo` | `route-monorepo` | `smart-routing.bats` |
| `session_start` | `session-start` | `flag-gated-code-paths.bats`, `sessionstart-compact-hooks.bats`, `phase4-integration.bats` |
| `smart_route` | `smart-route` | `smart-routing.bats` |
| `snapshot_resume` | `snapshot-resume` | `runtime-foundations.bats` |
| `state_updater` | `update-state` | `state-updater.bats`, `update-state.bats` |
| `statusline` | `statusline` | `statusline-cache-isolation.bats` |
| `token_baseline` | `token-baseline` | `token-baseline.bats` |
| `token_budget` | `token-budget` | `token-budgets.bats` |
| `token_economics_report` | `report-tokens` | `token-economics.bats` |
| `two_phase_complete` | `two-phase-complete` | `two-phase-completion.bats` |
| `validate_requirements` | `validate-requirements` | `discovery-research.bats` |
| `verify` | `verify` (via hooks) | `task-verify.bats` |
| `verify_plan_completion` | `verify-plan-completion` | `phase0-bugfix-verify.bats` |

### CLI Commands with NO Bats Test Coverage (22 modules)

| # | Rust Module | Probable CLI Command | Description | Priority |
|---|-------------|---------------------|-------------|----------|
| 1 | `artifact_registry` | `artifact` | Artifact storage and retrieval | Medium |
| 2 | `assess_plan_risk` | `assess-plan-risk` | Plan risk scoring | Medium |
| 3 | `bootstrap_roadmap` | `bootstrap roadmap` | Roadmap generation | Low |
| 4 | `bump_version` | `bump-version` | Version bumping utility | Low |
| 5 | `clean_stale_teams` | `clean-stale-teams` | Cleanup orphaned team state | Medium |
| 6 | `collect_metrics` | `collect-metrics` | Metrics collection | Low |
| 7 | `compile_rolling_summary` | `compile-rolling-summary` | Rolling summary generation | Low |
| 8 | `diff_against_plan` | `diff-against-plan` | Diff plan vs implementation | Medium |
| 9 | `doctor_cleanup` | `doctor-cleanup` | Doctor remediation actions | High |
| 10 | `generate_gsd_index` | `generate-gsd-index` | GSD index generation | Low |
| 11 | `help_output` | `help` | Help text generation | Low |
| 12 | `infer_gsd_summary` | `infer-gsd-summary` | GSD summary inference | Low |
| 13 | `infer_project_context` | `infer-project-context` | Project context inference | Medium |
| 14 | `install_hooks` | `install-hooks` | Hook installation | Medium |
| 15 | `pre_push_hook` | `pre-push-hook` | Git pre-push validation | Medium |
| 16 | `prune_completed` | `prune-completed` | Prune completed phase artifacts | Low |
| 17 | `resolve_gate_policy` | `resolve-gate-policy` | Gate policy resolution | Low |
| 18 | `suggest_next` | `suggest-next` | Next action suggestion | Low |
| 19 | `tier_context` | `tier-context` | Tier-based context compilation | Low |
| 20 | `tmux_watchdog` | `tmux-watchdog` | Tmux session monitoring | Low |
| 21 | `validate_plan` | `validate-plan` | Plan validation | Medium |
| 22 | `verify_claude_bootstrap` | `verify-claude-bootstrap` | Claude bootstrap verification | Low |
| 23 | `verify_init_todo` | `verify-init-todo` | Init/todo verification | Low |
| 24 | `verify_vibe` | `verify-vibe` | Vibe mode verification | Low |

### Summary

- **Total Rust command modules:** 79
- **Internal helpers (no CLI):** 6 (mod, utils, atomic_io, domain_types, feature_flags, structured_response)
- **CLI commands with bats coverage:** 49
- **CLI commands with no bats coverage:** 24
- **Coverage rate:** 67% of CLI-facing commands tested via bats
- **Note:** Many untested modules have Rust `#[cfg(test)]` unit tests internally, but no integration-level bats test exercises them through the CLI binary

---

## Task 3: Stale and Redundant Test Identification

### Tests Referencing Removed Agent: `yolo-scout`

The `yolo-scout` agent was removed (merged into `yolo-reviewer`), but 3 test files still reference it:

| File | Lines | Impact |
|------|-------|--------|
| `tests/hooks-isolation-lifecycle.bats` | 159, 163-164, 172, 272 | Uses `yolo-scout` as agent_type in SubagentStart hooks. Tests pass because the Rust binary normalizes any agent_type string -- it does not validate against known agents. **Low risk** but misleading. |
| `tests/agent-health.bats` | 52, 56, 60 | Uses `yolo-scout` for health-check registration/idle tests. Same normalization applies. **Low risk.** |
| `tests/typed-protocol.bats` | 56-61, 150-151, 162-163 | Tests `scout_findings` schema and scout role in hierarchy. These test the message-schemas.json file which still defines scout_findings. **Valid if schema still has scout.** |
| `tests/shutdown-protocol.bats` | 186, 215, 225, 269-270 | Iterates over roles including "scout" for shutdown authorization. **Valid if schemas still define scout.** |
| `tests/smart-routing.bats` | 17-36, 57 | Tests scout routing decisions. Scout may still be a valid routing target even without a dedicated agent file. |
| `tests/token-budgets.bats` | 36, 44, 54-56, 80, 87 | Uses `scout` as role for token-budget calculations. Valid as a role name in budgets. |

**Recommendation:** The `yolo-scout` references in `hooks-isolation-lifecycle.bats` and `agent-health.bats` should be updated to use an existing agent (e.g., `yolo-researcher` or `yolo-reviewer`). The typed-protocol and shutdown-protocol tests are valid as long as `message-schemas.json` still includes scout definitions.

### Unconditional Skip Statements

| File | Line | Skip Reason |
|------|------|-------------|
| `tests/schema-validation.bats` | 11 | `skip "yolo binary not found at $YOLO_BIN"` -- Conditional, only triggers when binary is missing. **Valid.** |
| `tests/sessionstart-compact-hooks.bats` | 123 | `skip "PreToolUse hook not configured in hooks.json"` -- Conditional, only triggers when hook config is absent. **Valid.** |

No unconditionally skipped tests found. Both skip statements are guarded by conditions.

### Duplicate/Overlapping Test Coverage

| Files | Overlap | Recommendation |
|-------|---------|---------------|
| `state-updater.bats` (4 tests) / `update-state.bats` (5 tests) | Both test the `update-state` CLI command. `state-updater.bats` was the original (pre-migration name), `update-state.bats` was added post-migration. `state-updater.bats` test "PLAN trigger supports NN-PLAN naming" overlaps with `update-state.bats` "PLAN trigger flips Status ready to active". | **Consolidate** into one file. `update-state.bats` follows the CLI naming convention. Move unique tests from `state-updater.bats` and delete it. |
| `control-plane.bats` / `hard-gates.bats` + `lock-lite.bats` | `control-plane.bats` was migrated from the removed `control-plane.sh`. It exercises `generate-contract`, `hard-gate`, `lock`, `lease-lock`, and `compile-context` which each have their own dedicated test files. | **Low priority.** `control-plane.bats` acts as an integration test combining multiple commands, while the others are unit-level. Keep both. |
| `hooks-isolation-lifecycle.bats` / `role-isolation.bats` / `role-isolation-runtime.bats` | All three test role isolation, but at different levels: hooks-isolation tests the PreToolUse hook, role-isolation tests config/schema definitions, role-isolation-runtime tests runtime enforcement. | **No action needed.** Tests are complementary, not duplicative. |

### Tests Referencing Removed/Changed Features

| File | Issue | Severity |
|------|-------|----------|
| `tests/hooks-isolation-lifecycle.bats:6` | Comment: "Commit format validation was removed in the Rust migration." Test file still exists and has valid tests -- the comment is accurate documentation. | **Informational only** |
| `tests/control-plane.bats:2-3` | Comment: "Migrated: control-plane.sh orchestrator removed." Tests now exercise individual Rust subcommands. | **Informational only** |
| `tests/resolve-claude-dir.bats:2` | Comment: "Migrated: resolve-claude-dir.sh removed." Tests now exercise hooks.json structure and Rust behavior. | **Informational only** |
| `tests/hooks-isolation-lifecycle.bats:144,363,413,449` | Comments reference "self-blocking removed in v1.21.13". Tests verify the removal still holds. | **Valid regression tests** |

### Summary

- **Stale references:** 3 test files reference removed `yolo-scout` agent as test data
- **Unconditional skips:** 0 (both skip statements are conditional)
- **Duplicate coverage:** 1 pair (`state-updater.bats` / `update-state.bats`) should be consolidated
- **Overall health:** Test suite is well-maintained with migration comments documenting why tests were adapted

---

## Task 4: Defaults.json Feature Flag Audit

Six feature flags default to `true` in `config/defaults.json`. This section assesses each for appropriateness.

### 1. `v3_schema_validation: true`

**What it enables:** Validates YAML frontmatter on PLAN and SUMMARY files, and JSON structure on contract files. Implemented in `hooks/validate_schema.rs`. Runs as part of the PreToolUse hook pipeline.

**Behavior when enabled:** Checks that plans have required fields (phase, plan, title, wave, depends_on, must_haves), summaries have (phase, plan, title, status, tasks_completed, tasks_total), and contracts have (phase, plan, task_count, allowed_paths). **Fail-open** -- always exits 0 even on validation failure (logs warning but does not block).

**Side effects:** Adds ~1-2ms per PreToolUse invocation for frontmatter parsing. Zero user-visible impact on failure since it is fail-open.

**Assessment:** **KEEP true.** Fail-open design means no risk of blocking users. Catches malformed plans early. Low overhead.

### 2. `v3_snapshot_resume: true`

**What it enables:** Saves execution state snapshots to `.yolo-planning/.snapshots/` during phase execution and restores them on session resume. Implemented in `commands/snapshot_resume.rs`.

**Behavior when enabled:** `snapshot-resume save <phase>` writes JSON snapshot. `snapshot-resume restore <phase>` reads it back. When disabled, commands silently return empty string with exit 0.

**Side effects:** Creates snapshot files (JSON, typically <10KB each) in `.yolo-planning/.snapshots/`. These accumulate per phase/agent but are within `.yolo-planning/` (gitignored). No user-facing prompts or behavior changes.

**Assessment:** **KEEP true.** Session resume is a core reliability feature. Disk usage is negligible. Silent no-op when disabled means toggling is safe.

### 3. `v3_lease_locks: true`

**What it enables:** Defined in `FeatureFlag` enum and reported during session-start. The `lease_lock.rs` command does NOT check this flag internally -- it always operates. The flag serves as a session-start reporting indicator and external orchestration signal.

**Behavior when enabled:** `lease-lock acquire/release/check` commands work regardless of this flag. session-start reports `v3_lease_locks=true/false` in its cache output. `task_lease_ttl_secs` (default 300s) controls lease expiry.

**Side effects:** Creates lock files in `.yolo-planning/.locks/`. Leases auto-expire based on TTL.

**Assessment:** **KEEP true.** The flag is a session-start reporting hint, not a gate. Lease locks prevent concurrent file conflicts in team mode. No downside to having it enabled.

### 4. `v3_event_recovery: true`

**What it enables:** Rebuilds `.execution-state.json` from event log and SUMMARY files. Implemented in `commands/recover_state.rs`. Gated -- command checks `v3_event_recovery` flag and returns `recovered: false` if disabled.

**Behavior when enabled:** `recover-state <phase>` scans event logs and SUMMARY files to reconstruct execution state. Used for crash recovery.

**Side effects:** Reads event log and summary files (I/O). Has a hard dependency: **requires `v3_event_log` to be enabled**, otherwise recovery finds no events. Currently `v3_event_log` defaults to `false` in defaults.json.

**Assessment:** **CHANGE to false.** This flag has a dependency on `v3_event_log` which defaults to `false`. Enabling recovery without event logging is misleading -- `session-start` emits a WARNING but recovery silently returns "no events found". The flag should match `v3_event_log`'s default (both false) until the user explicitly enables event logging.

### 5. `v2_typed_protocol: true`

**What it enables:** Validates event types in `log-event` against an allowlist of ~30 known types. Implemented in `commands/log_event.rs` line 76-81. Also gates message validation in `hooks/validate_message.rs`.

**Behavior when enabled:** Unknown event types are rejected with a WARNING and the event is NOT written. Messages are validated against schema definitions.

**Side effects:** Blocks custom/experimental event types. If a new event type is added to code but not to the allowlist, it gets silently dropped with a stderr warning.

**Assessment:** **KEEP true with caveat.** Type validation catches typos and ensures event log consistency. However, the allowlist is hardcoded in Rust (not configurable). New event types require a code change. This is acceptable for a plugin that controls its own event vocabulary, but should be documented for contributors.

### 6. `v2_token_budgets: true`

**What it enables:** Per-role token budget enforcement. Implemented in `commands/token_budget.rs`. Gated -- returns `skip, v2_token_budgets=false` when disabled.

**Behavior when enabled:** `token-budget <role> <file>` measures content against role-specific budgets from `config/token-budgets.json`. Default budget is 32,000 chars per role. Returns whether content is within budget and applies truncation if overage.

**Side effects:** Active truncation of context sent to agents. If budgets are set too low, agents receive incomplete context. Depends on `config/token-budgets.json` for per-role customization (falls back to defaults if missing).

**Assessment:** **KEEP true.** Token budgets prevent runaway context costs. The 32K default is generous for most roles. Users can customize via `config/token-budgets.json`. The feature degrades gracefully (uses defaults when config missing).

### Flag Dependency Matrix

| Flag | Depends On | Dependency Satisfied in Defaults? |
|------|-----------|-----------------------------------|
| `v3_schema_validation` | None | N/A |
| `v3_snapshot_resume` | None | N/A |
| `v3_lease_locks` | None (informational) | N/A |
| `v3_event_recovery` | `v3_event_log` | **NO** (`v3_event_log` defaults to `false`) |
| `v2_typed_protocol` | `v3_event_log` (for event validation) | No, but typed_protocol also covers messages |
| `v2_token_budgets` | None | N/A |

### Recommendations Summary

| Flag | Current | Recommendation | Rationale |
|------|---------|---------------|-----------|
| `v3_schema_validation` | `true` | **Keep** | Fail-open, low overhead, catches errors early |
| `v3_snapshot_resume` | `true` | **Keep** | Core reliability, negligible cost |
| `v3_lease_locks` | `true` | **Keep** | Informational flag, no gate behavior |
| `v3_event_recovery` | `true` | **Change to `false`** | Dependency `v3_event_log` is `false`; recovery without events is a no-op that misleads |
| `v2_typed_protocol` | `true` | **Keep** | Prevents event/message type drift, low friction |
| `v2_token_budgets` | `true` | **Keep** | Prevents runaway costs, generous defaults |

---

## Task 5: Schema Validation Test Adequacy Assessment

### Current Test Coverage (4 tests in `schema-validation.bats`)

| # | Test Name | What It Covers |
|---|-----------|---------------|
| 1 | `migrate-config rejects config with invalid effort type` | Type validation: integer where string expected |
| 2 | `migrate-config accepts valid config` | Happy path: minimal valid config |
| 3 | `migrate-config rejects unknown keys` | `additionalProperties: false` enforcement |
| 4 | `defaults.json validates against config.schema.json via migrate-config` | Self-consistency: defaults.json is valid |

### Schema Surface Area Not Tested

The schema (`config/config.schema.json`) defines 48 properties across 5 types:

- **10 enum-typed string fields** (effort, autonomy, planning_tracking, auto_push, verification_tier, visual_format, prefer_teams, model_profile, review_gate, qa_gate)
- **5 bounded integer fields** (max_tasks_per_plan [1-10], review_max_cycles [1-10], qa_max_cycles [1-10], command_timeout_ms [min 1000], task_lease_ttl_secs [min 1])
- **22 boolean flags** (all v2_*/v3_*/v4_* flags, plus auto_commit, skill_suggestions, etc.)
- **3 object fields** (agent_max_turns with integer sub-properties, custom_profiles, model_overrides)
- **1 array field** (qa_skip_agents)
- **2 freeform string fields** (active_profile)

### Recommended Additional Test Cases (Priority Order)

**High Priority -- Enum Field Validation (5 tests)**

| # | Test Case | Rationale |
|---|-----------|-----------|
| 1 | `effort` with invalid enum value (e.g., `"effort": "extreme"`) | Only type-level validation tested (int vs string), not enum-level |
| 2 | `autonomy` with invalid enum value (e.g., `"autonomy": "reckless"`) | Second most common config change, should validate |
| 3 | `auto_push` with invalid enum value (e.g., `"auto_push": "sometimes"`) | Safety-critical: wrong value could push unexpectedly |
| 4 | `verification_tier` with invalid enum value | Affects quality gate behavior |
| 5 | `model_profile` with invalid enum value | Affects cost/quality tradeoff |

**High Priority -- Integer Boundary Validation (4 tests)**

| # | Test Case | Rationale |
|---|-----------|-----------|
| 6 | `max_tasks_per_plan: 0` (below minimum of 1) | Boundary: could cause divide-by-zero or empty plans |
| 7 | `max_tasks_per_plan: 11` (above maximum of 10) | Boundary: upper limit enforcement |
| 8 | `command_timeout_ms: 500` (below minimum of 1000) | Boundary: too-low timeout could break commands |
| 9 | `review_max_cycles: 0` (below minimum of 1) | Boundary: zero cycles would skip review entirely |

**Medium Priority -- Type Validation (3 tests)**

| # | Test Case | Rationale |
|---|-----------|-----------|
| 10 | Boolean field with string value (e.g., `"auto_commit": "true"`) | Common mistake: string "true" instead of boolean |
| 11 | `agent_max_turns` with string sub-value (e.g., `"scout": "15"`) | Object field type validation |
| 12 | `qa_skip_agents` with non-array value (e.g., `"qa_skip_agents": "docs"`) | Array type enforcement |

**Low Priority -- Edge Cases (3 tests)**

| # | Test Case | Rationale |
|---|-----------|-----------|
| 13 | Valid config with all 10 enum fields set to valid values | Comprehensive happy path |
| 14 | Empty config `{}` validates successfully | Ensures all fields are optional |
| 15 | Config with negative integer (e.g., `"task_lease_ttl_secs": -1`) | Negative value handling |

### Gap Analysis Summary

- **Current coverage:** 4 tests covering 3 scenarios (type error, happy path, unknown keys, self-validation)
- **Recommended additions:** 15 test cases
- **Most critical gap:** Enum value validation -- the most common user error (typos in enum values) is not tested at all
- **Second gap:** Integer boundary validation -- `minimum`/`maximum` constraints in schema are not exercised
- **Schema complexity:** 48 properties with `additionalProperties: false`. The 4 existing tests provide structural coverage but not semantic coverage of individual field constraints
