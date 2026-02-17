#!/usr/bin/env bash
set -euo pipefail

# bootstrap-claude.sh — Generate or update CLAUDE.md with YOLO sections
#
# Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH] [--minimal] [--verify]
#   OUTPUT_PATH    Path to write CLAUDE.md
#   PROJECT_NAME   Name of the project
#   CORE_VALUE     One-line core value statement
#   EXISTING_PATH  (Optional) Path to existing CLAUDE.md to preserve non-YOLO content
#   --minimal      Generate only init-appropriate sections (YOLO Rules, Project Conventions, Commands, Plugin Isolation)
#   --verify       Validate YOLO_SECTIONS registry matches generate_yolo_sections() output and exit

if [[ $# -lt 3 ]]; then
  echo "Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH] [--minimal] [--verify]" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
CORE_VALUE="$3"

# Parse positional arg 4 (EXISTING_PATH) and flags from remaining args
EXISTING_PATH=""
MINIMAL=false
VERIFY_ONLY=false

shift 3
for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=true;;
    --verify) VERIFY_ONLY=true;;
    *) if [[ -z "$EXISTING_PATH" ]]; then EXISTING_PATH="$arg"; fi;;
  esac
done

# YOLO-managed section headers (order matters for generation)
YOLO_SECTIONS=(
  "## Active Context"
  "## Department Architecture"
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

## Department Architecture

26 agents across 4 departments. Enable/disable via `config/defaults.json` `departments` key.

| Department | Agents | Prefix | Protocol File |
|-----------|--------|--------|---------------|
| Backend | architect, lead, senior, dev, tester, qa, qa-code | (none) | `references/departments/backend.toon` |
| Frontend | fe-architect, fe-lead, fe-senior, fe-dev, fe-tester, fe-qa, fe-qa-code | `fe-` | `references/departments/frontend.toon` |
| UI/UX | ux-architect, ux-lead, ux-senior, ux-dev, ux-tester, ux-qa, ux-qa-code | `ux-` | `references/departments/uiux.toon` |
| Shared | owner, critic, scout, debugger, security | (none) | `references/departments/shared.toon` |

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

# Generate minimal sections for init (pre-bootstrap, no project context yet)
generate_minimal_sections() {
  cat <<'MINEOF'
## YOLO Rules

- **Always use YOLO commands** for project work. Do not manually edit files in `.yolo-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /yolo:go for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it. Commit locally and wait.

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
MINEOF
}

# Verify YOLO_SECTIONS registry matches generate_yolo_sections() output
verify_section_registry() {
  local generated
  generated=$(generate_yolo_sections)
  local gen_headers
  gen_headers=$(echo "$generated" | grep -E '^## ' | sort)
  local reg_headers
  reg_headers=$(printf '%s\n' "${YOLO_SECTIONS[@]}" | sort)
  if [[ "$gen_headers" != "$reg_headers" ]]; then
    echo "FATAL: YOLO_SECTIONS registry does not match generate_yolo_sections() output" >&2
    echo "Registry: $reg_headers" >&2
    echo "Generated: $gen_headers" >&2
    exit 1
  fi
}

# Always verify section registry at startup
verify_section_registry

# Handle --verify flag: validate and exit
if [[ "$VERIFY_ONLY" == true ]]; then
  exit 0
fi

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

# Select section generator based on --minimal flag
generate_sections() {
  if [[ "$MINIMAL" == true ]]; then
    generate_minimal_sections
  else
    generate_yolo_sections
  fi
}

# If existing file provided and it exists, preserve non-managed content
if [[ -n "$EXISTING_PATH" && -f "$EXISTING_PATH" ]]; then
  # Read existing file into variable for same-file safety (in-place regeneration)
  EXISTING_CONTENT=$(cat "$EXISTING_PATH")

  # Extract sections that are NOT managed by YOLO or GSD
  NON_YOLO_CONTENT=""
  IN_MANAGED_SECTION=false
  BEFORE_FIRST_SECTION=true
  IN_CODE_BLOCK=false
  FOUND_NON_YOLO=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Track code block state (``` toggles)
    if [[ "$line" =~ ^\`\`\` ]]; then
      if [[ "$IN_CODE_BLOCK" == false ]]; then
        IN_CODE_BLOCK=true
      else
        IN_CODE_BLOCK=false
      fi
    fi

    # Only process heading detection outside code blocks
    if [[ "$IN_CODE_BLOCK" == false ]]; then
      # Check if this line starts a YOLO or GSD managed section
      if is_managed_section "$line"; then
        IN_MANAGED_SECTION=true
        BEFORE_FIRST_SECTION=false
        continue
      fi

      # Check if this line starts a new non-managed section (any ## header not in either list)
      if [[ "$line" =~ ^##\  ]] && ! is_managed_section "$line"; then
        IN_MANAGED_SECTION=false
        BEFORE_FIRST_SECTION=false
      fi

      # Also detect top-level heading (# Project Name) — skip it, we regenerate it
      if [[ "$line" =~ ^#\  ]] && [[ ! "$line" =~ ^##\  ]]; then
        continue
      fi

      # Skip lines starting with **Core value:** — we regenerate it
      if [[ "$line" =~ ^\*\*Core\ value:\*\* ]]; then
        continue
      fi
    fi

    if [[ "$IN_MANAGED_SECTION" == false ]] && [[ "$BEFORE_FIRST_SECTION" == false ]]; then
      NON_YOLO_CONTENT+="${line}"$'\n'
      FOUND_NON_YOLO=true
    fi
  done <<< "$EXISTING_CONTENT"

  # Collision detection: warn if preserved user sections match YOLO section names
  if [[ "$FOUND_NON_YOLO" == true ]]; then
    while IFS= read -r preserved_line; do
      for header in "${YOLO_SECTIONS[@]}"; do
        if [[ "$preserved_line" == "$header" ]]; then
          echo "WARNING: User section '$header' collides with YOLO-managed section. User content under this heading will be replaced." >&2
        fi
      done
    done <<< "$NON_YOLO_CONTENT"
  fi

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
    generate_sections
  } > "$OUTPUT_PATH"
else
  # New file: generate fresh
  {
    echo "# ${PROJECT_NAME}"
    echo ""
    echo "**Core value:** ${CORE_VALUE}"
    echo ""
    generate_sections
  } > "$OUTPUT_PATH"
fi

exit 0
