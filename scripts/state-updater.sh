#!/bin/bash
set -u
# PostToolUse: Auto-update STATE.md, ROADMAP.md + .execution-state.json on PLAN/SUMMARY writes
# Non-blocking, fail-open (always exit 0)

update_state_md() {
  local phase_dir="$1"
  local state_md=".vbw-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  local plan_count summary_count pct
  plan_count=$(ls -1 "$phase_dir"/*.plan.jsonl "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(ls -1 "$phase_dir"/*.summary.jsonl "$phase_dir"/*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

  if [ "$plan_count" -gt 0 ]; then
    pct=$(( (summary_count * 100) / plan_count ))
  else
    pct=0
  fi

  local tmp="${state_md}.tmp.$$"
  sed "s/^Plans: .*/Plans: ${summary_count}\/${plan_count}/" "$state_md" | \
    sed "s/^Progress: .*/Progress: ${pct}%/" > "$tmp" 2>/dev/null && \
    mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

slug_to_name() {
  echo "$1" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

update_roadmap() {
  local phase_dir="$1"
  local roadmap=".vbw-planning/ROADMAP.md"

  [ -f "$roadmap" ] || return 0

  local dirname phase_num plan_count summary_count status date_str
  dirname=$(basename "$phase_dir")
  phase_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
  [ -z "$phase_num" ] && return 0

  plan_count=$(ls -1 "$phase_dir"/*.plan.jsonl "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(ls -1 "$phase_dir"/*.summary.jsonl "$phase_dir"/*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

  [ "$plan_count" -eq 0 ] && return 0

  if [ "$summary_count" -eq "$plan_count" ]; then
    status="complete"
    date_str=$(date +%Y-%m-%d)
  elif [ "$summary_count" -gt 0 ]; then
    status="in progress"
    date_str="-"
  else
    status="planned"
    date_str="-"
  fi

  # Extract phase name from existing progress table row
  local existing_name
  existing_name=$(grep -E "^\| *${phase_num} - " "$roadmap" | head -1 | sed 's/^| *[0-9]* - //' | sed 's/ *|.*//')
  [ -z "$existing_name" ] && return 0

  # Update progress table row
  local tmp="${roadmap}.tmp.$$"
  sed "s/^| *${phase_num} - .*/| ${phase_num} - ${existing_name} | ${summary_count}\/${plan_count} | ${status} | ${date_str} |/" "$roadmap" > "$tmp" 2>/dev/null

  # Check checkbox if phase complete
  if [ "$status" = "complete" ]; then
    local tmp2="${roadmap}.tmp2.$$"
    sed "s/^- \[ \] Phase ${phase_num}:/- [x] Phase ${phase_num}:/" "$tmp" > "$tmp2" 2>/dev/null && \
      mv "$tmp2" "$tmp" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
  fi

  mv "$tmp" "$roadmap" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

update_model_profile() {
  local state_md=".vbw-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  # Read active model profile from config
  local model_profile
  model_profile=$(jq -r '.model_profile // "balanced"' .vbw-planning/config.json 2>/dev/null || echo "balanced")

  # Check if Codebase Profile section exists
  if ! grep -q "^## Codebase Profile" "$state_md" 2>/dev/null; then
    return 0
  fi

  # Check if Model Profile line already exists
  if grep -q "^- \*\*Model Profile:\*\*" "$state_md" 2>/dev/null; then
    # Update existing line
    local tmp="${state_md}.tmp.$$"
    sed "s/^- \*\*Model Profile:\*\*.*/- **Model Profile:** ${model_profile}/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    # Insert after Test Coverage line
    local tmp="${state_md}.tmp.$$"
    sed "/^- \*\*Test Coverage:\*\*/a\\
- **Model Profile:** ${model_profile}" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

advance_phase() {
  local phase_dir="$1"
  local state_md=".vbw-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  # Check if triggering phase is complete
  local plan_count summary_count
  plan_count=$(ls -1 "$phase_dir"/*.plan.jsonl "$phase_dir"/*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  summary_count=$(ls -1 "$phase_dir"/*.summary.jsonl "$phase_dir"/*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$plan_count" -gt 0 ] && [ "$summary_count" -eq "$plan_count" ] || return 0

  # Scan all phase dirs to find next incomplete
  local phases_dir total next_num next_name all_done
  phases_dir=$(dirname "$phase_dir")
  total=$(ls -d "$phases_dir"/*/ 2>/dev/null | wc -l | tr -d ' ')
  next_num=""
  next_name=""
  all_done=true

  for dir in $(ls -d "$phases_dir"/*/ 2>/dev/null | sort); do
    local dirname p s
    dirname=$(basename "$dir")
    p=$(ls -1 "$dir"*.plan.jsonl "$dir"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
    s=$(ls -1 "$dir"*.summary.jsonl "$dir"*-SUMMARY.md 2>/dev/null | wc -l | tr -d ' ')

    if [ "$p" -eq 0 ] || [ "$s" -lt "$p" ]; then
      if [ -z "$next_num" ]; then
        next_num=$(echo "$dirname" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
        [ -z "$next_num" ] && next_num=0
        next_name=$(slug_to_name "$dirname")
      fi
      all_done=false
      break
    fi
  done

  [ "$total" -eq 0 ] && return 0

  local tmp="${state_md}.tmp.$$"
  if [ "$all_done" = true ]; then
    sed "s/^Status: .*/Status: complete/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  elif [ -n "$next_num" ]; then
    sed "s/^Phase: .*/Phase: ${next_num} of ${total} (${next_name})/" "$state_md" | \
      sed "s/^Status: .*/Status: ready/" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Plan trigger: update plan count + activate status (JSONL or legacy MD)
if echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+-[0-9]+\.plan\.jsonl$' || echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+-[0-9]+-PLAN\.md$'; then
  update_state_md "$(dirname "$FILE_PATH")"
  update_roadmap "$(dirname "$FILE_PATH")"
  # Status: ready → active when a plan is written
  _sm=".vbw-planning/STATE.md"
  if [ -f "$_sm" ] && grep -q '^Status: ready' "$_sm" 2>/dev/null; then
    _tmp="${_sm}.tmp.$$"
    sed 's/^Status: ready/Status: active/' "$_sm" > "$_tmp" 2>/dev/null && \
      mv "$_tmp" "$_sm" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
  fi
fi

# Summary trigger: update execution state + progress (JSONL or legacy MD)
IS_SUMMARY=false
if echo "$FILE_PATH" | grep -qE 'phases/.*\.summary\.jsonl$'; then
  IS_SUMMARY=true
elif echo "$FILE_PATH" | grep -qE 'phases/.*-SUMMARY\.md$'; then
  IS_SUMMARY=true
fi

if [ "$IS_SUMMARY" != true ]; then
  exit 0
fi

STATE_FILE=".vbw-planning/.execution-state.json"
[ -f "$STATE_FILE" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Parse summary for phase, plan, status (JSONL or legacy YAML)
PHASE=""
PLAN=""
STATUS=""

if echo "$FILE_PATH" | grep -qE '\.summary\.jsonl$'; then
  # JSONL summary: parse first line with jq
  if command -v jq >/dev/null 2>&1; then
    PHASE=$(jq -r '.p // ""' "$FILE_PATH" 2>/dev/null)
    PLAN=$(jq -r '.n // ""' "$FILE_PATH" 2>/dev/null)
    STATUS=$(jq -r '.s // "complete"' "$FILE_PATH" 2>/dev/null)
  fi
else
  # Legacy SUMMARY.md: parse YAML frontmatter
  IN_FRONTMATTER=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ "$IN_FRONTMATTER" -eq 0 ]; then
        IN_FRONTMATTER=1
        continue
      else
        break
      fi
    fi
    if [ "$IN_FRONTMATTER" -eq 1 ]; then
      key=$(echo "$line" | cut -d: -f1 | tr -d ' ')
      val=$(echo "$line" | cut -d: -f2- | sed 's/^ *//')
      case "$key" in
        phase) PHASE="$val" ;;
        plan) PLAN="$val" ;;
        status) STATUS="$val" ;;
      esac
    fi
  done < "$FILE_PATH"
fi

if [ -z "$PHASE" ] || [ -z "$PLAN" ]; then
  exit 0
fi

STATUS="${STATUS:-completed}"
TEMP_FILE="${STATE_FILE}.tmp"
jq --arg phase "$PHASE" --arg plan "$PLAN" --arg status "$STATUS" '
  if .phases[$phase] and .phases[$phase][$plan] then
    .phases[$phase][$plan].status = $status
  else
    .
  end
' "$STATE_FILE" > "$TEMP_FILE" 2>/dev/null && mv "$TEMP_FILE" "$STATE_FILE" 2>/dev/null

update_state_md "$(dirname "$FILE_PATH")"
update_roadmap "$(dirname "$FILE_PATH")"
update_model_profile
advance_phase "$(dirname "$FILE_PATH")"

exit 0
