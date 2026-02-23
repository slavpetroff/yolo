# Type Safety & Self-Healing Roadmap

**Goal:** Harden the YOLO plugin with (1) strict typification and contract enforcement across config, CLI, hooks, and inter-agent messaging — eliminating fail-open gaps where invalid data silently degrades, and (2) self-healing infrastructure that automatically recovers from transient failures, state corruption, and agent crashes without human intervention.

**Scope:** 2 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 5 | 25 | 18 |
| 2 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Hard Typification & Contract Enforcement](#phase-1-hard-typification--contract-enforcement)
- [ ] [Phase 2: Self-Healing Infrastructure](#phase-2-self-healing-infrastructure)

---

## Phase 1: Hard Typification & Contract Enforcement

**Goal:** Add strict type validation across the system's weakest points — config schema, feature flag enforcement, CLI command routing, and hook input contracts — then enable the existing typed protocol and schema validation flags by default.

**Success Criteria:**
- `config/config.schema.json` exists with full JSON Schema for all 57 config keys
- `migrate_config.rs` validates merged config against schema at startup, hard error on violation
- Feature flags use a Rust enum (`FeatureFlag`) instead of string keys — compile-time exhaustiveness
- Startup validation logs warning if any enforcement flag is disabled
- CLI router uses `Command` enum (not string match) for all 73+ commands
- Domain newtypes `TaskId`, `Phase`, `Wave` replace raw String/u64 in at minimum 3 critical paths (lock, gate, state)
- `v2_typed_protocol` and `v3_schema_validation` defaults changed to `true` in `config/defaults.json`
- Hook inputs for `security_filter` and `validate_contract` use typed structs instead of `Value`
- All existing tests pass + new tests for schema validation, flag enum, typed hooks

**Dependencies:** None

---

## Phase 2: Self-Healing Infrastructure

**Goal:** Add automatic failure recovery — MCP tool retry with backoff, atomic file writes for state integrity, command execution timeouts, and per-task lease TTL — then enable the existing recovery feature flags.

**Success Criteria:**
- MCP tool handler wraps all 5 tools with exponential backoff (100ms→200ms→400ms, 3 retries, jitter)
- Circuit breaker disables tool after 5 consecutive failures (resets after 60s)
- All critical file writes (`execution-state.json`, `event-log.jsonl`, config) use atomic temp+rename pattern
- `.sha256` sidecar files written alongside critical state files, validated on read
- Backup restore on checksum mismatch (read `.backup`, log recovery event)
- `Command::new()` spawns wrapped with 30s timeout (configurable via `command_timeout_ms` config key)
- Per-task lease TTL: tasks auto-released after 5min idle, re-queued for assignment
- `v3_event_recovery`, `v3_snapshot_resume`, `v3_lease_locks` defaults changed to `true`
- Telemetry tracks recovery events (retry count, checksum mismatch, timeout kill, task reassignment)
- All existing tests pass + new tests for retry logic, atomic writes, timeout enforcement, task lease

**Dependencies:** Phase 1
