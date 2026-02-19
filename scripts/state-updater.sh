#!/bin/bash
set -u
# PostToolUse: Auto-update STATE.md, state.json, ROADMAP.md + .execution-state.json on PLAN/SUMMARY writes
# Non-blocking, fail-open (always exit 0)

# --- Shared helper: count plans+summaries via bash glob (no subprocesses) ---
count_plans_summaries() {
  local dir="$1"
  local plans=0 summaries=0
  for f in "$dir"/*.plan.jsonl "$dir"/*-PLAN.md; do [ -f "$f" ] && plans=$((plans+1)); done
  for f in "$dir"/*.summary.jsonl "$dir"/*-SUMMARY.md; do [ -f "$f" ] && summaries=$((summaries+1)); done
  echo "$plans $summaries"
}

update_state_md() {
  local phase_dir="$1"
  local state_md=".yolo-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  local plan_count summary_count pct
  read -r plan_count summary_count <<< "$(count_plans_summaries "$phase_dir")"

  if [ "$plan_count" -gt 0 ]; then
    pct=$(( (summary_count * 100) / plan_count ))
  else
    pct=0
  fi

  local tmp="${state_md}.tmp.$$"
  sed -e "s/^Plans: .*/Plans: ${summary_count}\/${plan_count}/" \
      -e "s/^Progress: .*/Progress: ${pct}%/" "$state_md" > "$tmp" 2>/dev/null && \
    mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

slug_to_name() {
  echo "$1" | sed 's/^[0-9]*-//' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

update_roadmap() {
  local phase_dir="$1"
  local phase_num="$2"
  local roadmap=".yolo-planning/ROADMAP.md"

  [ -f "$roadmap" ] || return 0
  [ -z "$phase_num" ] && return 0

  local plan_count summary_count status date_str
  read -r plan_count summary_count <<< "$(count_plans_summaries "$phase_dir")"

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
  existing_name=$(grep -E "^\| *${phase_num} - " "$roadmap" | head -1 | sed 's/^| *[0-9]* - //;s/ *|.*//')
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
  local state_md=".yolo-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  # Read active model profile from config
  local model_profile
  model_profile=$(jq -r '.model_profile // "balanced"' .yolo-planning/config.json 2>/dev/null || echo "balanced")

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

update_state_json() {
  local phase_dir="$1"
  local phase_num="$2"
  local state_json=".yolo-planning/state.json"

  [ -f "$state_json" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -z "$phase_num" ] && return 0

  # Compute overall progress across all phases using glob counting
  local phases_dir total pct
  phases_dir=$(dirname "$phase_dir")
  total=0
  local total_plans=0 total_summaries=0
  for dir in $(command ls -d "$phases_dir"/*/ 2>/dev/null | sort); do
    total=$((total + 1))
    local dp ds
    read -r dp ds <<< "$(count_plans_summaries "$dir")"
    total_plans=$((total_plans + dp))
    total_summaries=$((total_summaries + ds))
  done

  if [ "$total_plans" -gt 0 ]; then
    pct=$(( (total_summaries * 100) / total_plans ))
  else
    pct=0
  fi

  # Determine status and write in a single jq call (batch read+write)
  local tmp="${state_json}.tmp.$$"
  jq --argjson ph "$phase_num" --argjson tt "$total" --argjson pr "$pct" \
    --argjson tp "$total_plans" --argjson ts "$total_summaries" \
    '.ph = $ph | .tt = $tt | .pr = $pr |
     if ($tp > 0 and $ts == $tp) then .st = "complete"
     elif ($ts > 0) then .st = "executing"
     elif ($tp > 0) then .st = "executing"
     else . end' "$state_json" > "$tmp" 2>/dev/null && \
    mv "$tmp" "$state_json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

advance_phase() {
  local phase_dir="$1"
  local state_md=".yolo-planning/STATE.md"

  [ -f "$state_md" ] || return 0

  # Check if triggering phase is complete using glob counting
  local plan_count summary_count
  read -r plan_count summary_count <<< "$(count_plans_summaries "$phase_dir")"
  [ "$plan_count" -gt 0 ] && [ "$summary_count" -eq "$plan_count" ] || return 0

  # Scan all phase dirs to find next incomplete
  local phases_dir total next_num next_name all_done
  phases_dir=$(dirname "$phase_dir")
  total=0
  for _d in $(command ls -d "$phases_dir"/*/ 2>/dev/null); do total=$((total + 1)); done
  next_num=""
  next_name=""
  all_done=true

  for dir in $(command ls -d "$phases_dir"/*/ 2>/dev/null | sort); do
    local dirname_base p s
    dirname_base=$(basename "$dir")
    read -r p s <<< "$(count_plans_summaries "$dir")"

    if [ "$p" -eq 0 ] || [ "$s" -lt "$p" ]; then
      if [ -z "$next_num" ]; then
        next_num=${dirname_base%%-*}
        next_num=$(( 10#$next_num ))
        [ -z "$next_num" ] && next_num=0
        next_name=$(slug_to_name "$dirname_base")
      fi
      all_done=false
      break
    fi
  done

  [ "$total" -eq 0 ] && return 0

  local tmp="${state_md}.tmp.$$"
  local state_json=".yolo-planning/state.json"
  if [ "$all_done" = true ]; then
    sed "s/^Status: .*/Status: complete/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    # Update state.json to complete (single jq call)
    if [ -f "$state_json" ] && command -v jq >/dev/null 2>&1; then
      local jtmp="${state_json}.tmp.$$"
      jq '.st = "complete" | .pr = 100' "$state_json" > "$jtmp" 2>/dev/null && \
        mv "$jtmp" "$state_json" 2>/dev/null || rm -f "$jtmp" 2>/dev/null
    fi
  elif [ -n "$next_num" ]; then
    sed -e "s/^Phase: .*/Phase: ${next_num} of ${total} (${next_name})/" \
        -e "s/^Status: .*/Status: ready/" "$state_md" > "$tmp" 2>/dev/null && \
      mv "$tmp" "$state_md" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    # Advance state.json to next phase (single jq call)
    if [ -f "$state_json" ] && command -v jq >/dev/null 2>&1; then
      local jtmp="${state_json}.tmp.$$"
      jq --argjson ph "$next_num" --argjson tt "$total" '.ph = $ph | .tt = $tt | .st = "planning" | .step = "plan"' \
        "$state_json" > "$jtmp" 2>/dev/null && \
        mv "$jtmp" "$state_json" 2>/dev/null || rm -f "$jtmp" 2>/dev/null
    fi
  fi
}

update_phase_orchestration() {
  local phase_dir="$1" file_path="$2"
  local ORCH_FILE="$phase_dir/.phase-orchestration.json"
  [ -f "$ORCH_FILE" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  # Detect department from active agent
  local ACTIVE_AGENT=""
  [ -f ".yolo-planning/.active-agent" ] && ACTIVE_AGENT=$(<".yolo-planning/.active-agent")
  local ORCH_DEPT
  case "${ACTIVE_AGENT:-}" in
    yolo-fe-*) ORCH_DEPT="frontend" ;;
    yolo-ux-*) ORCH_DEPT="uiux" ;;
    yolo-*) ORCH_DEPT="backend" ;;
    *) return 0 ;;
  esac

  # Determine step from file path
  local ORCH_STEP
  case "$file_path" in
    *plan.jsonl) ORCH_STEP="planning" ;;
    *summary.jsonl) ORCH_STEP="implementation" ;;
    *) return 0 ;;
  esac

  # Update department step atomically
  local tmp="${ORCH_FILE}.tmp.$$"
  jq --arg dept "$ORCH_DEPT" --arg step "$ORCH_STEP" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.departments[$dept].step = $step | .departments[$dept].updated_at = $now' \
    "$ORCH_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$ORCH_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null

  # Check if all departments are complete
  local all_complete
  all_complete=$(jq '[.departments[]] | all(.status == "complete")' "$ORCH_FILE" 2>/dev/null) || true
  if [ "${all_complete:-}" = "true" ]; then
    local tmp2="${ORCH_FILE}.tmp.$$"
    jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.gates["all-depts"].status = "passed" | .gates["all-depts"].passed_at = $now' \
      "$ORCH_FILE" > "$tmp2" 2>/dev/null && mv "$tmp2" "$ORCH_FILE" 2>/dev/null || rm -f "$tmp2" 2>/dev/null
  fi
}

