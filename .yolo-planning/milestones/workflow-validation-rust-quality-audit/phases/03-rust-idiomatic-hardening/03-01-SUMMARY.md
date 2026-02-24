---
plan: "03-01"
phase: 3
title: "Replace Mutex::lock().unwrap() with proper error handling"
status: complete
agent: dev-01
tasks_completed: 3
tasks_total: 3
commits: 2
commit_hashes:
  - da4d48b4215187ea7f6b05de271f25d7ee33d39d
  - 042e8ab91bed1a1e683a5c69fbe784ddc9eee584
---

## What Was Built

Hardened all 7 `Mutex::lock().unwrap()` calls across 2 files to eliminate panic-on-poison:

- **telemetry/db.rs** (4 calls): Replaced with `.lock().map_err(...)` to propagate mutex poisoning as `rusqlite::Error::InvalidParameterName`. All 4 methods already return `Result<_, rusqlite::Error>`, so error propagation is a clean fit.
- **mcp/tools.rs** (3 calls): Replaced with `.lock().unwrap_or_else(|e| e.into_inner())` for poison recovery. These guard in-memory caches (prefix hashes, file locks) where recovering stale data is preferable to crashing.

## Files Modified

- yolo-mcp-server/src/telemetry/db.rs
- yolo-mcp-server/src/mcp/tools.rs

## Deviations

None. All changes match the plan exactly.
