#!/usr/bin/env bash
set -euo pipefail

# bootstrap-claude.sh — Generate or update CLAUDE.md with YOLO sections
#
# Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]
#   OUTPUT_PATH    Path to write CLAUDE.md
#   PROJECT_NAME   Name of the project
#   CORE_VALUE     One-line core value statement
#   EXISTING_PATH  (Optional) Path to existing CLAUDE.md to preserve non-YOLO content

if [[ $# -lt 3 ]]; then
  echo "Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
CORE_VALUE="$3"
EXISTING_PATH="${4:-}"

# YOLO-managed section headers (order matters for generation)
YOLO_SECTIONS=(
  "## Active Context"
  "## YOLO Rules"
  "## Key Decisions"
  "## Installed Skills"
  "## Project Conventions"
  "## Commands"
  "## Plugin Isolation"
)

# GSD-managed section headers (stripped from existing CLAUDE.md to prevent insight leakage)
GSD_SECTIONS=(
  "## Codebase Intelligence"
  "## Project Reference"
  "## GSD Rules"
  "## GSD Context"
  "## What This Is"
  "## Core Value"
  "## Context"
  "## Constraints"
)

# Ensure parent directory exists
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Generate YOLO-managed content
generate_yolo_sections() {
  cat <<'YOLOEOF'
## Active Context

**Work:** No active milestone
**Last shipped:** _(none yet)_
**Next action:** Run /yolo:go to start a new milestone, or /yolo:status to review progress

## YOLO Rules

- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /yolo:go for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it. Commit locally and wait.

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|

## Installed Skills

_(Run /yolo:skills to list)_

## Project Conventions

_(To be defined during project setup)_

## Commands

Run /yolo:status for current progress.
Run /yolo:help for all available commands.

## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.yolo-planning/`
- YOLO agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to YOLO workflows.
- YOLO uses its own codebase mapping in `.yolo-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into YOLO planning or vice versa.
YOLOEOF
}

# Check if a line is a YOLO-managed section header
is_yolo_section() {
  local line="$1"
  for header in "${YOLO_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line is a GSD-managed section header (stripped to prevent insight leakage)
is_gsd_section() {
  local line="$1"
  for header in "${GSD_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line is a managed section header (YOLO or GSD — both get stripped)
is_managed_section() {
  is_yolo_section "$1" || is_gsd_section "$1"
}

# If existing file provided and it exists, preserve non-managed content
if [[ -n "$EXISTING_PATH" && -f "$EXISTING_PATH" ]]; then
  # Extract sections that are NOT managed by YOLO or GSD
  NON_YOLO_CONTENT=""
  IN_MANAGED_SECTION=false
  FOUND_NON_YOLO=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Check if this line starts a YOLO or GSD managed section
    if is_managed_section "$line"; then
      IN_MANAGED_SECTION=true
      continue
    fi

    # Check if this line starts a new non-managed section (any ## header not in either list)
    if [[ "$line" =~ ^##\  ]] && ! is_managed_section "$line"; then
      IN_MANAGED_SECTION=false
    fi

    # Also detect top-level heading (# Project Name) — skip it, we regenerate it
    if [[ "$line" =~ ^#\  ]] && [[ ! "$line" =~ ^##\  ]]; then
      continue
    fi

    # Skip lines starting with **Core value:** — we regenerate it
    if [[ "$line" =~ ^\*\*Core\ value:\*\* ]]; then
      continue
    fi

    if [[ "$IN_MANAGED_SECTION" == false ]]; then
      NON_YOLO_CONTENT+="${line}"$'\n'
      FOUND_NON_YOLO=true
    fi
  done < "$EXISTING_PATH"

  # Write: header + core value + preserved content + YOLO sections
  {
    echo "# ${PROJECT_NAME}"
    echo ""
    echo "**Core value:** ${CORE_VALUE}"
    echo ""
    if [[ "$FOUND_NON_YOLO" == true ]]; then
      # Trim leading/trailing blank lines from preserved content
      echo "$NON_YOLO_CONTENT" | awk 'NF{found=1} found{lines[++n]=$0; if(NF)last=n} END{for(i=1;i<=last;i++)print lines[i]}'
      echo ""
    fi
    generate_yolo_sections
  } > "$OUTPUT_PATH"
else
  # New file: generate fresh
  {
    echo "# ${PROJECT_NAME}"
    echo ""
    echo "**Core value:** ${CORE_VALUE}"
    echo ""
    generate_yolo_sections
  } > "$OUTPUT_PATH"
fi

exit 0
