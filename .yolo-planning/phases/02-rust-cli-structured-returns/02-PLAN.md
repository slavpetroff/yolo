---
phase: 2
plan: 2
title: "Bootstrap commands structured returns"
wave: 1
depends_on: []
must_haves:
  - "All 5 bootstrap commands return structured JSON with changed files and content summary"
  - "bootstrap-project delta includes section_count, has_requirements, has_constraints"
  - "bootstrap-requirements delta includes requirement_count, research_available, discovery_updated"
  - "bootstrap-roadmap delta includes phase_count, phase_dirs_created list"
  - "bootstrap-state delta includes phase_count, preserved_todos (bool), preserved_decisions (bool)"
  - "bootstrap-claude delta includes sections_stripped count, decisions_migrated count, mode (greenfield/brownfield)"
  - "All existing tests in bootstrap_*.rs still pass"
  - "New tests verify JSON output for each bootstrap variant"
---

# Plan 2: Bootstrap Commands Structured Returns

## Overview

Retrofit all 5 bootstrap commands to return structured JSON using the `StructuredResponse` pattern. These commands currently return empty strings or "Created", forcing the caller to re-read the generated file to understand what was produced. With structured returns, the LLM caller immediately knows what was generated without follow-up reads.

**NOTE:** This plan does NOT import from `structured_response.rs` (Plan 1). Instead, it uses the same JSON envelope pattern inline to avoid cross-plan file dependencies. If Plan 1 lands first, a quick follow-up can refactor to use the shared module.

## Task 1: bootstrap-project structured return

**Files:**
- `yolo-mcp-server/src/commands/bootstrap_project.rs`

**Acceptance:**
- Returns JSON: `{"ok": true, "cmd": "bootstrap-project", "changed": ["<output_path>"], "delta": {"name": "...", "description": "...", "section_count": N, "has_requirements": true, "has_constraints": true}, "elapsed_ms": N}`
- Error case returns `{"ok": false, "cmd": "bootstrap-project", "error": "...", "elapsed_ms": N}`
- All existing tests pass with JSON parsing

**Implementation Details:**

The function currently returns `Ok((String::new(), 0))`. Change to:
1. Add `use std::time::Instant;` at top
2. Capture `let start = Instant::now();` at function entry
3. Count sections in generated content (count occurrences of `\n## `)
4. Build JSON response:
```rust
let response = serde_json::json!({
    "ok": true,
    "cmd": "bootstrap-project",
    "changed": [output_path.to_string_lossy()],
    "delta": {
        "name": name,
        "description": description,
        "section_count": section_count,
        "has_requirements": true,
        "has_constraints": true
    },
    "elapsed_ms": start.elapsed().as_millis() as u64
});
Ok((response.to_string(), 0))
```

## Task 2: bootstrap-requirements structured return

**Files:**
- `yolo-mcp-server/src/commands/bootstrap_requirements.rs`

**Acceptance:**
- Returns JSON with: requirement_count, research_available (bool), discovery_updated (bool)
- Changed files includes both the output_path and the discovery_path (since it writes to both)
- All existing tests pass

**Implementation Details:**

1. Count requirements from `inferred_count` (already computed)
2. Track whether discovery.json was updated (it always is, unless error)
3. Build response:
```rust
let response = serde_json::json!({
    "ok": true,
    "cmd": "bootstrap-requirements",
    "changed": [output_path.to_string_lossy(), discovery_path.to_string_lossy()],
    "delta": {
        "requirement_count": inferred_count,
        "research_available": research_available,
        "discovery_updated": true
    },
    "elapsed_ms": start.elapsed().as_millis() as u64
});
```

## Task 3: bootstrap-roadmap structured return

**Files:**
- `yolo-mcp-server/src/commands/bootstrap_roadmap.rs`

**Acceptance:**
- Returns JSON with: phase_count, phase_dirs list, project_name
- Changed files includes ROADMAP.md and all created phase directories
- All existing tests pass

**Implementation Details:**

1. `phase_count` is already computed as `phases_arr.len()`
2. Collect phase directory paths during the creation loop
3. Build response:
```rust
let mut changed = vec![output_path.to_string_lossy().to_string()];
let mut phase_dir_names = Vec::new();
for (i, phase) in phases_arr.iter().enumerate() {
    let dir_name = format!("{:02}-{}", i + 1, slug);
    phase_dir_names.push(dir_name.clone());
    changed.push(phases_dir.join(&dir_name).to_string_lossy().to_string());
}
```

## Task 4: bootstrap-state + bootstrap-claude structured returns

**Files:**
- `yolo-mcp-server/src/commands/bootstrap_state.rs`
- `yolo-mcp-server/src/commands/bootstrap_claude.rs`

**Acceptance:**
- bootstrap-state returns JSON with: phase_count, preserved_todos (bool), preserved_decisions (bool), project_name, milestone_name
- bootstrap-claude returns JSON with: mode (greenfield/brownfield), sections_stripped, decisions_migrated, non_yolo_sections_preserved
- All existing tests pass

**Implementation Details:**

For bootstrap-state:
- `preserved_todos` = `!existing_todos.is_empty()`
- `preserved_decisions` = `!existing_decisions.is_empty()`
- phase_count is passed as an arg

For bootstrap-claude:
- Track `greenfield` vs `brownfield` based on whether `existing_path` is provided and exists
- Count stripped sections: increment counter each time `is_managed_section` returns true
- Track decisions migrated via the `migrate_key_decisions` return value
- The current return `Ok(("Created".to_string(), 0))` becomes the JSON envelope

## Task 5: Update tests for all bootstrap commands

**Files:**
- `yolo-mcp-server/src/commands/bootstrap_project.rs` (test module)
- `yolo-mcp-server/src/commands/bootstrap_requirements.rs` (test module)
- `yolo-mcp-server/src/commands/bootstrap_roadmap.rs` (test module)
- `yolo-mcp-server/src/commands/bootstrap_state.rs` (test module)
- `yolo-mcp-server/src/commands/bootstrap_claude.rs` (test module)

**Acceptance:**
- All existing test assertions still hold (file content checks)
- Each test additionally parses the returned tuple's String as JSON
- Validates `ok`, `cmd`, `changed` (non-empty), and at least one delta field per command
- At least 1 error-case test per command validates `ok: false`

**Implementation Details:**

Pattern for updating each test:
```rust
let (output, code) = execute(&args, dir.path()).unwrap();
assert_eq!(code, 0);
let json: serde_json::Value = serde_json::from_str(&output).unwrap();
assert_eq!(json["ok"], true);
assert_eq!(json["cmd"], "bootstrap-project");
assert!(json["changed"].as_array().unwrap().len() > 0);
// existing file content assertions stay as-is
```