save_escalation_state() {
  local phase_dir="$1" agent="$2" reason="$3" severity="${4:-medium}" target="${5:-}"
  local esc_file=".yolo-planning/.escalation-state.json"
  command -v jq >/dev/null 2>&1 || return 0

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local phase_num
  phase_num=$(basename "$phase_dir" | cut -d'-' -f1)

  if [ ! -f "$esc_file" ]; then
    echo '{"pending":[],"resolved":[]}' > "$esc_file"
  fi

  local tmp="${esc_file}.tmp.$$"
  jq --arg agent "$agent" --arg reason "$reason" --arg sev "$severity" \
     --arg target "$target" --arg phase "$phase_num" --arg dt "$now" \
    '.pending += [{"agent":$agent,"reason":$reason,"severity":$sev,"target":$target,"phase":$phase,"created_at":$dt,"status":"pending"}]' \
    "$esc_file" > "$tmp" 2>/dev/null && mv "$tmp" "$esc_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

load_escalation_state() {
  local esc_file=".yolo-planning/.escalation-state.json"
  if [ -f "$esc_file" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.pending | length' "$esc_file" 2>/dev/null
  else
    echo "0"
  fi
}

resolve_escalation() {
  local index="${1:-0}" resolution="$2"
  local esc_file=".yolo-planning/.escalation-state.json"
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$esc_file" ] || return 0

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local tmp="${esc_file}.tmp.$$"
  jq --argjson idx "$index" --arg res "$resolution" --arg dt "$now" \
    '.pending[$idx].status = "resolved" | .pending[$idx].resolved_at = $dt | .pending[$idx].resolution = $res |
     .resolved += [.pending[$idx]] | .pending = [.pending[] | select(.status == "pending")]' \
    "$esc_file" > "$tmp" 2>/dev/null && mv "$tmp" "$esc_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

commit_state_artifacts() {
  local msg="${1:-state transition}"
  # Non-blocking: fail silently if git unavailable or nothing to commit
  command -v git >/dev/null 2>&1 || return 0

  local files_to_add=""
  for f in .yolo-planning/STATE.md .yolo-planning/state.json .yolo-planning/ROADMAP.md .yolo-planning/.execution-state.json .yolo-planning/.escalation-state.json; do
    if [ -f "$f" ] && git diff --name-only "$f" 2>/dev/null | grep -q .; then
      files_to_add="$files_to_add $f"
    elif [ -f "$f" ] && ! git ls-files --error-unmatch "$f" 2>/dev/null | grep -q .; then
      files_to_add="$files_to_add $f"
    fi
  done

  if [ -n "${PHASE_DIR:-}" ] && [ -f "$PHASE_DIR/.phase-orchestration.json" ]; then
    if git diff --name-only "$PHASE_DIR/.phase-orchestration.json" 2>/dev/null | grep -q .; then
      files_to_add="$files_to_add $PHASE_DIR/.phase-orchestration.json"
    fi
  fi

  [ -z "$files_to_add" ] && return 0

  git add $files_to_add 2>/dev/null || return 0
  git commit -m "chore(state): $msg" --no-verify 2>/dev/null || return 0
}

# --- OPTIMIZATION 1: Early exit via bash case before jq parsing ---
INPUT=$(cat)
# Quick pattern check: bail immediately if not a plan/summary file path
case "$INPUT" in
  *plan.jsonl*|*PLAN.md*|*summary.jsonl*|*SUMMARY.md*) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# --- OPTIMIZATION 3: Cache dirname and phase_num once ---
PHASE_DIR=$(dirname "$FILE_PATH")
PHASE_DIR_BASE=$(basename "$PHASE_DIR")
CACHED_PHASE_NUM=${PHASE_DIR_BASE%%-*}
CACHED_PHASE_NUM=$(( 10#$CACHED_PHASE_NUM )) 2>/dev/null || CACHED_PHASE_NUM=""

# Plan trigger: update plan count + activate status (JSONL or legacy MD)
if echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+-[0-9]+\.plan\.jsonl$' || echo "$FILE_PATH" | grep -qE 'phases/[^/]+/[0-9]+-[0-9]+-PLAN\.md$'; then
  update_state_md "$PHASE_DIR"
  update_roadmap "$PHASE_DIR" "$CACHED_PHASE_NUM"
  update_state_json "$PHASE_DIR" "$CACHED_PHASE_NUM"
  update_phase_orchestration "$PHASE_DIR" "$FILE_PATH"
  # Status: ready → active when a plan is written
  _sm=".yolo-planning/STATE.md"
  if [ -f "$_sm" ] && grep -q '^Status: ready' "$_sm" 2>/dev/null; then
    _tmp="${_sm}.tmp.$$"
    sed 's/^Status: ready/Status: active/' "$_sm" > "$_tmp" 2>/dev/null && \
      mv "$_tmp" "$_sm" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
  fi
  # Also stage+commit the plan file itself alongside state artifacts
  git add "$FILE_PATH" 2>/dev/null || true
  commit_state_artifacts "plan written $(basename "$FILE_PATH")"
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

STATE_FILE=".yolo-planning/.execution-state.json"
[ -f "$STATE_FILE" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Parse summary for phase, plan, status (JSONL or legacy YAML)
PHASE=""
PLAN=""
STATUS=""

if echo "$FILE_PATH" | grep -qE '\.summary\.jsonl$'; then
  # JSONL summary: parse first line with jq
  if command -v jq >/dev/null 2>&1; then
    IFS='|' read -r PHASE PLAN STATUS <<< "$(jq -r '[(.p // ""), (.n // ""), (.s // "complete")] | join("|")' "$FILE_PATH" 2>/dev/null)"
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

update_state_md "$PHASE_DIR"
update_roadmap "$PHASE_DIR" "$CACHED_PHASE_NUM"
update_state_json "$PHASE_DIR" "$CACHED_PHASE_NUM"
update_model_profile
advance_phase "$PHASE_DIR"
update_phase_orchestration "$PHASE_DIR" "$FILE_PATH"

# Stage summary + commit all state artifacts
git add "$FILE_PATH" 2>/dev/null || true
commit_state_artifacts "summary written $(basename "$FILE_PATH")"

exit 0
