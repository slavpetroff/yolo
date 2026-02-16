#!/bin/bash
# generate-department-toons.sh — Generate project-specific department TOON files
# Reads project type from detect-stack.sh, maps conventions from project-types.json,
# renders templates from config/department-templates/ into .yolo-planning/departments/.
#
# Usage: bash generate-department-toons.sh [project-dir] [--force]
# Output: .yolo-planning/departments/{backend,frontend,uiux}.toon
#
# Generated TOONs are ephemeral (not committed). Static structural TOONs
# remain in references/departments/ (two-layer model per architecture D1).

set -euo pipefail

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Parse arguments ---
PROJECT_DIR=""
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE=true
      ;;
    *)
      if [ -z "$PROJECT_DIR" ]; then
        PROJECT_DIR="$arg"
      fi
      ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-.}"

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_TYPES="$SCRIPT_DIR/../config/project-types.json"
TEMPLATES_DIR="$SCRIPT_DIR/../config/department-templates"
OUTPUT_DIR="$PROJECT_DIR/.yolo-planning/departments"

# --- Validate inputs ---
if [ ! -f "$PROJECT_TYPES" ]; then
  echo '{"error":"project-types.json not found"}' >&2
  exit 1
fi

if [ ! -d "$TEMPLATES_DIR" ]; then
  echo '{"error":"department-templates directory not found"}' >&2
  exit 1
fi

# --- Call detect-stack.sh ---
DETECT_OUTPUT=$(bash "$SCRIPT_DIR/detect-stack.sh" "$PROJECT_DIR") || {
  echo '{"error":"detect-stack.sh failed"}' >&2
  exit 1
}

PROJECT_TYPE=$(echo "$DETECT_OUTPUT" | jq -r '.project_type // ""')
if [ -z "$PROJECT_TYPE" ] || [ "$PROJECT_TYPE" = "null" ]; then
  PROJECT_TYPE="generic"
fi

# --- Cross-platform hash computation ---
compute_hash() {
  if command -v shasum &>/dev/null; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum &>/dev/null; then
    sha256sum | cut -d' ' -f1
  else
    # fallback: use cksum if neither available
    cksum | cut -d' ' -f1
  fi
}

# --- Hash check: skip regeneration if detect output unchanged ---
CURRENT_HASH=$(echo "$DETECT_OUTPUT" | compute_hash)

if [ "$FORCE" = true ]; then
  echo "Force regeneration requested"
elif [ -f "$OUTPUT_DIR/.stack-hash" ]; then
  STORED_HASH=$(cat "$OUTPUT_DIR/.stack-hash")
  if [ "$STORED_HASH" = "$CURRENT_HASH" ]; then
    echo "TOONs up to date"
    exit 0
  else
    echo "Stack changed, regenerating TOONs"
  fi
fi

# --- Create output directory ---
mkdir -p "$OUTPUT_DIR"

# --- Lookup conventions from project-types.json ---
TYPE_DATA=$(jq --arg t "$PROJECT_TYPE" '.types[] | select(.id == $t)' "$PROJECT_TYPES")

# Fallback to generic if type not found
if [ -z "$TYPE_DATA" ]; then
  TYPE_DATA=$(jq '.types[] | select(.id == "generic")' "$PROJECT_TYPES")
fi

# --- Extract backend values ---
BACKEND_LANGUAGE=$(echo "$TYPE_DATA" | jq -r '.department_conventions.backend.language // "per project"')
BACKEND_TESTING=$(echo "$TYPE_DATA" | jq -r '.department_conventions.backend.testing // "per project"')
BACKEND_TOOLING=$(echo "$TYPE_DATA" | jq -r '.department_conventions.backend.tooling // "per project"')

# --- Extract frontend values (handle empty frontend object) ---
FRONTEND_FRAMEWORK=$(echo "$TYPE_DATA" | jq -r '.department_conventions.frontend.framework // "per project"')
FRONTEND_COMPONENT_LIB=$(echo "$TYPE_DATA" | jq -r '.department_conventions.frontend.component_lib // "per project"')
FRONTEND_CSS=$(echo "$TYPE_DATA" | jq -r '.department_conventions.frontend.css // "per project"')
FRONTEND_TESTING=$(echo "$TYPE_DATA" | jq -r '.department_conventions.frontend.testing // "per project"')

