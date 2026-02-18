#!/usr/bin/env bash
set -euo pipefail

# generate-agent.sh — Combine template + dept overlay to produce agent .md files
# Usage: generate-agent.sh --role <role> --dept <backend|frontend|uiux> [--dry-run] [--output <path>]
#
# Templates:  agents/templates/<role>.md
# Overlays:   agents/overlays/<dept>.json
# Output:     agents/yolo-<prefix><role>.md (or stdout with --dry-run)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/agents/templates"
OVERLAYS_DIR="$REPO_ROOT/agents/overlays"
AGENTS_DIR="$REPO_ROOT/agents"

# --- Argument parsing ---
ROLE=""
DEPT=""
DRY_RUN=false
OUTPUT=""

usage() {
  cat <<'USAGE'
Usage: generate-agent.sh --role <role> --dept <backend|frontend|uiux> [--dry-run] [--output <path>]

Options:
  --role <role>       Agent role: dev, senior, tester, qa, qa-code, architect, lead, security, documenter
  --dept <dept>       Department: backend, frontend, uiux
  --dry-run           Print generated output to stdout instead of writing file
  --output <path>     Custom output path (default: agents/yolo-<prefix><role>.md)
  --help              Show this help message

Examples:
  generate-agent.sh --role dev --dept backend
  generate-agent.sh --role dev --dept frontend --dry-run
  generate-agent.sh --role security --dept uiux --output /tmp/test.md
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)   ROLE="$2"; shift 2 ;;
    --dept)   DEPT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --help)   usage 0 ;;
    *)        echo "Error: unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --- Validation ---
if [[ -z "$ROLE" ]]; then
  echo "Error: --role is required" >&2
  usage 1
fi

if [[ -z "$DEPT" ]]; then
  echo "Error: --dept is required" >&2
  usage 1
fi

VALID_ROLES="dev senior tester qa qa-code architect lead security documenter"
if ! echo "$VALID_ROLES" | tr ' ' '\n' | grep -qx "$ROLE"; then
  echo "Error: invalid role '$ROLE'. Valid: $VALID_ROLES" >&2
  exit 1
fi

VALID_DEPTS="backend frontend uiux"
if ! echo "$VALID_DEPTS" | tr ' ' '\n' | grep -qx "$DEPT"; then
  echo "Error: invalid dept '$DEPT'. Valid: $VALID_DEPTS" >&2
  exit 1
fi

TEMPLATE="$TEMPLATES_DIR/$ROLE.md"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "Error: template not found: $TEMPLATE" >&2
  exit 1
fi

OVERLAY="$OVERLAYS_DIR/$DEPT.json"
if [[ ! -f "$OVERLAY" ]]; then
  echo "Error: overlay not found: $OVERLAY" >&2
  exit 1
fi

# --- Build jq substitution program ---
# Strategy: use jq to build a single sed-compatible substitution script
# that replaces all placeholders in one pass. This avoids shell loops
# over multi-line values entirely.
#
# We use jq to merge common + role sections, then generate a jq program
# that does all substitutions on the template content in one shot.

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Step 1: Extract merged placeholder map (role overrides common) as flat JSON object
jq --arg role "$ROLE" '
  (.common // {}) * (.[$role] // {})
' "$OVERLAY" > "$TMPDIR_WORK/merged.json"

# Step 2: Collect all placeholder keys from template
grep -oE '\{\{[A-Z_]+\}\}' "$TEMPLATE" | sort -u | sed 's/[{}]//g' > "$TMPDIR_WORK/keys.txt"

# Step 3: Use jq to perform all substitutions on the template content
# Read template as raw string, then iteratively replace each placeholder
# with its value from the merged overlay

jq -Rs --slurpfile overlay "$TMPDIR_WORK/merged.json" '
  . as $template |
  $overlay[0] as $vals |
  reduce ($vals | keys[]) as $key (
    $template;
    ($vals[$key] // null) as $val |
    if $val != null then
      gsub("{{" + $key + "}}"; $val)
    else
      .
    end
  )
' "$TEMPLATE" > "$TMPDIR_WORK/output.txt"

# Step 4: Check for unreplaced placeholders
UNREPLACED=$(grep -oE '\{\{[A-Z_]+\}\}' "$TMPDIR_WORK/output.txt" 2>/dev/null | sort -u || true)
if [[ -n "$UNREPLACED" ]]; then
  echo "Warning: unreplaced placeholders for role=$ROLE dept=$DEPT:" >&2
  echo "$UNREPLACED" | sed 's/^/  /' >&2
fi

# --- Determine output path ---
if [[ -z "$OUTPUT" ]]; then
  PREFIX=$(jq -r '.common.DEPT_PREFIX' "$OVERLAY")
  OUTPUT="$AGENTS_DIR/yolo-${PREFIX}${ROLE}.md"
fi

# --- Write output ---
# jq -Rs wraps output in quotes with escape sequences; we stored raw jq output
# which is a JSON string — unwrap it
CONTENT=$(jq -r '.' "$TMPDIR_WORK/output.txt")

if $DRY_RUN; then
  printf '%s\n' "$CONTENT"
  echo "# Would write to: $OUTPUT" >&2
else
  printf '%s\n' "$CONTENT" > "$OUTPUT"
  echo "Generated: $OUTPUT"
fi
