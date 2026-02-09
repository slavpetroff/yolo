# VBW Shared Patterns

Reusable protocol fragments referenced across multiple skills.

## Initialization Guard

If `.vbw-planning/` doesn't exist, STOP: "Run /vbw:init first."

**Exception:** `/vbw:implement` handles the uninitialized state via its state machine. When `.vbw-planning/` exists but `PROJECT.md` is missing or contains template placeholders, implement routes to its Bootstrap flow (State 1) rather than stopping. Other commands continue to use this guard as-is.

## Milestone Resolution

Check for `.vbw-planning/ACTIVE` file to resolve the active milestone. If ACTIVE exists, read its contents for the milestone identifier and scope all phase paths accordingly.

## Agent Teams Shutdown Protocol

After all teammates have completed their tasks:
1. Send a shutdown request to each teammate.
2. Wait for each teammate to respond with shutdown approval.
3. If a teammate rejects shutdown (still finishing work), wait for it to complete and re-request.
4. Once ALL teammates have shut down, run TeamDelete to clean up the team and its shared task list.

## Command Context Budgets

Commands inject context via `!` blocks in their markdown. Not every command needs the same amount. Use the tier that matches the command's actual needs:

| Tier | What to inject | When to use |
|------|---------------|-------------|
| Minimal | Config pre-injected by SessionStart hook (nothing in command) | Commands that act on user intent, not project state: fix, todo, help, whats-new, update, uninstall, debug |
| Standard | `!`head -40 .vbw-planning/STATE.md`` + config (via hook) | Commands that need current phase/progress: plan, execute, implement, qa, status, resume |
| Full | Read full STATE.md + ROADMAP.md during execution | Commands that need the complete picture: audit, archive, map, assumptions |

**Rule:** Never add a STATE.md injection to a Minimal-tier command. If a command doesn't read the state during its logic, it doesn't need the state in its context.

## Phase Auto-Detection

Read `${CLAUDE_PLUGIN_ROOT}/references/phase-detection.md` for the full algorithm. Summary: scan phase directories in numeric order, checking for the presence/absence of PLAN.md and SUMMARY.md files to determine the next actionable phase.
