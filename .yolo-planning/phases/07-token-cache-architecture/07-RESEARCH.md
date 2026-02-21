# Phase 7 Research: Token Cache Architecture Alignment

## Findings

### Current State
- `compile-context` produces role-gated `.context-{role}.md` files (~9KB / ~2,300 tokens)
- Context is passed as **file path reference** in TaskCreate descriptions, not injected verbatim
- Dev agents read the context file as a tool call — appears as mid-conversation tool result, NOT as system prompt prefix
- Anthropic prompt cache operates on system prompt + leading messages — tool results don't trigger cache hits
- `yolo report` uses hardcoded 80K assumption and 1:10 write:read ratio — no measured data
- `v2_token_budgets=false` — enforcement exists in Rust but is disabled
- Compiled context already has `--- COMPILED CONTEXT ---` / `--- VOLATILE TAIL ---` markers but returns as single fused string

### Cache-Hit Gap Analysis
When 3 Dev agents are spawned for the same phase:
- Agent definition (`agents/yolo-dev.md`) IS shared in system prompt → cached ✓
- CLAUDE.md IS shared in system prompt → cached ✓
- Task prompt (first user message) starts with DIFFERENT content per agent → cache miss ✗
- Compiled context read via tool call mid-conversation → not cache-eligible ✗

## Relevant Patterns

### Files Requiring Changes
1. `references/execute-protocol.md` lines 150-196 — Dev TaskCreate template
2. `commands/vibe.md` Plan mode step 4 + step 6 — Lead Task spawn
3. `yolo-mcp-server/src/mcp/tools.rs` lines 22-97 — compile_context MCP tool (split output)
4. `yolo-mcp-server/src/cli/router.rs` lines 8-62 — report command + compile-context CLI
5. `.yolo-planning/config.json` — enable v2_token_budgets, v3_metrics, v3_event_log

### Prefix-First Pattern
All sibling Dev agents MUST receive byte-identical content from position 0 through the end of the stable context prefix. Task-specific instructions (PLAN_PATH, resume state) come AFTER the shared prefix.

```
[STABLE PREFIX — identical for all sibling agents]
--- COMPILED CONTEXT (phase=N, role=dev) ---
{CONVENTIONS.md}
{STACK.md}
{ROADMAP.md}
--- END COMPILED CONTEXT ---

[VOLATILE TAIL — per-agent]
Execute all tasks in {PLAN_PATH}.
Effort: {effort}. Working directory: {pwd}.
```

## Risks

1. **TaskCreate description size limits**: Injecting ~9KB of context verbatim into TaskCreate may hit description length limits. Mitigation: 9KB is well within typical limits (Claude context windows are 200K+).
2. **Volatile tail in compiled context**: `git diff HEAD` and PLAN.md content currently appear in the compiled context file. If volatile content is in the "stable prefix" section, cache hits break. Mitigation: Move volatile content to a separate section clearly after the sentinel.
3. **Cross-phase prefix reuse**: The header `phase=N` changes between phases. Removing it enables cross-phase caching of unchanged files but loses phase context. Mitigation: Move phase number to volatile tail.

## Recommendations

1. **Highest priority**: Prefix-first prompt assembly in execute-protocol.md — this is the single biggest cache efficiency win, requires only protocol text changes (no Rust code).
2. **Second priority**: Split compile_context output into stable/volatile in Rust — enables orchestrator to inject only the stable part as shared prefix.
3. **Third priority**: ROI dashboard upgrade — replace hardcoded assumptions with actual DB metrics.
4. **Fourth priority**: Enable token budgets + metrics flags — flip config, verify enforcement works end-to-end.
