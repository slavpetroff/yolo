---
name: research
description: Run standalone research via Lead-scoped Scout dispatch for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
disable-model-invocation: true
---

# YOLO Research: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current project:
```
!`cat .yolo-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Missing required input. Usage: /yolo:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
2. **Spawn Lead:**
- Resolve models (lead, scout) via `resolve-agent-model.sh` with config.json + model-profiles.json. Abort on failure.
- Display: `◆ Spawning Lead (${LEAD_MODEL}) for research scoping...`
- Spawn yolo-lead as subagent via Task tool. **Add `model: "${LEAD_MODEL}"` parameter.**
```
Research dispatch. Topic: {topic}. Parallel: {true|false}. Project context: {tech stack from PROJECT.md if relevant}. Scout model: ${SCOUT_MODEL}.
(1) Scope research: break topic into precise questions. Identify codebase-answerable (use Glob/Grep) vs web-research (needs Scout).
(2) If --parallel or multi-faceted topic: generate 2-4 sub-topics, spawn up to 4 yolo-scout subagents (model: SCOUT_MODEL each) with one scoped question each. If single question: spawn 1 yolo-scout (model: SCOUT_MODEL).
(3) Each Scout gets: exact research question, project context if relevant, instruction to return findings via scout_findings schema with confidence levels.
(4) Synthesize: merge Scout findings, resolve contradictions, rank by confidence (high/medium/low).
(5) Persist decision: ask go.md (caller) whether to save. If yes: write research.jsonl lines using jq -cn, one JSON line per finding with keys q,src,finding,conf,dt,rel. Write to .yolo-planning/phases/{phase-dir}/research.jsonl (if active phase) or .yolo-planning/research.jsonl (global). Append if file exists.
(6) Return: synthesized findings with confidence levels.
```
3. **Present:** Display Lead's synthesized findings using brand essentials format.
```
➜ Next Up
  /yolo:go --plan {N} -- Plan using research findings
  /yolo:go --discuss {N} -- Discuss phase approach
```

## Escalation

- Scout -> Lead: Scout reports findings or inability to find information. Scout NEVER presents results to user directly.
- Lead -> go.md: Lead synthesizes all Scout findings, resolves contradictions, presents final output to go.md (Owner proxy).
- Contradictions: If Scouts return conflicting findings, Lead flags contradictions with confidence levels and recommends which to trust.
- Scope concerns: If research reveals the topic needs deeper investigation or impacts architecture, Lead recommends /yolo:go --discuss to the user.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/○/⚠ symbols, Next Up, no ANSI.
