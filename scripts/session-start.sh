#!/bin/bash
set -u
# SessionStart: YOLO project state detection, update checks, cache maintenance (exit 0)

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"hookSpecificOutput":{"additionalContext":"YOLO: jq not found. Install: brew install jq (macOS) / apt install jq (Linux). All 17 YOLO quality gates are disabled until jq is installed -- no commit validation, no security filtering, no file guarding."}}'
  exit 0
fi

PLANNING_DIR=".yolo-planning"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# OPTIMIZATION 9: Config auto-migrate guard (only run once per version)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_VER=$(tr -d '[:space:]' < "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0.0.0")
MIGRATE_MARKER="$PLANNING_DIR/.config-migrated-${LOCAL_VER}"
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ] && [ ! -f "$MIGRATE_MARKER" ]; then
  if ! jq -e '.model_profile' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
    TMP=$(mktemp)
    jq '. + {model_profile: "quality", model_overrides: {}}' "$PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$PLANNING_DIR/config.json"
  fi
  if ! jq -e '.team_mode' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
    TMP=$(mktemp)
    jq '. + {team_mode: "task"}' "$PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$PLANNING_DIR/config.json"
  fi
  touch "$MIGRATE_MARKER" 2>/dev/null
fi

# Clean compaction marker at session start (fresh-session guarantee, REQ-15)
rm -f "$PLANNING_DIR/.compaction-marker" 2>/dev/null

UPDATE_MSG=""

# --- First-run welcome (DXP-03) ---
YOLO_MARKER="$CLAUDE_DIR/.yolo-welcomed"
WELCOME_MSG=""
if [ ! -f "$YOLO_MARKER" ]; then
  mkdir -p "$CLAUDE_DIR" 2>/dev/null
  touch "$YOLO_MARKER" 2>/dev/null
  WELCOME_MSG="FIRST RUN -- Display this welcome to the user verbatim: Welcome to YOLO -- YOLO — Your Own Local Orchestrator. You're not an engineer anymore. You're a prompt jockey with commit access. At least do it properly. Quick start: /yolo:go -- describe your project and YOLO handles the rest. Type /yolo:help for the full story. --- "
fi

# --- Update check (once per day, fail-silent) ---

CACHE="/tmp/yolo-update-check-$(id -u)"
NOW=$(date +%s)
if [ "$(uname)" = "Darwin" ]; then
  MT=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
else
  MT=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
fi

# OPTIMIZATION 1: Async curl for update check (non-blocking)
if [ ! -f "$CACHE" ] || [ $((NOW - MT)) -gt 86400 ]; then
  # Background the entire fetch — result available on NEXT session
  { REMOTE_VER=$(curl -sf --max-time 3 \
      "https://raw.githubusercontent.com/slavpetroff/yolo/main/VERSION" \
      2>/dev/null | tr -d '[:space:]')
    echo "${LOCAL_VER:-0.0.0}|${REMOTE_VER:-0.0.0}" > "$CACHE" 2>/dev/null
  } &
  disown

  # Read stale cached value if available (or empty on first run)
  if [ -f "$CACHE" ]; then
    IFS='|' read -r _cached_local _cached_remote < "$CACHE" 2>/dev/null || true
    if [ -n "${_cached_remote:-}" ] && [ "${_cached_remote:-}" != "0.0.0" ] && [ "${_cached_remote:-}" != "${LOCAL_VER:-}" ]; then
      UPDATE_MSG=" UPDATE AVAILABLE: v${LOCAL_VER:-0.0.0} -> v${_cached_remote:-0.0.0}. Run /yolo:update to upgrade."
    fi
  fi
else
  # Read cached result
  IFS='|' read -r _cached_local REMOTE_VER < "$CACHE" 2>/dev/null || true
  if [ -n "${REMOTE_VER:-}" ] && [ "${REMOTE_VER:-}" != "0.0.0" ] && [ "${REMOTE_VER:-}" != "${LOCAL_VER:-}" ]; then
    UPDATE_MSG=" UPDATE AVAILABLE: v${LOCAL_VER:-0.0.0} -> v${REMOTE_VER:-0.0.0}. Run /yolo:update to upgrade."
  fi
fi

