---
phase: 01
plan: 01
title: "Fix wrong subcommand names in command markdowns"
wave: 1
depends_on: []
must_haves:
  - All CLI subcommand references in command markdowns match actual router entries
  - No broken yolo CLI calls remain in init.md, todo.md, or vibe.md
---

## Tasks

### Task 1: Fix init.md -- rename infer-gsd-summary to gsd-summary
**Files:** commands/init.md
**Action:** On line 399, replace `yolo infer-gsd-summary` with `yolo gsd-summary`. The router has `"gsd-summary"` mapped to `infer_gsd_summary::execute`.
**Acceptance:** `grep -c 'infer-gsd-summary' commands/init.md` returns 0; `grep -c 'yolo gsd-summary' commands/init.md` returns >= 1.

### Task 2: Fix todo.md -- rename persist-state-after-ship to persist-state
**Files:** commands/todo.md
**Action:** On line 26, replace `yolo persist-state-after-ship` with `yolo persist-state`. The router has `"persist-state"` mapped to `persist_state::execute`.
**Acceptance:** `grep -c 'persist-state-after-ship' commands/todo.md` returns 0; `grep -c 'yolo persist-state' commands/todo.md` returns >= 1.

### Task 3: Fix vibe.md -- rename compile-rolling-summary to rolling-summary
**Files:** commands/vibe.md
**Action:** On line 377, replace `yolo compile-rolling-summary` with `yolo rolling-summary`. The router has `"rolling-summary"` mapped to `compile_rolling_summary::execute`.
**Acceptance:** `grep -c 'compile-rolling-summary' commands/vibe.md` returns 0; `grep -c 'yolo rolling-summary' commands/vibe.md` returns >= 1.

### Task 4: Fix vibe.md -- rename persist-state-after-ship to persist-state
**Files:** commands/vibe.md
**Action:** On line 385, replace `yolo persist-state-after-ship` with `yolo persist-state`. Same fix as Task 2 but in vibe.md.
**Acceptance:** `grep -c 'persist-state-after-ship' commands/vibe.md` returns 0; `grep -c 'yolo persist-state' commands/vibe.md` returns >= 1.
