---
phase: "03"
plan: "01"
title: "Replace Mutex::lock().unwrap() with proper error handling"
wave: 1
depends_on: []
must_haves:
  - "REQ-01: All 4 Mutex::lock().unwrap() in telemetry/db.rs replaced with map_err"
  - "REQ-02: All 3 Mutex::lock().unwrap() in mcp/tools.rs replaced with poison recovery"
  - "REQ-03: Existing unit tests pass unchanged"
---

## Goal

Replace all 7 production `Mutex::lock().unwrap()` calls with proper error handling. Panicking on a poisoned mutex is unacceptable in a long-running MCP server.

## Strategy

- **telemetry/db.rs** (4 occurrences, lines 21/67/86/147): These wrap synchronous rusqlite calls that already return `Result`. Use `.map_err(|e| rusqlite::Error::InvalidParameterName(e.to_string()))?` or convert to a custom error string to propagate through the existing `Result<_, rusqlite::Error>` return types. The `init()` method is called from `new()` which already returns `Result`.
- **mcp/tools.rs** (3 occurrences, lines 170/230/247): These are in an async handler that returns `Value` directly (no `Result`). Use `.unwrap_or_else(|e| e.into_inner())` for poison recovery -- if a previous thread panicked while holding the lock, recover the inner data and continue. This is the correct pattern for in-memory state (locks and prefix hashes) where data loss from a panic is acceptable but server crash is not.

## Task 1: Harden telemetry/db.rs Mutex access

**Files:** `yolo-mcp-server/src/telemetry/db.rs`

Replace 4 `.lock().unwrap()` calls at lines 21, 67, 86, 147 with error propagation:

```rust
// Before:
let conn = self.conn.lock().unwrap();

// After:
let conn = self.conn.lock()
    .map_err(|e| rusqlite::Error::InvalidParameterName(format!("Mutex poisoned: {}", e)))?;
```

All 4 methods already return `Result<_, rusqlite::Error>`, so this is a clean fit.

## Task 2: Harden mcp/tools.rs Mutex access with poison recovery

**Files:** `yolo-mcp-server/src/mcp/tools.rs`

Replace 3 `.lock().unwrap()` calls at lines 170, 230, 247 with poison recovery:

```rust
// Before:
let mut hashes = state.last_prefix_hashes.lock().unwrap();

// After:
let mut hashes = state.last_prefix_hashes.lock().unwrap_or_else(|e| e.into_inner());
```

This pattern recovers from a poisoned mutex by extracting the inner data. For in-memory lock/hash state, this is safer than panicking.

## Task 3: Verify tests pass

Run `cargo test` in the `yolo-mcp-server/` directory. All existing tests (including `test_telemetry_db_creation_and_insertion`, `test_lock_acquire_and_release`, `test_compile_context_*`) must pass unchanged.