# OPTIMIZATION 2: Defer statusLine migration (only check on version change)
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SL_MARKER="/tmp/yolo-sl-migrated-$(id -u)-${LOCAL_VER}"
if [ -f "$SETTINGS_FILE" ] && [ ! -f "$SL_MARKER" ]; then
  SL_CMD=$(jq -r '.statusLine.command // .statusLine // ""' "$SETTINGS_FILE" 2>/dev/null)
  SL_NEEDS_UPDATE=false
  if echo "$SL_CMD" | grep -q 'for f in' && echo "$SL_CMD" | grep -q 'yolo-statusline'; then
    SL_NEEDS_UPDATE=true
  elif echo "$SL_CMD" | grep -q 'yolo-statusline' && ! echo "$SL_CMD" | grep -q 'command ls'; then
    # Bare ls without 'command' prefix — vulnerable to eza/lsd aliases
    SL_NEEDS_UPDATE=true
  fi
  if [ "$SL_NEEDS_UPDATE" = true ]; then
    CORRECT_CMD="bash -c 'f=\$(command ls -1 \"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}\"/plugins/cache/yolo-marketplace/yolo/*/scripts/yolo-statusline.sh 2>/dev/null | sort -V | tail -1) && [ -f \"\$f\" ] && exec bash \"\$f\"'"
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
    if ! jq --arg cmd "$CORRECT_CMD" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"; then
      cp "${SETTINGS_FILE}.bak" "$SETTINGS_FILE"
      rm -f "${SETTINGS_FILE}.tmp"
    else
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    fi
    rm -f "${SETTINGS_FILE}.bak"
  fi
  touch "$SL_MARKER" 2>/dev/null
fi

# --- Clean old cache versions (keep only latest) ---
CACHE_DIR="$CLAUDE_DIR/plugins/cache/yolo-marketplace/yolo"
YOLO_CLEANUP_LOCK="/tmp/yolo-cache-cleanup-lock"
if [ -d "$CACHE_DIR" ] && mkdir "$YOLO_CLEANUP_LOCK" 2>/dev/null; then
  VERSIONS=$(command ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V)
  COUNT=$(echo "$VERSIONS" | wc -l | tr -d ' ')
  if [ "$COUNT" -gt 1 ]; then
    echo "$VERSIONS" | head -n $((COUNT - 1)) | while IFS= read -r dir; do rm -rf "$dir"; done
  fi
  rmdir "$YOLO_CLEANUP_LOCK" 2>/dev/null
fi

