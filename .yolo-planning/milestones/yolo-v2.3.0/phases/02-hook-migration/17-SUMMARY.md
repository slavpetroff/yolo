# Plan 17 Summary: Update hooks.json to Use Native Rust Dispatcher

**Agent:** dev-17
**Status:** COMPLETE
**Commits:** 4

## Tasks Completed

### Task 1: Update hooks.json to use native Rust dispatcher
- **Commit:** `e6fe551` feat(hooks): replace all bash hook-wrapper.sh entries with native Rust dispatcher
- Replaced all remaining bash hook-wrapper.sh one-liners with single `$HOME/.cargo/bin/yolo hook <EventName>` entries
- Merged multiple entries per event+matcher into single dispatcher calls
- Reduced hooks.json from ~200 lines to ~110 lines, eliminating ~15 bash shell-outs per session

### Task 2: Create hook-wrapper.sh deprecation stub
- **Commit:** `970e70d` refactor(hooks): replace hook-wrapper.sh with deprecation forwarding stub
- Replaced the full hook-wrapper.sh (SIGHUP trap, plugin cache resolution, bash execution) with a lightweight forwarding stub
- Maps all 21 script names to their corresponding dispatcher events
- Marked for removal in v3.0

### Task 3: Add end-to-end integration tests for hook dispatcher
- **Commit:** `89f8de2` test(hooks): add e2e integration tests and no-bash regression guard (shared with parallel dev)
- Added 3 additional e2e tests: SUMMARY.md write, credentials.json block, .pem file block
- 15+ existing e2e tests already covered all 10 dispatch paths

### Task 4: Verify no remaining Command::new("bash") in hook paths
- **Commit:** `17e09a2` test(hooks): add static analysis tests for hard_gate and two_phase_complete bash usage
- Verified hard_gate.rs has exactly 1 bash call (user-defined verification_checks, legitimate)
- Verified two_phase_complete.rs has exactly 1 sh call (user-defined verification_checks, legitimate)
- session_start.rs confirmed clean, all hooks/*.rs confirmed clean

### Task 5: Final cleanup and documentation
- **Commit:** `6c51e21` refactor(hooks): fix clippy warnings across all hook modules
- Fixed 4 clippy warnings in hooks/ (utils.rs, validate_contract.rs, agent_health.rs, blocker_notify.rs)
- Verified all 22 hook modules declared in mod.rs
- cargo clippy reports 0 warnings in hooks/ modules
- All 674 hooks tests pass

## Files Modified
- `hooks/hooks.json` (all events now use native Rust dispatcher)
- `scripts/hook-wrapper.sh` (replaced with deprecation forwarding stub)
- `yolo-mcp-server/src/hooks/dispatcher.rs` (3 additional e2e tests)
- `yolo-mcp-server/src/hooks/mod.rs` (2 additional static analysis tests)
- `yolo-mcp-server/src/hooks/utils.rs` (clippy fix: identical blocks)
- `yolo-mcp-server/src/hooks/validate_contract.rs` (clippy fix: redundant closure)
- `yolo-mcp-server/src/hooks/agent_health.rs` (clippy fix: boolean simplification)
- `yolo-mcp-server/src/hooks/blocker_notify.rs` (clippy fix: boolean simplification)

## Tests
- 674 hooks tests pass, 0 failures
- 0 clippy warnings in hooks/ modules
- 827 total crate tests pass (8 pre-existing failures: 7 SQLite + 1 env-dependent)

## Key Decisions
- PascalCase event names in hooks.json to match HookEvent enum directly
- hard_gate.rs and two_phase_complete.rs exempted from no-bash check (user-defined verification checks)
- Absolute binary path `$HOME/.cargo/bin/yolo` for deterministic resolution
