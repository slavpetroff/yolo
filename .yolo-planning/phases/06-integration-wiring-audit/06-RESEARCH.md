# Phase 6 Research: Integration Wiring Audit

## Findings

### MCP Tools (5 registered, all properly exposed)
- `compile_context` — Used by orchestrator (vibe command) to build agent context. Not directly referenced by agents (correct by design).
- `acquire_lock` / `release_lock` — Referenced by `yolo-dev.md` (lines 25, 34). Used for parallel file locking.
- `run_test_suite` — Referenced by `yolo-dev.md` (line 32). Dynamic runner detection (cargo/bats/pytest/npm).
- `request_human_approval` — Referenced by `yolo-architect.md` (line 30). HITL gate for vision validation.

**Status:** All 5 tools properly wired. No orphans.

### CLI Subcommands (60+ registered)
All commands in `router.rs` have matching modules in `src/commands/`. Cross-referenced with:
- `commands/*.md` slash commands invoke CLI via `$HOME/.cargo/bin/yolo <cmd>`
- `references/execute-protocol.md` and `commands/vibe.md` invoke planning-git, compile-context, resolve-model, etc.

**Status:** All commands properly wired. No orphans.

### Agent Definitions — CRITICAL GAPS

**Defined (4):** `yolo-architect`, `yolo-dev`, `yolo-docs`, `yolo-reviewer`

**Missing (3):**

1. **`yolo-lead`** — HIGH severity
   - Referenced by: `commands/vibe.md` Plan mode, `references/execute-protocol.md`, `hooks/hooks.json` (4 matchers)
   - Impact: Plan mode spawns Lead via `Task` tool. Without agent definition, spawning works only because orchestrator uses `vbw:vbw-lead` fallback. Fragile.

2. **`yolo-debugger`** — MEDIUM severity
   - Referenced by: `hooks/hooks.json` (4 matchers), `config/token-budgets.json` (debugger role)
   - Impact: Debug command references debugger role but no agent definition exists. Currently works because `/yolo:debug` uses `vbw:vbw-debugger`.

3. **Vestigial: `yolo-qa`, `yolo-scout`** — LOW severity
   - Referenced by: `hooks/hooks.json` (4 matchers each)
   - CLAUDE.md explicitly deprecates these: "No QA or Scout agents"
   - Impact: Zero runtime impact (hooks are advisory-only). Stale references cause confusion.

### Hook Matchers — Stale References
`hooks/hooks.json` SubagentStart/Stop/Idle/TaskCompleted matchers include 7 agent names but only 4 have definitions. The 3 extra (`yolo-lead`, `yolo-qa`, `yolo-scout`, `yolo-debugger`) are either missing or intentionally deprecated.

### Slash Commands (22 total)
All 22 command markdown files reference valid CLI subcommands. No broken links.

### Config Files (6 total)
All config keys (`defaults.json`, `model-profiles.json`, etc.) are read by Rust code. Feature flags (`v3_*`) map to corresponding CLI commands.

### References (11 total)
All reference files are actively used by commands or protocols. No orphans.

## Risks

1. **yolo-lead missing**: If VBW plugin is removed or reconfigured, Plan mode breaks entirely since it depends on `vbw:vbw-lead` as a hidden fallback
2. **Agent naming inconsistency**: Hooks accept 3 name variants (yolo-lead, lead, team-lead) but only the `yolo-` prefix variant maps to agent files
3. **Stale hook matchers**: New contributors may assume yolo-qa/yolo-scout exist and waste time looking for them

## Recommendations

### Priority 1: Create Missing Agent Definitions
- Create `agents/yolo-lead.md` with planning orchestration protocol
- Create `agents/yolo-debugger.md` with scientific debugging protocol

### Priority 2: Clean Up Stale References
- Remove `yolo-qa`, `yolo-scout` from all 4 hook matchers in `hooks/hooks.json`
- Add comment in hooks.json explaining which agents are active

### Priority 3: Verify Agent Tool Access
- Ensure each agent's `allowed-tools` frontmatter includes the MCP tools it actually uses
- Cross-validate that `compile_context` MCP tool output format matches what agents expect to receive