# --- Cache integrity check (nuke if critical files missing, skip during update) ---
if [ -d "$CACHE_DIR" ]; then
  UPDATE_LOCK="/tmp/yolo-update-lock-$(id -u)"
  SKIP_INTEGRITY=false
  
  if [ -f "$UPDATE_LOCK" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      LOCK_AGE=$((NOW - $(stat -f %m "$UPDATE_LOCK" 2>/dev/null || echo "$NOW")))
    else
      LOCK_AGE=$((NOW - $(stat -c %Y "$UPDATE_LOCK" 2>/dev/null || echo "$NOW")))
    fi
    if [ "$LOCK_AGE" -lt 60 ]; then
      SKIP_INTEGRITY=true
    fi
  fi
  
  if [ "$SKIP_INTEGRITY" = false ]; then
    LATEST_CACHE=$(command ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V | tail -1)
    if [ -n "$LATEST_CACHE" ]; then
      INTEGRITY_OK=true
      for f in commands/init.md .claude-plugin/plugin.json VERSION config/defaults.json; do
        if [ ! -f "$LATEST_CACHE$f" ]; then
          INTEGRITY_OK=false
          break
        fi
      done
      if [ "$INTEGRITY_OK" = false ]; then
        echo "YOLO cache integrity check failed — nuking stale cache" >&2
        rm -rf "$CACHE_DIR"
      fi
    fi
  fi
fi

# --- Auto-sync stale marketplace checkout ---
# OPTIMIZATION 6: Use VERSION files instead of jq for version comparison
MKT_DIR="$CLAUDE_DIR/plugins/marketplaces/yolo-marketplace"
if [ -d "$MKT_DIR/.git" ] && [ -d "$CACHE_DIR" ]; then
  MKT_VER=$(tr -d '[:space:]' < "$MKT_DIR/VERSION" 2>/dev/null || echo "0")
  CACHE_VER_FILE=$(command ls -d "$CACHE_DIR"/*/VERSION 2>/dev/null | sort -V | tail -1)
  CACHE_VER=$(tr -d '[:space:]' < "$CACHE_VER_FILE" 2>/dev/null || echo "0")
  if [ "$MKT_VER" != "$CACHE_VER" ] && [ -n "$CACHE_VER" ] && [ "$CACHE_VER" != "0" ]; then
    (git -C "$MKT_DIR" fetch origin --quiet 2>/dev/null && \
      if git -C "$MKT_DIR" diff --quiet 2>/dev/null; then
        git -C "$MKT_DIR" reset --hard origin/main --quiet 2>/dev/null
      else
        echo "YOLO: marketplace checkout has local modifications — skipping reset" >&2
      fi)
  fi
  # Content staleness: compare command counts
  if [ -d "$MKT_DIR/commands" ] && [ -d "$CACHE_DIR" ]; then
    LATEST_VER=$(command ls -d "$CACHE_DIR"/*/ 2>/dev/null | sort -V | tail -1)
    if [ -n "$LATEST_VER" ] && [ -d "${LATEST_VER}commands" ]; then
      MKT_CMD_COUNT=$(command ls "$MKT_DIR/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
      CACHE_CMD_COUNT=$(command ls "${LATEST_VER}commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
      if [ "${MKT_CMD_COUNT:-0}" -ne "${CACHE_CMD_COUNT:-0}" ]; then
        echo "YOLO cache stale — marketplace has ${MKT_CMD_COUNT} commands, cache has ${CACHE_CMD_COUNT}" >&2
        rm -rf "$CACHE_DIR"
      fi
    fi
  fi
fi

# --- Sync commands to CLAUDE_DIR/commands/yolo/ for autocomplete prefix ---
YOLO_CACHE_CMD=$(command ls -d "$CLAUDE_DIR"/plugins/cache/yolo-marketplace/yolo/*/commands 2>/dev/null | sort -V | tail -1)
YOLO_GLOBAL_CMD="$CLAUDE_DIR/commands/yolo"
if [ -d "$YOLO_CACHE_CMD" ]; then
  mkdir -p "$YOLO_GLOBAL_CMD"
  rm -f "$YOLO_GLOBAL_CMD"/*.md 2>/dev/null
  cp "$YOLO_CACHE_CMD"/*.md "$YOLO_GLOBAL_CMD/" 2>/dev/null
fi

# --- Auto-install git hooks if missing ---
PROJECT_GIT_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_GIT_DIR=""
if [ -n "$PROJECT_GIT_DIR" ] && [ ! -f "$PROJECT_GIT_DIR/.git/hooks/pre-push" ] && [ -f "$SCRIPT_DIR/install-hooks.sh" ]; then
  (bash "$SCRIPT_DIR/install-hooks.sh" 2>/dev/null) || true
fi

# --- Reconcile orphaned execution state ---
# OPTIMIZATION 5: Batch exec state jq (merge multiple jq reads into single call)
EXEC_STATE="$PLANNING_DIR/.execution-state.json"
if [ -f "$EXEC_STATE" ]; then
  IFS='|' read -r EXEC_STATUS PHASE_NAME PHASE_NUM EXEC_STEP EXEC_TASK PLAN_COUNT <<< \
    "$(jq -r '[(.status // ""), (.phase_name // ""), (.phase // ""), (.step // ""), (.current_task // ""), (.plans | length | tostring)] | join("|")' "$EXEC_STATE" 2>/dev/null)"
  if [ "$EXEC_STATUS" = "running" ]; then
    PHASE_DIR=""
    if [ -n "$PHASE_NUM" ]; then
      PHASE_DIR=$(command ls -d "$PLANNING_DIR/phases/${PHASE_NUM}-"* 2>/dev/null | head -1)
    fi
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      # OPTIMIZATION 8: Bash glob replacing find for summary counting
      SUMMARY_COUNT=0
      for f in "$PHASE_DIR"/*.summary.jsonl "$PHASE_DIR"/*-SUMMARY.md; do [ -f "$f" ] && SUMMARY_COUNT=$((SUMMARY_COUNT+1)); done
      if [ "${SUMMARY_COUNT:-0}" -ge "${PLAN_COUNT:-1}" ] && [ "${PLAN_COUNT:-0}" -gt 0 ]; then
        # All plans have summaries — build finished after crash
        jq '.status = "complete"' "$EXEC_STATE" > "$PLANNING_DIR/.execution-state.json.tmp" && mv "$PLANNING_DIR/.execution-state.json.tmp" "$EXEC_STATE"
        BUILD_STATE="complete (recovered)"
      else
        BUILD_STATE="interrupted (${SUMMARY_COUNT:-0}/${PLAN_COUNT:-0} plans"
        [ -n "$EXEC_STEP" ] && BUILD_STATE="${BUILD_STATE}, step: ${EXEC_STEP}"
        [ -n "$EXEC_TASK" ] && BUILD_STATE="${BUILD_STATE}, task: ${EXEC_TASK}"
        BUILD_STATE="${BUILD_STATE})"

        # Clear stale compiled context — force recompile from committed JSONL
        rm -f "$PHASE_DIR"/.ctx-*.toon 2>/dev/null

        # Recompile context for all roles from committed artifacts
        COMPILE_SCRIPT="$SCRIPT_DIR/compile-context.sh"
        if [ -f "$COMPILE_SCRIPT" ]; then
          for role in architect lead senior dev qa qa-code security debugger; do
            bash "$COMPILE_SCRIPT" "$PHASE_NUM" "$role" "$PLANNING_DIR/phases" 2>/dev/null || true
          done
        fi
      fi
      UPDATE_MSG="${UPDATE_MSG} Build state: ${BUILD_STATE}."
    fi
  fi
fi

# --- Orphaned .dept-status cleanup ---
# Clean stale .dept-status-*.json files from prior crashed sessions.
# Only runs when agent_teams=true in config (no cleanup needed for task-only mode).
if [ -d "$PLANNING_DIR" ] && [ -f "$PLANNING_DIR/config.json" ]; then
  DEPT_CLEANUP_TEAMS=$(jq -r 'if .agent_teams == false then "false" else "true" end' "$PLANNING_DIR/config.json" 2>/dev/null)
  if [ "$DEPT_CLEANUP_TEAMS" = "true" ]; then
    STALE_THRESHOLD=$((24 * 60 * 60))  # 24 hours in seconds
    for dept_file in "$PLANNING_DIR"/.dept-status-*.json; do
      [ -f "$dept_file" ] || continue
      if [ "$(uname)" = "Darwin" ]; then
        FILE_EPOCH=$(stat -f %m "$dept_file" 2>/dev/null || echo "$NOW")
      else
        FILE_EPOCH=$(stat -c %Y "$dept_file" 2>/dev/null || echo "$NOW")
      fi
      FILE_AGE=$((NOW - FILE_EPOCH))
      if [ "$FILE_AGE" -gt "$STALE_THRESHOLD" ]; then
        echo "YOLO: cleaning stale dept-status file: $(basename "$dept_file") (age: ${FILE_AGE}s)" >&2
        rm -f "$dept_file"
      fi
    done
  fi
fi

# --- Project state ---

if [ ! -d "$PLANNING_DIR" ]; then
  jq -n --arg update "$UPDATE_MSG" --arg welcome "$WELCOME_MSG" '{
    "hookSpecificOutput": {
      "additionalContext": ($welcome + "No .yolo-planning/ directory found. Run /yolo:init to set up the project." + $update)
    }
  }'
  exit 0
fi

# --- Resolve ACTIVE milestone ---
MILESTONE_SLUG="none"
if [ -f "$PLANNING_DIR/ACTIVE" ]; then
  MILESTONE_SLUG=$(cat "$PLANNING_DIR/ACTIVE" 2>/dev/null | tr -d '[:space:]')
  MILESTONE_DIR="$PLANNING_DIR/milestones/$MILESTONE_SLUG"
  if [ ! -d "$MILESTONE_DIR" ]; then
    # ACTIVE points to nonexistent directory — fall back
    MILESTONE_SLUG="none"
    MILESTONE_DIR="$PLANNING_DIR"
    PHASES_DIR="$PLANNING_DIR/phases"
  else
    PHASES_DIR="$MILESTONE_DIR/phases"
  fi
else
  MILESTONE_DIR="$PLANNING_DIR"
  PHASES_DIR="$PLANNING_DIR/phases"
fi

# --- Parse config ---
CONFIG_FILE="$PLANNING_DIR/config.json"
config_effort="balanced"
config_autonomy="standard"
config_auto_commit="true"
config_verification="standard"
config_agent_teams="true"
config_max_tasks="5"
if [ -f "$CONFIG_FILE" ]; then
  IFS='|' read -r config_effort config_autonomy config_auto_commit config_verification \
    config_agent_teams config_max_tasks <<< \
    "$(jq -r '[
      (.effort // "balanced"),
      (.autonomy // "standard"),
      (.auto_commit // true | tostring),
      (.verification_tier // "standard"),
      (.agent_teams // true | tostring),
      (.max_tasks_per_plan // 5 | tostring)
    ] | join("|")' "$CONFIG_FILE" 2>/dev/null)"
fi

# --- Parse state.json (preferred) or STATE.md (fallback) ---
STATE_JSON="$MILESTONE_DIR/state.json"
STATE_MD="$MILESTONE_DIR/STATE.md"
phase_pos="unknown"
phase_total="unknown"
phase_name="unknown"
phase_status="unknown"
progress_pct="0"
if [ -f "$STATE_JSON" ] && command -v jq >/dev/null 2>&1; then
  IFS='|' read -r phase_pos phase_total phase_status progress_pct <<< \
    "$(jq -r '[(.ph // "unknown"), (.tt // "unknown"), (.st // "unknown"), (.pr // 0 | tostring)] | join("|")' "$STATE_JSON" 2>/dev/null)"
  # Derive phase name from directory
  if [ -n "$phase_pos" ] && [ "$phase_pos" != "unknown" ]; then
    phase_dir_match=$(command ls -d "$PLANNING_DIR/phases/$(printf '%02d' "$phase_pos")-"* 2>/dev/null | head -1)
    if [ -n "$phase_dir_match" ]; then
      phase_name=$(basename "$phase_dir_match" | sed 's/^[0-9]*-//' | tr '-' ' ')
    fi
  fi
elif [ -f "$STATE_MD" ]; then
  # Fallback: parse STATE.md (less reliable but backward-compat)
  phase_line=$(grep -m1 "Current Phase" "$STATE_MD" 2>/dev/null || true)
  if [ -n "$phase_line" ]; then
    phase_pos=$(echo "$phase_line" | grep -oE '[0-9]+' | head -1)
  fi
  progress_line=$(grep -m1 "Progress" "$STATE_MD" 2>/dev/null || true)
  if [ -n "$progress_line" ]; then
    progress_pct=$(echo "$progress_line" | grep -oE '[0-9]+' | head -1)
  fi
fi
: "${phase_pos:=unknown}"
: "${phase_total:=unknown}"
: "${phase_name:=unknown}"
: "${phase_status:=unknown}"
: "${progress_pct:=0}"

# --- Determine next action ---
NEXT_ACTION=""
if [ ! -f "$PLANNING_DIR/PROJECT.md" ]; then
  NEXT_ACTION="/yolo:init"
elif [ ! -d "$PHASES_DIR" ] || [ -z "$(command ls -d "$PHASES_DIR"/*/ 2>/dev/null)" ]; then
  NEXT_ACTION="/yolo:go (needs scoping)"
else
  # Check execution state for interrupted builds
  EXEC_STATE="$PLANNING_DIR/.execution-state.json"
  MILESTONE_EXEC_STATE="$MILESTONE_DIR/.execution-state.json"
  exec_running=false
  for es in "$EXEC_STATE" "$MILESTONE_EXEC_STATE"; do
    if [ -f "$es" ]; then
      es_status=$(jq -r '.status // ""' "$es" 2>/dev/null)
      if [ "$es_status" = "running" ]; then
        exec_running=true
        break
      fi
    fi
  done

  if [ "$exec_running" = true ]; then
    NEXT_ACTION="/yolo:go (build interrupted, will resume)"
  else
    # OPTIMIZATION 8: Bash glob replacing find for plan/summary counting
    all_done=true
    next_phase=""
    for pdir in $(command ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort); do
      pname=$(basename "$pdir")
      plan_count=0
      for f in "$pdir"/*.plan.jsonl "$pdir"/*-PLAN.md; do [ -f "$f" ] && plan_count=$((plan_count+1)); done
      summary_count=0
      for f in "$pdir"/*.summary.jsonl "$pdir"/*-SUMMARY.md; do [ -f "$f" ] && summary_count=$((summary_count+1)); done
      if [ "${plan_count:-0}" -eq 0 ]; then
        # Phase has no plans yet — needs planning
        pnum=${pname%%-*}
        NEXT_ACTION="/yolo:go (Phase $pnum needs planning)"
        all_done=false
        break
      elif [ "${summary_count:-0}" -lt "${plan_count:-0}" ]; then
        # Phase has plans but not all executed
        pnum=${pname%%-*}
        NEXT_ACTION="/yolo:go (Phase $pnum planned, needs execution)"
        all_done=false
        break
      fi
    done
    if [ "$all_done" = true ]; then
      NEXT_ACTION="/yolo:go --archive"
    fi
  fi
fi

# --- Build additionalContext ---
CTX="YOLO project detected."
CTX="$CTX Milestone: ${MILESTONE_SLUG}."
CTX="$CTX Phase: ${phase_pos}/${phase_total} (${phase_name}) -- ${phase_status}."
CTX="$CTX Progress: ${progress_pct}%."
CTX="$CTX Config: effort=${config_effort}, autonomy=${config_autonomy}, auto_commit=${config_auto_commit}, verification=${config_verification}, agent_teams=${config_agent_teams}, max_tasks=${config_max_tasks}."
CTX="$CTX Next: ${NEXT_ACTION}."

jq -n --arg ctx "$CTX" --arg update "$UPDATE_MSG" --arg welcome "$WELCOME_MSG" '{
  "hookSpecificOutput": {
    "additionalContext": ($welcome + $ctx + $update)
  }
}'

exit 0
