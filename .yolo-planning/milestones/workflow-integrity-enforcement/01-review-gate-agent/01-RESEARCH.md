# Phase 1 Research: Review Gate — Agent-Based Adversarial Review

## Findings

### Current State
- Execute protocol Step 2b (SKILL.md lines 55-274) runs `yolo review-plan` (Rust CLI) and parses its JSON verdict
- `review_plan.rs` (663 lines) checks ONLY structural properties:
  1. Frontmatter completeness (6 required fields)
  2. Task count <= 5
  3. Must-haves non-empty
  4. Wave is positive integer
  5. Referenced file paths exist
- Exit codes: 0=approve, 1=reject (structural issues), 2=conditional (warnings)
- A well-formed plan with valid frontmatter ALWAYS passes — no design quality review

### What Should Happen (Per Agent Definition)
- `agents/yolo-reviewer.md` defines an adversarial agent that:
  1. Reads plan files
  2. Verifies referenced codebase files exist (Glob/Grep)
  3. Runs `yolo review-plan` for automated checks
  4. Analyzes adversarially: design risks, anti-patterns, missing edge cases, naming violations, file conflicts
  5. Produces structured VERDICT with findings
- Agent has proper tool restrictions: Read, Glob, Grep, Bash (no Edit/Write)
- Delta-aware review protocol for feedback loops (cycle > 1)
- Escalation protocol for persistent high-severity findings

### The Gap
- The execute protocol runs the Rust CLI command directly and uses its exit code as the verdict
- The reviewer agent (which would do adversarial analysis) is NEVER spawned
- The feedback loop (reject → architect revise → re-review) exists in protocol but never triggers because the CLI check is too superficial to reject well-formed plans

### Config Context
- User's config: `review_gate: "always"`, `review_max_cycles: 3`
- Defaults: `review_gate: "on_request"` — gate would be skipped unless explicitly enabled
- Protocol heading says "Step 2b: Review gate (optional)" — misleading when config is "always"

## Relevant Patterns

### Files to Modify
1. `skills/execute-protocol/SKILL.md` — Step 2b section (lines 55-274)
   - Must add reviewer agent spawn after CLI pre-check
   - CLI check becomes fail-fast pre-filter, agent provides quality verdict
2. `agents/yolo-reviewer.md` — May need minor updates to ensure verdict parsing works
3. `yolo-mcp-server/src/commands/review_plan.rs` — No changes needed (stays as pre-check)

### Existing Feedback Loop Infrastructure
- Review loop logic (lines 89-251) is complete: cycle tracking, delta findings, architect spawn, re-review
- Execution state tracking with `review_loops` in `.execution-state.json`
- Event logging: `review_loop_start`, `review_loop_cycle`, `review_loop_end`
- This infrastructure is reusable — the loop just needs the reviewer agent verdict instead of CLI exit code

### Two-Stage Review Pattern
The fix should be: CLI pre-check (fast, structural) → Agent review (thorough, adversarial)
- If CLI rejects (structural issue like missing frontmatter): fast fail, no agent needed
- If CLI approves/conditional: spawn reviewer agent for adversarial analysis
- Agent's VERDICT becomes the gate verdict for the feedback loop

## Risks

1. **Token cost increase**: Spawning a reviewer agent per plan adds ~15 turns of API calls
   - Mitigation: CLI pre-check filters out obviously broken plans before agent runs
2. **Verdict parsing**: Agent returns free-text VERDICT; protocol must parse it reliably
   - Mitigation: Agent definition has structured format with `VERDICT: approve|reject|conditional`
3. **Review timing**: Agent review adds latency before Dev execution begins
   - Mitigation: Review runs sequentially per plan (already in protocol), parallelism preserved in Dev execution
4. **Backward compatibility**: Changing Step 2b must not break when reviewer agent is unavailable
   - Mitigation: Fall back to CLI-only verdict if agent spawn fails

## Recommendations

1. Restructure Step 2b as two-stage: CLI pre-check → agent adversarial review
2. Remove "(optional)" from Step 2b heading — it's misleading when `review_gate="always"`
3. Change the verdict source from CLI exit code to agent's VERDICT output
4. Keep CLI check as fast fail-early gate (saves tokens on malformed plans)
5. Add explicit agent spawn with `subagent_type: "yolo:yolo-reviewer"` in the protocol
6. Ensure feedback loop (reject → architect revise → re-review) uses agent review in re-review step too
