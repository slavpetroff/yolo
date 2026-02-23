# Phase 3 Research: Context Integrity

## REQ-03: ARCHITECTURE.md for Execution Family

**Problem:** `tier_context.rs` line 84 — execution family only gets `["ROADMAP.md"]`. Dev/QA agents never see ARCHITECTURE.md, causing architecture drift across phases.

**Fix location:** `yolo-mcp-server/src/commands/tier_context.rs`
- Line 84: Change `"execution" => vec!["ROADMAP.md"]` to `"execution" => vec!["ARCHITECTURE.md", "ROADMAP.md"]`
- Line 482: Update test assertion `assert_eq!(execution, vec!["ROADMAP.md"])` → `vec!["ARCHITECTURE.md", "ROADMAP.md"]`
- Line 534: Flip assertion `assert!(!t2_dev.contains("Architecture overview"))` → `assert!(t2_dev.contains(...))`
- Line 530: `assert_ne!` between dev/lead tier2 may now fail since both get ARCHITECTURE.md. Planning still differs (has REQUIREMENTS.md). Check if content still differs.

**Scope:** 1 source line + 2-3 test assertions.

## REQ-05: Step-Ordering Verification

**Problem:** `.execution-state.json` tracks phase/plans but not which protocol steps completed. Claude can skip steps (e.g., jump from Step 2 to Step 3d) with no detection.

**Fix locations:**
1. `skills/execute-protocol/SKILL.md` — Add `steps_completed` array tracking at each step transition. After completing Step 2, record `"step_2"`. After 2b, record `"step_2b"`. Etc.
2. `skills/execute-protocol/SKILL.md` Step 5 — Add validation: verify `steps_completed` contains all required steps before marking phase complete. Required sequence: `["step_2", "step_2b", "step_3", "step_3c", "step_3d"]` (step 4/4.5 conditional on config).
3. `.execution-state.json` schema — Add `"steps_completed": []` field to initial write in Step 2 item 7.

**Design:** Append-only array. Each step appends its ID. Step 5 validates presence of required steps. Missing steps = HARD STOP with list of skipped steps.

## REQ-06: Delegation Mandate Reinforcement

**Problem:** Delegation directive at SKILL.md lines 428-434 is a single block. During long executions, context compression can lose it, causing Claude to implement tasks instead of delegating.

**Fix locations:**
1. `skills/execute-protocol/SKILL.md` line 428 — Strengthen existing mandate with anti-takeover language
2. `skills/execute-protocol/SKILL.md` Step 3c — Add reminder: "You are LEAD. Do NOT edit plan files yourself."
3. `skills/execute-protocol/SKILL.md` Step 3d — Add reminder: "You are LEAD. QA is agent-based, not self-review."
4. `skills/execute-protocol/SKILL.md` Step 5 — Add reminder: "You are LEAD. State updates only — no implementation."
5. `agents/yolo-lead.md` — Add "Anti-Takeover Protocol" section: Lead MUST delegate to Dev. Never Write/Edit files in `files_modified`. If tempted to implement: create new Dev agent instead.

**Design:** Distributed reinforcement (5 anchor points) survives compression better than single block. Each anchor is 1-2 lines, minimal token cost.
