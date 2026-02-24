---
phase: "01"
plan: "02"
title: "Enforce qa_skip_agents in execute protocol"
wave: 1
depends_on: []
must_haves:
  - "REQ-02: qa_skip_agents config read in Step 3d of execute protocol"
  - "REQ-02: docs agent plans skip QA verification"
  - "REQ-02: agent field added to PLAN.md frontmatter schema so skip check has a source"
---

# Plan 02: Enforce qa_skip_agents in execute protocol

## Goal

The `qa_skip_agents` config key exists in `config/defaults.json` (line 30: `["docs"]`) and is defined in `config/config.schema.json` (lines 96-101), but the execute protocol SKILL.md never reads or enforces it. Plans produced by agents in the skip list (e.g., `docs`) should bypass QA verification entirely.

## Tasks

### Task 1: Add `agent` field to PLAN.md frontmatter schema

**Files:** `templates/PLAN.md`, `config/config.schema.json`

**What to change:**

The `qa_skip_agents` check needs an `agent` field on each plan to identify which agent produced it. Currently no PLAN.md files contain an `agent` field (the field only appears inconsistently in some SUMMARY.md files). Add the field to the canonical schema:

1. In `templates/PLAN.md`, add `agent: {agent-role}` to the YAML frontmatter block (after `effort_override`, before `skills_used`). This is an optional field -- plans without it are backward-compatible (the skip check treats missing agent as "proceed with QA").

2. In `config/config.schema.json`, if plan frontmatter validation exists, add `agent` as an optional string field. If validation is handled elsewhere (e.g., `validate-schema` hook), note that the field should be accepted but not required.

**Why:** Without an `agent` field in plan frontmatter, the `qa_skip_agents` check has no data source. SUMMARY.md has the field only in ~3 files out of many, making it unreliable. Adding `agent` to the plan template is a minimal, forward-compatible schema addition that the Lead agent sets when creating plans (e.g., `agent: "docs"` for documentation plans, `agent: "dev-01"` for dev plans).

### Task 2: Add qa_skip_agents enforcement to Step 3d in execute protocol

**File:** `skills/execute-protocol/SKILL.md`

**What to change:**
In Step 3d (QA gate verification), inside the "For each completed plan" prose loop (line ~734), add a skip check at the top -- before Stage 1 CLI data collection. The check reads the plan's `agent` field from PLAN.md frontmatter and compares against `qa_skip_agents` from config.

Insert as a new paragraph immediately after "For each completed plan in the phase, run **two-stage QA verification**:" and before "#### Stage 1 -- CLI data collection":

**Agent skip check (per plan):**

Before running Stage 1 for a plan, check whether the plan's producing agent is in the skip list:

```bash
# Check qa_skip_agents -- skip QA for plans produced by listed agents
SKIP_QA=false
QA_SKIP_AGENTS=$(jq -r '.qa_skip_agents // [] | .[]' .yolo-planning/config.json 2>/dev/null)
PLAN_AGENT=$(sed -n 's/^agent: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "{plan_path}" | head -1)
for skip_agent in $QA_SKIP_AGENTS; do
  if [ "$PLAN_AGENT" = "$skip_agent" ]; then
    SKIP_QA=true
    break
  fi
done

if [ "$SKIP_QA" = "true" ]; then
  echo "○ QA skipped for plan {NN-MM} (agent: ${PLAN_AGENT} in qa_skip_agents)"
  # Do not run CLI checks or spawn QA agent for this plan.
  # Proceed to the next plan.
fi
```

If `SKIP_QA` is true, skip both Stage 1 (CLI data collection) and Stage 2 (QA agent spawn) for this plan and move to the next completed plan. If false, proceed with QA normally.

The protocol text should explain:
- Read `qa_skip_agents` array from config (once per plan, or cache for the phase)
- Read `agent` field from PLAN.md YAML frontmatter
- If the plan's agent matches any entry in the skip list, set `SKIP_QA=true` and display skip message
- If no `agent` field in frontmatter (empty PLAN_AGENT), proceed with QA normally (fail-open for backward compat)

**Why:** The `qa_skip_agents` config exists specifically to skip QA for non-code plans (like docs plans) that don't benefit from regression checks or commit linting. Without enforcement, every plan goes through QA regardless. The flag-based pattern (`SKIP_QA=true` + conditional) is used instead of `continue 2` because the execute protocol's "For each completed plan" is a prose instruction to the Lead agent, not a literal bash for-loop -- `continue 2` would produce a shell error outside a nested loop construct.

### Task 3: Add bats test for qa_skip_agents enforcement

**File:** `tests/unit/qa-skip-agents.bats` (new file)

**What to change:**
Create a test file that:
1. Verifies `qa_skip_agents` key exists in `config/defaults.json`
2. Verifies the value is a JSON array containing `"docs"`
3. Verifies `config.schema.json` defines `qa_skip_agents` as an array of strings
4. Greps `skills/execute-protocol/SKILL.md` for the string `qa_skip_agents` to confirm the protocol references it
5. Greps `templates/PLAN.md` for the string `agent:` to confirm the template includes the field

**Why:** Ensures the config key, plan template, and protocol enforcement stay in sync.
