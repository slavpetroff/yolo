---
phase: 11
plan: 4
title: Task Lease TTL with Auto-Reassignment
status: complete
tasks_total: 5
tasks_completed: 5
tasks_done: 5
commits: 5
commit_hashes:
  - 676a85f
  - 97ae106
  - 0068cc5
  - 84b171c
  - 41791a7
---

# Summary: Task Lease TTL with Auto-Reassignment

## What Was Built

Automatic detection and recovery of task leases held by crashed agents. When an agent crashes mid-task, its lease expires after a configurable TTL (default 300s). The system can then reassign those tasks to available agents and report on the previous owners. The `recover_state` command now detects stale leases and marks affected plans for re-queuing.

Key capabilities added:
- Configurable `task_lease_ttl_secs` in `config.json` (default 300)
- `reassign_expired_tasks()` scans locks, removes expired leases, logs `task_reassigned` events
- CLI `yolo lease-lock reassign` command for manual reassignment
- `recover_state` marks plans with expired leases as "stale" for orchestrator re-queuing
- `is_lease_expired()` public helper for cross-module lease status checks

## Completed Tasks

### Task 1: Add task_lease_ttl_secs config key and reading
- Added `read_task_lease_ttl(cwd)` to `lease_lock.rs` -- reads from `.yolo-planning/config.json`, defaults to 300
- Added `task_lease_ttl_secs: 300` to `config/defaults.json`
- Updated `acquire()` to use config TTL when caller passes the default value
- 3 unit tests added
- **Commit:** 676a85f `feat(commands): add task_lease_ttl_secs config key for lease TTL`

### Task 2: Add reassign_expired_tasks function
- Added `pub fn reassign_expired_tasks(cwd)` to `lease_lock.rs`
- Scans `.locks/` for expired leases, removes them, logs `task_reassigned` events via `log_event`
- Returns `{"action": "reassign", "reassigned": [...], "count": N}` with previous owner info
- 2 unit tests added
- **Commit:** 97ae106 `feat(commands): add reassign_expired_tasks for crashed agent recovery`

### Task 3: Wire reassignment into CLI and enhance cleanup_expired
- Added `"reassign"` action to `execute()` CLI handler
- Enhanced `cleanup` action to include reassignment info in its output
- Updated usage string and error messages to include `reassign`
- 2 unit tests added (CLI routing + unknown action)
- **Commit:** 0068cc5 `feat(commands): wire task reassignment into lease-lock CLI`

### Task 4: Teach recover_state.rs to check lease staleness
- Added `pub fn is_lease_expired(cwd, resource)` to `lease_lock.rs` -- public helper for cross-module use
- Modified `collect_plans()` in `recover_state.rs` to check lease staleness
- Plans showing as "running" with expired leases are now marked "stale"
- "stale" recognized in overall status determination and wave tracking
- 2 unit tests added
- **Commit:** 84b171c `feat(commands): detect stale task leases in recover_state`

### Task 5: Integration tests for lease TTL and reassignment flow
- End-to-end test: acquire, expire, reassign, verify lease removed
- Test: fresh leases NOT reassigned
- Test: reassignment with event logging (v3_event_log enabled)
- Test: reassignment report includes previous owner info for all expired leases
- 4 integration tests added
- **Commit:** 41791a7 `test(commands): add integration tests for task lease TTL and reassignment`

## Deviations

None. All 5 tasks implemented as planned with no deviations from the plan.

## Files Modified
| File | Changes |
|------|---------|
| `yolo-mcp-server/src/commands/lease_lock.rs` | +375 lines: config reader, reassign function, is_lease_expired, CLI wiring, 12 new tests |
| `yolo-mcp-server/src/commands/recover_state.rs` | +101 lines: lease staleness detection, stale status handling, 2 new tests |
| `config/defaults.json` | +1 line: task_lease_ttl_secs key |

## Test Results
- **lease_lock**: 26 tests, 0 failures (14 existing + 12 new)
- **recover_state**: 10 tests, 0 failures (8 existing + 2 new)
