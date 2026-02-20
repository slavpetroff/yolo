---
name: yolo:research
category: advanced
description: Run standalone research by spawning Scout agent(s) for web searches and documentation lookups.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch
---

# YOLO Research: $ARGUMENTS

## Context

Working directory: `!`pwd``
Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

Current project:
```
!`cat .yolo-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Guard

- No $ARGUMENTS: STOP "Usage: /yolo:research <topic> [--parallel]"

## Steps

1. **Parse:** Topic (required). --parallel: spawn multiple Scouts on sub-topics.
2. **Scope:** Determine the key facets of the question.
3. **Research:**
   - Investigate the topic using your `WebFetch` tool for external knowledge, or codebase search tools for internal knowledge.
   - Do NOT spawn any subagents. Conduct the research directly in this context.
   - Focus on structured findings with clear headings.
4. **Synthesize:** Present your findings directly.
5. **Persist:** Ask "Save findings? (y/n)". If yes: write to .yolo-planning/phases/{phase-dir}/RESEARCH.md or .yolo-planning/RESEARCH.md.
```
➜ Next Up
  /yolo:vibe --plan {N} -- Plan using research findings
  /yolo:vibe --discuss {N} -- Discuss phase approach
```

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.md: single-line box for findings, ✓ high / ○ medium / ⚠ low confidence, Next Up Block, no ANSI.
