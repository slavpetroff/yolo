---
phase: 3
plan: 3
title: "Deduplicate agent boilerplate into shared base reference"
wave: 1
depends_on: []
must_haves:
  - New references/agent-base-protocols.md containing canonical Circuit Breaker, Context Injection, and Shutdown Handling protocols
  - 5 agent files (architect, debugger, dev, lead, docs) updated with compressed inline versions referencing the shared base
  - Section headers (## Circuit Breaker, ## Shutdown Handling, ## Context Injection) preserved in all agents that currently have them
  - Agent-specific variations preserved (architect's unique shutdown note, dev's terse circuit breaker)
  - Net reduction of ~40 lines across agent files
  - All 692+ existing tests pass (especially shutdown-protocol.bats and discovered-issues-surfacing.bats)
---

# Plan 03: Deduplicate Agent Boilerplate

## Context

Six agent definition files in `agents/` total 21.6KB. Three protocol sections are duplicated nearly verbatim across multiple agents:

**Circuit Breaker** (5 agents): ~3-line paragraph about "same error 3 consecutive times" appears 5 times.
**Context Injection** (3 agents): ~2-line paragraph about "90% prompt cache hit" appears 3 times.
**Shutdown Handling** (4 agents): ~3-line paragraph about responding to `shutdown_request` appears 3 times (+ architect's unique variant).

**CRITICAL CONSTRAINT**: Tests in `tests/shutdown-protocol.bats` (20+ assertions) grep for `## Shutdown Handling` and `## Circuit Breaker` section headers directly in agent .md files. They also check section content for keywords like `shutdown_request`, `shutdown_response`, `STOP`, `blocker`. Tests also verify section ordering (Effort -> Shutdown -> Circuit Breaker). The deduplication approach MUST preserve these headers and keywords.

**Token impact**: By creating a shared reference doc for the canonical definitions and compressing the inline agent sections to 1-line summaries + reference pointer, we save ~40 lines / ~800 tokens total across agent definitions.

## Tasks

### Task 1: Create references/agent-base-protocols.md

**Files:** `references/agent-base-protocols.md` (new)

Create a shared reference containing the canonical (complete) versions of three protocols:

```markdown
# Agent Base Protocols

Canonical definitions for shared agent behaviors. Individual agents reference this file and may override specific behaviors.

## Circuit Breaker

If you encounter the same error 3 consecutive times: STOP retrying the same approach. Try ONE alternative approach. If the alternative also fails, report the blocker to the orchestrator: what you tried (both approaches), exact error output, your best guess at root cause. Never attempt a 4th retry of the same failing operation.

## Context Injection (Immutable Prefix)

You are spawned with the entire codebase context prefixed to your memory. This guarantees a 90% prompt cache hit. **DO NOT** request or attempt to read the entire architecture again unless explicitly required for your specific task.

## Shutdown Handling

When you receive a `shutdown_request` message via SendMessage: immediately respond with `shutdown_response` (approved=true, final_status reflecting your current state). Finish any in-progress tool call, then STOP. Do NOT start new tasks, write additional code, commit changes, or take any further action.
```

### Task 2: Compress inline sections in agent files

**Files:** `agents/yolo-debugger.md`, `agents/yolo-dev.md`, `agents/yolo-lead.md`, `agents/yolo-docs.md`

For each agent file, compress the duplicated sections while preserving section headers and test-critical keywords:

**Circuit Breaker** — Replace the full paragraph with a compressed version:
```markdown
## Circuit Breaker

Same error 3 times → STOP, try ONE alternative. Still fails → report blocker to orchestrator (both approaches, error output, root cause guess). No 4th retry.
```

**Context Injection** — Replace with:
```markdown
## Context Injection (Immutable Prefix)

Codebase context prefixed to memory (90% cache hit). Do NOT re-read architecture unless required for your specific task.
```

**Shutdown Handling** (debugger, lead, docs) — Replace with:
```markdown
## Shutdown Handling

On `shutdown_request`: respond `shutdown_response` (approved=true, final_status), finish in-progress tool call, then STOP. No new tasks or actions after responding.
```

**IMPORTANT**: Keep `yolo-architect.md` Shutdown Handling unchanged (it has the unique "planning-only agent" / "excluded from shutdown protocol" variant that tests check for `planning-only`). Only compress architect's Circuit Breaker section.

**IMPORTANT**: Keep `yolo-reviewer.md` completely unchanged (it has none of these sections).

Add a single reference line at the bottom of each modified agent file (before the last section):
```markdown
Full protocol definitions: `references/agent-base-protocols.md`
```

### Task 3: Verify all tests pass

**Files:** (read-only verification)

Run the full test suite, paying special attention to:
- `tests/shutdown-protocol.bats` — checks section headers, keywords (shutdown_request, shutdown_response, STOP, planning-only, finish), and section ordering
- `tests/discovered-issues-surfacing.bats` — checks Circuit Breaker exists in dev, mentions blocker reporting
- Any other tests that grep agent .md files

All 692+ tests must pass with zero failures.
