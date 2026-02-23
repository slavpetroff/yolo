---
phase: "01"
plan: "02"
title: "Enforce qa_skip_agents in execute protocol"
wave: 1
depends_on: []
must_haves:
  - "REQ-02: qa_skip_agents config read in Step 3d of execute protocol"
  - "REQ-02: docs agent plans skip QA verification"
---

# Plan 02: Enforce qa_skip_agents in execute protocol

## Goal

The `qa_skip_agents` config key exists in `config/defaults.json` (line 30: `["docs"]`) and is defined in `config/config.schema.json` (lines 96-101), but the execute protocol SKILL.md never reads or enforces it. Plans produced by agents in the skip list (e.g., `docs`) should bypass QA verification entirely.

## Tasks

### Task 1: Add qa_skip_agents enforcement to Step 3d in execute protocol

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
In Step 3d (QA gate verification), immediately after reading `QA_GATE` and confirming it is active, add a check that reads the plan's producing agent from the plan frontmatter and compares against `qa_skip_agents`:

Insert after the `QA_GATE` activation check (after line ~715) and before the "When active:" section:

```bash
# Check qa_skip_agents — skip QA for plans produced by listed agents
QA_SKIP_AGENTS=$(jq -r '.qa_skip_agents // [] | .[]' .yolo-planning/config.json 2>/dev/null)
PLAN_AGENT=$(sed -n 's/^agent: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' {plan_path} | head -1)
for skip_agent in $QA_SKIP_AGENTS; do
  if [ "$PLAN_AGENT" = "$skip_agent" ]; then
    echo "○ QA skipped for plan {NN-MM} (agent: ${PLAN_AGENT} in qa_skip_agents)"
    # Skip to next plan — do not run CLI checks or spawn QA agent
    continue 2
  fi
done
```

Add this as a new subsection between the activation table and the "When active:" heading. The protocol text should explain:
- Read `qa_skip_agents` array from config
- Read `agent` field from plan YAML frontmatter (if present)
- If the plan's agent is in the skip list, display skip message and bypass QA for this plan
- If no `agent` field in frontmatter, proceed with QA normally (fail-open for backward compat)

**Why:** The `qa_skip_agents` config exists specifically to skip QA for non-code plans (like docs plans) that don't benefit from regression checks or commit linting. Without enforcement, every plan goes through QA regardless.

### Task 2: Add bats test for qa_skip_agents enforcement

**File:** `tests/unit/qa-skip-agents.bats` (new file)

**What to change:**
Create a test file that:
1. Verifies `qa_skip_agents` key exists in `config/defaults.json`
2. Verifies the value is a JSON array containing `"docs"`
3. Verifies `config.schema.json` defines `qa_skip_agents` as an array of strings
4. Greps `skills/execute-protocol/SKILL.md` for the string `qa_skip_agents` to confirm the protocol references it

**Why:** Ensures the config key and protocol enforcement stay in sync.
