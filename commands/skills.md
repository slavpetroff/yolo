---
name: skills
disable-model-invocation: true
description: Browse and install community skills from skills.sh based on your project's tech stack.
argument-hint: [--search <query>] [--list] [--refresh]
allowed-tools: Read, Bash, Glob, Grep, WebFetch
---

# YOLO Skills $ARGUMENTS

## Context

Working directory: `!`pwd``
Stack detection:
```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh "$(pwd)" 2>/dev/null || echo '{"error":"detect-stack.sh failed"}'`
```

## Guard

1. **Script failure:** Context contains `"error"` → STOP: "Stack detection failed. Make sure jq is installed."

## Steps

### Step 1: Parse arguments

- **No args**: full flow (detect, show installed, suggest, offer install)
- **--search \<query\>**: skip curated, search registry for \<query\>
- **--list**: list installed only, no suggestions
- **--refresh**: force re-run stack detection

### Step 2: Display current state

From Context JSON: display installed skills (`installed.global[]` + `installed.project[]`) in single-line box. Display detected stack. If `--list`: STOP here.

### Step 3: Curated suggestions

From `suggestions[]` in Context JSON (recommended but not installed). Display with `(curated)` tag. Empty + stack: "✓ All recommended installed." No stack + find-skills: suggest searches. No stack + no find-skills: "○ Use --search."

### Step 4: Dynamic registry search

**4a.** If `find_skills_available` is false: AskUserQuestion to install find-skills (`npx skills add vercel-labs/skills --skill find-skills -g -y`). Declined → skip to Step 5.

**4b.** Search when: --search passed (search for query) | no --search but unmapped stack items (auto-search each) | all mapped → skip.
Run `npx skills find "<query>"`. Display results with `(registry)` tag. If npx unavailable: "⚠ Skills CLI is not installed. Run: npx skills --help to verify."

### Step 5: Offer installation

Combine curated + registry, deduplicate, rank (curated first). AskUserQuestion multiSelect, max 4 options + "Skip". If >4: show top 4, suggest --search for more.

### Step 6: Install selected

`npx skills add <skill> -g -y` per selection. Display ✓ or ✗ per skill. "➜ Skills take effect immediately — no restart needed."

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/○/✗/⚠ symbols, no ANSI.
