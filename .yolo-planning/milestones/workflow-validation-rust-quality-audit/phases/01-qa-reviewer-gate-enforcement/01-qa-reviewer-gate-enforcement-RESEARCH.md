# Research: Phase 01 — QA & Reviewer Gate Enforcement

## Findings

### Gap 1: Both gates default to `on_request` — neither fires automatically
- `config/defaults.json` lines 53-54: `"review_gate": "on_request"`, `"qa_gate": "on_request"`
- Execute protocol reads these at Step 2b (line 67) and Step 3d (line 715)
- With `on_request`, gates only fire when user passes `--review` or `--qa` flags
- Step 5 ordering check (line 1137) requires `step_2b` and `step_3d` in `steps_completed`, but both steps append regardless of whether gate was active or skipped
- **Fix:** Change defaults to `"always"` in `config/defaults.json`

### Gap 2: `qa_skip_agents` defined but never enforced
- `config/defaults.json` line 30: `qa_skip_agents: ["docs"]`
- `config/config.schema.json` lines 96-101 validates it as array
- Execute protocol `skills/execute-protocol/SKILL.md` — zero matches for `qa_skip_agents`
- **Impact:** Docs-only plans go through full QA unnecessarily
- **Fix:** Add qa_skip_agents check in execute protocol Step 3d before running QA CLI commands

### Gap 3: `check-regression` fixable_by 3-way inconsistency
- Execute protocol Step 3d (line 782): says `fixable_by: "architect"`
- Rust command `check_regression.rs` line 33: returns `fixable_by: "manual"`
- QA agent def `yolo-qa.md` line 82: says `fixable_by: "manual"`
- Runtime uses Rust command output → effective value is `"manual"` (HARD STOP)
- Protocol documentation at line 782 is wrong
- **Fix:** Update execute protocol table to say `"manual"` to match Rust output and agent def

### Gap 4: Verdict parsing is fail-open
- Reviewer verdict parsing (SKILL.md lines 141-153): shell `grep -oP` extracts `VERDICT:` line
- QA report parsing (SKILL.md lines 829-841): similar shell regex extraction
- Both have fallback: Reviewer defaults to `conditional` (proceed with warning), QA defaults to CLI results only
- **Impact:** Malformed agent output = gate becomes no-op, execution continues
- **Fix:** Change fallback to fail-closed: if verdict cannot be parsed, STOP with error

### Gap 5: `check-regression` always returns ok:true, exit 0
- `check_regression.rs` lines 27-36: hardcodes `"ok": true` and exit 0
- Only path to regression HARD STOP is if QA agent (Stage 2) overrides
- CLI fast-path (all 5 pass → skip agent) always passes check-regression
- Regression detection only fires when another check also fails
- **Note:** This is by design — the command is informational. But it should be documented clearly.

## Relevant Patterns

### Execute protocol gate pattern
```
1. Read gate config from .yolo-planning/config.json
2. If gate != "always" and no --flag: skip, append step to steps_completed
3. Run CLI Stage 1 commands
4. Fast-path: all CLI pass → skip agent spawn
5. Spawn agent via Task tool with subagent_type
6. Parse structured verdict from agent output
7. On reject: feedback loop (max N cycles)
8. On approve: proceed
```

### Config file locations
- Defaults: `config/defaults.json` (plugin-level defaults)
- User config: `.yolo-planning/config.json` (project-level overrides)
- Schema: `config/config.schema.json`

### Files requiring changes
- `config/defaults.json` — change gate defaults
- `skills/execute-protocol/SKILL.md` — add qa_skip_agents enforcement, fix fixable_by table, change verdict fallback behavior
- Possibly `yolo-mcp-server/src/commands/check_regression.rs` — no code change needed (documented as informational)

## Risks

1. Changing defaults to `always` is technically backward-compatible (users can override in project config) but will slow down execution for existing users who relied on `on_request` defaults
2. Fail-closed verdict parsing could block execution if agent output is disrupted by context compaction — need clear error message with manual override path
3. qa_skip_agents enforcement must handle edge case: what if agent name in plan doesn't exactly match config array entry?

## Recommendations

1. Change defaults.json `review_gate` and `qa_gate` to `"always"` — this is the correct default for a quality-focused plugin
2. Add qa_skip_agents check as the first thing in Step 3d, before running any CLI commands
3. Fix the fixable_by table in the execute protocol to match Rust output (`"manual"`)
4. Change verdict parsing fallback from fail-open to fail-closed with a clear STOP message
5. Keep all changes within existing config schema — no new keys needed
