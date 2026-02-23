---
phase: 3
plan: 3
title: "Deduplicate agent boilerplate into shared base reference"
status: complete
commits: 2
deviations: 0
---

# Summary: Deduplicate Agent Boilerplate

## What Was Built
Created shared `references/agent-base-protocols.md` with canonical Circuit Breaker, Context Injection, and Shutdown Handling protocols. Compressed inline sections in 5 agent files while preserving test-critical headers and keywords.

## Files Modified
- `references/agent-base-protocols.md` — new shared reference
- `agents/yolo-debugger.md` — compressed Circuit Breaker, Context Injection, Shutdown Handling
- `agents/yolo-dev.md` — compressed Circuit Breaker, Context Injection, Shutdown Handling
- `agents/yolo-lead.md` — compressed Circuit Breaker, Context Injection, Shutdown Handling
- `agents/yolo-docs.md` — compressed Circuit Breaker, Shutdown Handling
- `agents/yolo-architect.md` — compressed Circuit Breaker only (unique Shutdown preserved)

## Commits
- `f00ae37` docs(03-03): create shared agent-base-protocols.md reference
- `69571f8` refactor(03-03): compress agent boilerplate with shared base reference

## Metrics
- Circuit Breaker compressed in 5 agents
- Context Injection compressed in 3 agents
- Shutdown Handling compressed in 3 agents (architect preserved unchanged)
- ~800 tokens saved across agent definitions
