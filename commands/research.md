---
name: research
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
---

# YOLO Research: $ARGUMENTS

## Context

Working directory: `!`pwd``

Current project:
```
!`cat .yolo-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Usage: /yolo:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
2. **Scope:** Single question = 1 Scout. Multi-faceted or --parallel = 2-4 sub-topics.
3. **Spawn Scout:**
   - Resolve Scout model:
     ```bash
     SCOUT_MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh scout .yolo-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
     if [ $? -ne 0 ]; then echo "$SCOUT_MODEL" >&2; exit 1; fi
     ```
   - Display: `◆ Spawning Scout (${SCOUT_MODEL})...`
   - Spawn yolo-scout as subagent(s) via Task tool. **Add `model: "${SCOUT_MODEL}"` parameter.**
```
Research: {topic or sub-topic}.
Project context: {tech stack, constraints from PROJECT.md if relevant}.
Return structured findings.
```
   - Parallel: up to 4 simultaneous Tasks, each with same `model: "${SCOUT_MODEL}"`.
4. **Synthesize:** Single: present directly. Parallel: merge, note contradictions, rank by confidence.
5. **Persist:** Ask "Save findings? (y/n)". If yes: convert findings to research.jsonl (one JSON line per finding):
   ```json
   {"q":"topic","src":"web","finding":"key finding text","conf":"high","dt":"YYYY-MM-DD","rel":"why relevant"}
   ```
   Write to `.yolo-planning/phases/{phase-dir}/research.jsonl` (if active phase) or `.yolo-planning/research.jsonl` (global).
   Use `jq -cn` to produce each line. Append if file exists.
```
➜ Next Up
  /yolo:go --plan {N} -- Plan using research findings
  /yolo:go --discuss {N} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
