---
phase: "01"
plan: "03"
title: "Fix check-regression fixable_by inconsistency"
wave: 1
depends_on: []
must_haves:
  - "REQ-03: check-regression fixable_by is manual in execute protocol Step 3d fixable_by table"
  - "REQ-03: check-regression fixable_by is manual in execute protocol Dev remediation table"
---

# Plan 03: Fix check-regression fixable_by inconsistency

## Goal

The `check-regression` command's `fixable_by` classification is inconsistent across three locations:
- Rust CLI (`check_regression.rs` line 33): returns `"manual"` -- CORRECT
- QA agent (`yolo-qa.md` line 82): says `"manual"` -- CORRECT
- Execute protocol (`SKILL.md` line 784): says `"architect"` -- WRONG
- Execute protocol (`SKILL.md` line 1070): says `"architect"` -- WRONG

The Rust CLI is the source of truth. The execute protocol tables must be updated to match.

## Tasks

### Task 1: Fix fixable_by in Step 3d CLI classification table

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
Line 784 currently reads:
```
- `check-regression` → `"architect"` (test count decrease is a plan-level issue)
```

Change to:
```
- `check-regression` → `"manual"` (test count change requires human review)
```

**Why:** The Rust `check_regression.rs` returns `fixable_by: "manual"` in its JSON output (line 33). The protocol table must match the CLI output since the QA agent reads `fixable_by` from the CLI JSON, not from this table. Saying `"architect"` here creates confusion about what the actual gate behavior is.

### Task 2: Fix fixable_by in Dev remediation context table

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
Line 1070 currently reads:
```
| `check-regression` | N/A (always `fixable_by: "architect"` — HARD STOP, never reaches Dev) | — |
```

Change to:
```
| `check-regression` | N/A (always `fixable_by: "manual"` — HARD STOP, never reaches Dev) | — |
```

**Why:** Same consistency fix as Task 1. The Rust CLI and QA agent both say `"manual"`. The execute protocol must agree.

### Task 3: Add bats test for fixable_by consistency

**File:** `tests/unit/fixable-by-consistency.bats` (new file)

**What to change:**
Create a test file that:
1. Runs `yolo check-regression` against a temp dir and asserts `fixable_by` equals `"manual"` in the JSON output (this test already exists in `qa-loop.bats` but a dedicated consistency test is clearer)
2. Greps `skills/execute-protocol/SKILL.md` for the check-regression fixable_by classification and asserts it contains `"manual"` (not `"architect"`)
3. Greps `agents/yolo-qa.md` for the check-regression fixable_by and asserts it contains `"manual"`

**Why:** Three-way consistency check prevents future drift between CLI, protocol, and agent definition.