# --- Extract UX values ---
UX_TESTING_APPROACH=$(echo "$TYPE_DATA" | jq -r '.ux_focus.testing_approach // "general usability review"')

# Multi-line UX blocks: format as indented list items
UX_FOCUS_AREAS=$(echo "$TYPE_DATA" | jq -r '.ux_focus.focus_areas // [] | map("    - " + .) | join("\n")')
UX_ARTIFACT_TYPES=$(echo "$TYPE_DATA" | jq -r '.ux_focus.artifact_types // [] | map("    - " + .) | join("\n")')
UX_VOCABULARY=$(echo "$TYPE_DATA" | jq -r '.ux_focus.vocabulary // {} | to_entries | map("    " + .key + ": " + .value) | join("\n")')

# --- Render templates ---
# Uses awk for placeholder substitution (architecture R1: no sed s///)

# Render backend template
awk \
  -v lang="$BACKEND_LANGUAGE" \
  -v test="$BACKEND_TESTING" \
  -v tool="$BACKEND_TOOLING" \
  '{
    gsub(/\{\{BACKEND_LANGUAGE\}\}/, lang)
    gsub(/\{\{BACKEND_TESTING\}\}/, test)
    gsub(/\{\{BACKEND_TOOLING\}\}/, tool)
    print
  }' "$TEMPLATES_DIR/backend.toon.tmpl" > "$OUTPUT_DIR/backend.toon"

# Render frontend template
awk \
  -v fw="$FRONTEND_FRAMEWORK" \
  -v cl="$FRONTEND_COMPONENT_LIB" \
  -v css="$FRONTEND_CSS" \
  -v test="$FRONTEND_TESTING" \
  '{
    gsub(/\{\{FRONTEND_FRAMEWORK\}\}/, fw)
    gsub(/\{\{FRONTEND_COMPONENT_LIB\}\}/, cl)
    gsub(/\{\{FRONTEND_CSS\}\}/, css)
    gsub(/\{\{FRONTEND_TESTING\}\}/, test)
    print
  }' "$TEMPLATES_DIR/frontend.toon.tmpl" > "$OUTPUT_DIR/frontend.toon"

# Render uiux template
# Multi-line blocks require special handling: write expanded content to temp files,
# then use awk to replace placeholder lines with file contents
UX_FOCUS_TMPFILE=$(mktemp)
UX_ARTIFACTS_TMPFILE=$(mktemp)
UX_VOCAB_TMPFILE=$(mktemp)

printf '%s\n' "$UX_FOCUS_AREAS" > "$UX_FOCUS_TMPFILE"
printf '%s\n' "$UX_ARTIFACT_TYPES" > "$UX_ARTIFACTS_TMPFILE"
printf '%s\n' "$UX_VOCABULARY" > "$UX_VOCAB_TMPFILE"

awk \
  -v testing="$UX_TESTING_APPROACH" \
  -v focus_file="$UX_FOCUS_TMPFILE" \
  -v artifact_file="$UX_ARTIFACTS_TMPFILE" \
  -v vocab_file="$UX_VOCAB_TMPFILE" \
  '{
    gsub(/\{\{UX_TESTING_APPROACH\}\}/, testing)
    if ($0 ~ /\{\{UX_FOCUS_AREAS\}\}/) {
      while ((getline line < focus_file) > 0) print line
      close(focus_file)
      next
    }
    if ($0 ~ /\{\{UX_ARTIFACT_TYPES\}\}/) {
      while ((getline line < artifact_file) > 0) print line
      close(artifact_file)
      next
    }
    if ($0 ~ /\{\{UX_VOCABULARY\}\}/) {
      while ((getline line < vocab_file) > 0) print line
      close(vocab_file)
      next
    }
    print
  }' "$TEMPLATES_DIR/uiux.toon.tmpl" > "$OUTPUT_DIR/uiux.toon"

# Clean up temp files
rm -f "$UX_FOCUS_TMPFILE" "$UX_ARTIFACTS_TMPFILE" "$UX_VOCAB_TMPFILE"

# --- Write hash ---
echo "$CURRENT_HASH" > "$OUTPUT_DIR/.stack-hash"

# --- Output summary ---
echo "Generated department TOONs for project_type=$PROJECT_TYPE in $OUTPUT_DIR"
exit 0
