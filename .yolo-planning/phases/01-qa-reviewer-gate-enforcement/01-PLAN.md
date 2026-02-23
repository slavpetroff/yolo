---
phase: "01"
plan: "01"
title: "Gate defaults to always"
wave: 1
depends_on: []
must_haves:
  - "REQ-01: review_gate default is always in defaults.json"
  - "REQ-01: qa_gate default is always in defaults.json"
---

# Plan 01: Gate defaults to always

## Goal

Change `review_gate` and `qa_gate` defaults from `"on_request"` to `"always"` so that both gates fire automatically on every phase execution without requiring `--review` or `--qa` flags.

## Tasks

### Task 1: Change gate defaults in config/defaults.json

**File:** `config/defaults.json`

**What to change:**
- Line 53: Change `"review_gate": "on_request"` to `"review_gate": "always"`
- Line 54: Change `"qa_gate": "on_request"` to `"qa_gate": "always"`

**Why:** Both gates are defined but default to `on_request`, which means they never fire unless the user explicitly passes `--review` or `--qa`. Changing to `"always"` makes them fire on every execution, which is the intended behavior for a quality-gated workflow.

### Task 2: Add bats test verifying gate defaults

**File:** `tests/unit/gate-defaults.bats` (new file)

**What to change:**
Create a test file that:
1. Reads `config/defaults.json` with jq
2. Asserts `review_gate` equals `"always"`
3. Asserts `qa_gate` equals `"always"`
4. Asserts `review_max_cycles` is a positive integer
5. Asserts `qa_max_cycles` is a positive integer

**Why:** Prevents future regressions where someone changes the defaults back to `on_request`. The test locks in the intended behavior.
