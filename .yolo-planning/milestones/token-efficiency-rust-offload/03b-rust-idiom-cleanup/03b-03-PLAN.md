---
phase: "03b"
plan: "03"
title: "Safe string handling, error convention, and minor cleanups"
wave: 1
depends_on: []
must_haves:
  - "parse_frontmatter.rs uses split_once and strip_prefix instead of byte indexing"
  - "Consistent error convention: Ok((msg, exit_code)) for expected failures, Err for unexpected"
  - "serde_json::to_string uses ? operator instead of .unwrap()"
  - "session_start.rs cache dir read consolidated to single read"
  - "resolve_plugin_root.rs dead code removed"
  - "All existing tests pass"
---

# Plan 03b-03: Safe string handling, error convention, and minor cleanups

## Summary

Fix remaining non-idiomatic patterns: unsafe string indexing, inconsistent error handling, unnecessary unwraps, and dead code.

## Task 1: Safe string handling in parse_frontmatter.rs

**File:** `yolo-mcp-server/src/commands/parse_frontmatter.rs`

**Changes:**
1. Replace `line[..colon_pos]` with `line.split_once(':')`:
   ```rust
   // Before:
   let key = line[..colon_pos].trim().to_string();
   let val_raw = line[colon_pos + 1..].trim();

   // After:
   if let Some((key_part, val_part)) = line.split_once(':') {
       let key = key_part.trim().to_string();
       let val_raw = val_part.trim();
   ```
2. Replace `&val_raw[1..val_raw.len() - 1]` with `strip_prefix`/`strip_suffix`:
   ```rust
   // Before:
   let inner = &val_raw[1..val_raw.len() - 1];

   // After:
   if let Some(inner) = val_raw.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
   ```
3. Similar for quoted string stripping — use `strip_prefix('"').and_then(|s| s.strip_suffix('"'))`

## Task 2: Unify error handling convention

**Files:** All Phase 2 + Phase 3 command files

**Convention to apply:**
- `Err(message)`: Only for truly unexpected internal errors (should never happen)
- `Ok((json_output, 1))`: For expected failures (file not found, invalid input, usage errors)
- `Ok((json_output, 0))`: For success

**Changes:**
1. In `parse_frontmatter.rs`, change `Err(json_string)` usage errors to `Ok((json_string, 1))`
2. In `resolve_model.rs`, change `Err(plain_string)` to `Ok((json_error, 1))`
3. In `detect_stack.rs`, change `Err(json_string)` to `Ok((json_string, 1))`
4. Ensure all error responses are valid JSON (not plain strings)
5. Document the convention with a comment in `utils.rs`:
   ```rust
   // Error convention: Ok((output, exit_code)) for all expected conditions.
   // Err(msg) reserved for truly unexpected internal failures.
   ```

## Task 3: Replace .unwrap() on serde_json::to_string with ? or map_err

**Files:** All Phase 2 command files

**Changes:**
1. Replace all instances of:
   ```rust
   Ok((serde_json::to_string(&out).unwrap() + "\n", 0))
   ```
   with:
   ```rust
   let mut s = serde_json::to_string(&out).map_err(|e| e.to_string())?;
   s.push('\n');
   Ok((s, 0))
   ```
2. Apply consistently across: parse_frontmatter.rs, resolve_plugin_root.rs, config_read.rs

## Task 4: Consolidate session_start.rs cache directory reads

**File:** `yolo-mcp-server/src/commands/session_start.rs`

**Changes:**
1. In `cleanup_and_sync_cache()`, read the cache directory once and reuse:
   ```rust
   fn sorted_cache_dirs(cache_dir: &Path) -> Vec<PathBuf> {
       let mut dirs: Vec<PathBuf> = fs::read_dir(cache_dir)
           .into_iter().flatten().flatten()
           .filter(|e| e.path().is_dir())
           .map(|e| e.path())
           .collect();
       dirs.sort();
       dirs
   }
   ```
2. Replace the 3+ separate `fs::read_dir` calls with a single `sorted_cache_dirs()` call
3. Also centralize the `unsafe { libc::getuid() }` calls into a single `fn get_uid() -> u32`

## Task 5: Remove dead code in resolve_plugin_root.rs

**File:** `yolo-mcp-server/src/commands/resolve_plugin_root.rs`

**Changes:**
1. Remove or simplify the always-true `grandparent.is_dir()` check
2. Add a meaningful validation instead (e.g., check for a marker file like `yolo-mcp-server` dir or `Cargo.toml`)
3. Or simply document that the binary fallback always succeeds:
   ```rust
   // Strategy 3: Use binary's grandparent directory
   // This always succeeds since the binary must be in a directory
   let grandparent = parent.parent().unwrap_or(parent);
   ```
