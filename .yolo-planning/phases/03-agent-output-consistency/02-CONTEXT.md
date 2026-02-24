# Phase 3: Agent Output Consistency & Race Condition Fixes — Context

Gathered: 2026-02-24
Calibration: architect

## Phase Boundary

Fix SUMMARY naming enforcement, diff-against-plan commit scoping, commit_hashes validation, and instruction consistency. Scope reduced: binary path unification dropped (current `$HOME/.cargo/bin/yolo` is consistent and reliable).

## Decisions

### Binary path strategy

- **Keep `$HOME/.cargo/bin/yolo` everywhere.** 205+ references are consistent. No churn.
- Removed from Phase 3 scope — the roadmap item is not worth the migration cost.

### commit_hashes validation depth

- Add `git rev-parse --verify {hash}^{commit}` existence check in verify-plan-completion
- Fast (< 10ms per hash), catches typos and fabricated hashes
- No branch scoping or ancestry check (avoids rebase false positives)
- Current regex check (7+ hex) stays as first-pass filter

### --commits override semantics for diff-against-plan

- `--commits hash1,hash2` is a **full override** — replaces frontmatter commit_hashes entirely
- Explicit always wins: if user passes --commits, frontmatter hashes are ignored
- Use case: re-verifying a plan against specific commits when frontmatter is wrong/missing
- When --commits is NOT passed, existing behavior (read from frontmatter) is unchanged

### SUMMARY naming enforcement

- **Dev agent template hardcoding** — compute `{NN}-{MM}-SUMMARY.md` filename from plan metadata
- Prevention at source, not runtime detection
- Strengthen the dev agent template to derive filename from plan number and phase number
- No QA-side filename check needed (agent produces correct name by construction)

### Open (Claude's discretion)

- Implementation order: commit_hashes validation first (smallest), then --commits flag (depends on validation), then SUMMARY naming (agent template change)
- SUMMARY naming change should update both `agents/yolo-dev.md` and `skills/execute-protocol/SKILL.md`

## Deferred Ideas

None captured during discussion.
