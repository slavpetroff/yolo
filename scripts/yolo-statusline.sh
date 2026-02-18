#!/bin/bash
# YOLO Status Line — 4-line dashboard (L1: project, L2: context, L3: usage+cache, L4: model/cost)
# Cache: {prefix}-fast (5s), {prefix}-slow (60s), {prefix}-cost (per-render), {prefix}-ok (permanent)

input=$(cat)

# Colors
C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m'
D='\033[2m' B='\033[1m' X='\033[0m'

# --- Width-limiting utilities (TD5) ---
source "$(dirname "$0")/statusline-utils.sh"

# DEGRADATION ORDER (C8 — per-line segment drop priority, rightmost = first to drop):
# L1 (project): [YOLO] Phase Plans Effort Model QA Branch Files Commits Diff
#   -> drop: Diff -> Commits -> Files -> QA -> Model -> Effort -> Plans
#   -> OSC 8 link degrades to plain text before any segment drops
# L2 (context): Context: [BAR] PCT% tokens | Tokens: in out | Cache: hit% wr rd
#   -> Shrink bar (20->12->8) -> abbreviate labels (write->wr, read->rd)
# L3 (usage): Session: [BAR] % | Weekly: [BAR] % | Sonnet: [BAR] % | Extra: [BAR] % $/$
#   -> Shrink all bars (20->12->8->3) -> drop Extra -> drop Sonnet
# L4 (model): Model: name | Time: dur (API: dur) | agents | YOLO ver -> ver | CC ver
#   -> Drop update text -> drop agent line -> abbreviate versions

# --- Cached platform info ---
_UID=$(id -u)
_OS=$(uname)
_VER=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null | tr -d '[:space:]')
_CACHE="/tmp/yolo-${_VER:-0}-${_UID}"

# Clean stale caches from previous versions on first run
if ! [ -f "${_CACHE}-ok" ] || ! [ -O "${_CACHE}-ok" ]; then
  rm -f /tmp/yolo-*-"${_UID}"-* /tmp/yolo-sl-cache-"${_UID}" /tmp/yolo-usage-cache-"${_UID}" /tmp/yolo-gh-cache-"${_UID}" /tmp/yolo-team-cache-"${_UID}" 2>/dev/null
  touch "${_CACHE}-ok"
fi

# --- Helpers ---

cache_fresh() {
  local cf="$1" ttl="$2"
  [ ! -f "$cf" ] && return 1
  [ ! -O "$cf" ] && rm -f "$cf" 2>/dev/null && return 1
  local mt
  if [ "$_OS" = "Darwin" ]; then
    mt=$(stat -f %m "$cf" 2>/dev/null || echo 0)
  else
    mt=$(stat -c %Y "$cf" 2>/dev/null || echo 0)
  fi
  [ $((NOW - mt)) -le "$ttl" ]
}

progress_bar() {
  local pct="$1" width="$2"
  local filled=$((pct * width / 100))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  local empty=$((width - filled))
  local color
  if [ "$pct" -ge 80 ]; then color="$R"
  elif [ "$pct" -ge 50 ]; then color="$Y"
  else color="$G"
  fi
  local bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '█')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '░')"
  printf '%b%s%b' "$color" "$bar" "$X"
}

fmt_tok() {
  local v=$1
  if [ "$v" -ge 1000000 ]; then
    local d=$((v / 1000000)) r=$(( (v % 1000000 + 50000) / 100000 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dM" "$d" "$r"
  elif [ "$v" -ge 1000 ]; then
    local d=$((v / 1000)) r=$(( (v % 1000 + 50) / 100 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dK" "$d" "$r"
  else
    printf "%d" "$v"
  fi
}

fmt_cost() {
  local whole="${1%%.*}" frac="${1#*.}"
  local cents="${frac:0:2}"
  cents=$((10#${cents:-0}))
  whole=$((10#${whole:-0}))
  local total_cents=$(( whole * 100 + cents ))
  if [ "$total_cents" -ge 10000 ]; then printf "\$%d" "$whole"
  elif [ "$total_cents" -ge 1000 ]; then printf "\$%d.%d" "$whole" $((cents / 10))
  else printf "\$%d.%02d" "$whole" "$cents"
  fi
}

fmt_dur() {
  local s=$(($1 / 1000))
  if [ "$s" -ge 3600 ]; then
    printf "%dh %dm" $((s / 3600)) $(( (s % 3600) / 60 ))
  elif [ "$s" -ge 60 ]; then
    printf "%dm %ds" $((s / 60)) $((s % 60))
  else
    printf "%ds" "$s"
  fi
}

IFS='|' read -r PCT REM IN_TOK OUT_TOK CACHE_W CACHE_R CTX_SIZE \
               COST DUR_MS API_MS ADDED REMOVED MODEL VER <<< \
  "$(echo "$input" | jq -r '[
    (.context_window.used_percentage // 0 | floor),
    (.context_window.remaining_percentage // 100 | floor),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.output_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.cost.total_cost_usd // 0),
    (.cost.total_duration_ms // 0),
    (.cost.total_api_duration_ms // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.model.display_name // "Claude"),
    (.version // "?")
  ] | join("|")' 2>/dev/null)"

PCT=${PCT:-0}; REM=${REM:-100}; IN_TOK=${IN_TOK:-0}; OUT_TOK=${OUT_TOK:-0}
CACHE_W=${CACHE_W:-0}; CACHE_R=${CACHE_R:-0}; COST=${COST:-0}
DUR_MS=${DUR_MS:-0}; API_MS=${API_MS:-0}; ADDED=${ADDED:-0}; REMOVED=${REMOVED:-0}
MODEL=${MODEL:-Claude}; VER=${VER:-?}

NOW=$(date +%s)

CTX_USED=$((IN_TOK + CACHE_W + CACHE_R))
CTX_USED_FMT=$(fmt_tok "$CTX_USED")
CTX_SIZE_FMT=$(fmt_tok "$CTX_SIZE")
IN_TOK_FMT=$(fmt_tok "$IN_TOK")
OUT_TOK_FMT=$(fmt_tok "$OUT_TOK")
CACHE_W_FMT=$(fmt_tok "$CACHE_W")
CACHE_R_FMT=$(fmt_tok "$CACHE_R")
COST_FMT=$(fmt_cost "$COST")
DUR_FMT=$(fmt_dur "$DUR_MS")
API_DUR_FMT=$(fmt_dur "$API_MS")
TOTAL_INPUT=$((IN_TOK + CACHE_W + CACHE_R))
CACHE_HIT_PCT=0
[ "$TOTAL_INPUT" -gt 0 ] && CACHE_HIT_PCT=$(( CACHE_R * 100 / TOTAL_INPUT ))
if [ "$CACHE_HIT_PCT" -ge 70 ]; then CACHE_COLOR="$G"
elif [ "$CACHE_HIT_PCT" -ge 40 ]; then CACHE_COLOR="$Y"
else CACHE_COLOR="$R"
fi

# --- Fast cache (5s TTL): YOLO state + execution + agents ---
FAST_CF="${_CACHE}-fast"

if ! cache_fresh "$FAST_CF" 5; then
  PH=""; TT=""; EF="balanced"; MP="quality"; BR=""
  PD=0; PT=0; PPD=0; QA="--"; GH_URL=""
  if [ -f ".yolo-planning/state.json" ]; then
    IFS='|' read -r PH TT <<< "$(jq -r '[(.ph // ""), (.tt // "")] | join("|")' .yolo-planning/state.json 2>/dev/null)"
  elif [ -f ".yolo-planning/STATE.md" ]; then
    PH=$(grep -m1 "Current Phase" .yolo-planning/STATE.md 2>/dev/null | grep -oE '[0-9]+' | head -1)
    TT=$(grep -c "^\- \*\*Phase" .yolo-planning/STATE.md 2>/dev/null || echo "")
  fi
  if [ -f ".yolo-planning/config.json" ]; then
    # Auto-migrate: add model_profile if missing
    if ! jq -e '.model_profile' .yolo-planning/config.json >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' .yolo-planning/config.json > "$TMP" && mv "$TMP" .yolo-planning/config.json
    fi
    IFS='|' read -r EF MP <<< "$(jq -r '[(.effort // "balanced"), (.model_profile // "quality")] | join("|")' .yolo-planning/config.json 2>/dev/null)"
  fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BR=$(git branch --show-current 2>/dev/null)
    GH_URL=$(git remote get-url origin 2>/dev/null | sed -e 's|git@github.com:|https://github.com/|' -e 's|\.git$||' -e 's|https://[^@]*@|https://|')
    GIT_STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  fi
  if [ -d ".yolo-planning/phases" ]; then
    PT=$(find .yolo-planning/phases \( -name '*.plan.jsonl' -o -name '*-PLAN.md' \) 2>/dev/null | wc -l | tr -d ' ')
    PD=$(find .yolo-planning/phases \( -name '*.summary.jsonl' -o -name '*-SUMMARY.md' \) 2>/dev/null | wc -l | tr -d ' ')
    if [ -n "$PH" ] && [ "$PH" != "0" ]; then
      PDIR=$(find .yolo-planning/phases -maxdepth 1 -type d -name "$(printf '%02d' "$PH")-*" 2>/dev/null | head -1)
      [ -n "$PDIR" ] && PPD=$(find "$PDIR" \( -name '*.summary.jsonl' -o -name '*-SUMMARY.md' \) 2>/dev/null | wc -l | tr -d ' ')
      [ -n "$PDIR" ] && [ -n "$(find "$PDIR" \( -name 'verification.jsonl' -o -name '*VERIFICATION.md' \) 2>/dev/null | head -1)" ] && QA="pass"
    fi
  fi

  EXEC_STATUS=""; EXEC_WAVE=0; EXEC_TWAVES=0; EXEC_DONE=0; EXEC_TOTAL=0; EXEC_CURRENT=""
  if [ -f ".yolo-planning/.execution-state.json" ]; then
    IFS='|' read -r EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT <<< \
      "$(jq -r '[
        (.status // ""),
        (.wave // 0),
        (.total_waves // 0),
        ([.plans[] | select(.status == "complete")] | length),
        (.plans | length),
        ([.plans[] | select(.status == "running")][0].title // "")
      ] | join("|")' .yolo-planning/.execution-state.json 2>/dev/null)"
  fi

  AGENT_DATA=""
  AGENT_N=$(( $(pgrep -u "$_UID" -cf "claude" 2>/dev/null || echo 1) - 1 ))
  if [ "$AGENT_N" -gt 0 ] 2>/dev/null; then
    AGENT_DATA="${AGENT_N}"
  fi

  printf '%s\n' "${PH:-0}|${TT:-0}|${EF}|${MP}|${BR}|${PD}|${PT}|${PPD}|${QA}|${GH_URL}|${GIT_STAGED:-0}|${GIT_MODIFIED:-0}|${GIT_AHEAD:-0}|${EXEC_STATUS:-}|${EXEC_WAVE:-0}|${EXEC_TWAVES:-0}|${EXEC_DONE:-0}|${EXEC_TOTAL:-0}|${EXEC_CURRENT:-}|${AGENT_DATA:-0}" > "$FAST_CF" 2>/dev/null
fi

if [ -O "$FAST_CF" ]; then
  IFS='|' read -r PH TT EF MP BR PD PT PPD QA GH_URL GIT_STAGED GIT_MODIFIED GIT_AHEAD \
                  EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT \
                  AGENT_N < "$FAST_CF"
fi

AGENT_LINE=""
if [ "${AGENT_N:-0}" -gt 0 ] 2>/dev/null; then
  AGENT_LINE="${C}◆${X} ${AGENT_N} agent$([ "$AGENT_N" -gt 1 ] && echo s) working"
fi

# --- Slow cache (60s TTL): usage limits + update check ---
SLOW_CF="${_CACHE}-slow"

if ! cache_fresh "$SLOW_CF" 60; then
  OAUTH_TOKEN=""
  if [ "$_OS" = "Darwin" ]; then
    CRED_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$CRED_JSON" ]; then
      OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
  fi

  FIVE_PCT=0; FIVE_EPOCH=0; WEEK_PCT=0; WEEK_EPOCH=0; SONNET_PCT=-1
  EXTRA_ENABLED=0; EXTRA_PCT=-1; EXTRA_USED_C=0; EXTRA_LIMIT_C=0; FETCH_OK="noauth"

  if [ -n "$OAUTH_TOKEN" ]; then
    HTTP_CODE=$(curl -s -o /tmp/yolo-usage-body-"${_UID}-$$" -w '%{http_code}' --max-time 3 \
      -H "Authorization: Bearer ${OAUTH_TOKEN}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || HTTP_CODE="000"
    USAGE_RAW=$(cat /tmp/yolo-usage-body-"${_UID}-$$" 2>/dev/null)
    rm -f /tmp/yolo-usage-body-"${_UID}-$$" 2>/dev/null

    if [ -n "$USAGE_RAW" ] && echo "$USAGE_RAW" | jq -e '.five_hour' >/dev/null 2>&1; then
      IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                      EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C <<< \
        "$(echo "$USAGE_RAW" | jq -r '
          def pct: floor;
          def epoch: gsub("\\.[0-9]+"; "") | gsub("Z$"; "+00:00") | split("+")[0] + "Z" | fromdate;
          [
            ((.five_hour.utilization // 0) | pct),
            ((.five_hour.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day.utilization // 0) | pct),
            ((.seven_day.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day_sonnet.utilization // -1) | pct),
            (if .extra_usage.is_enabled == true then 1 else 0 end),
            ((.extra_usage.utilization // -1) | pct),
            ((.extra_usage.used_credits // 0) | floor),
            ((.extra_usage.monthly_limit // 0) | floor)
          ] | join("|")
        ' 2>/dev/null)"
      FETCH_OK="ok"
    else
      if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        FETCH_OK="auth"
      else
        FETCH_OK="fail"
      fi
    fi
  fi

  UPDATE_AVAIL=""
  REMOTE_VER=$(curl -sf --max-time 3 "https://raw.githubusercontent.com/slavpetroff/yolo/main/VERSION" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$REMOTE_VER" ] && [ -n "$_VER" ] && [ "$REMOTE_VER" != "$_VER" ]; then
    NEWEST=$(printf '%s\n%s\n' "$_VER" "$REMOTE_VER" | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)
    [ "$NEWEST" = "$REMOTE_VER" ] && UPDATE_AVAIL="$REMOTE_VER"
  fi

  printf '%s\n' "${FIVE_PCT:-0}|${FIVE_EPOCH:-0}|${WEEK_PCT:-0}|${WEEK_EPOCH:-0}|${SONNET_PCT:--1}|${EXTRA_ENABLED:-0}|${EXTRA_PCT:--1}|${EXTRA_USED_C:-0}|${EXTRA_LIMIT_C:-0}|${FETCH_OK}|${UPDATE_AVAIL:-}" > "$SLOW_CF" 2>/dev/null
fi

if [ -O "$SLOW_CF" ]; then
  IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                  EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C \
                  FETCH_OK UPDATE_AVAIL < "$SLOW_CF"
fi

# --- Cost cache: delta attribution per render ---
COST_CF="${_CACHE}-cost"
PREV_COST=""
[ -O "$COST_CF" ] && PREV_COST=$(cat "$COST_CF" 2>/dev/null)
printf '%s\n' "${COST}" > "$COST_CF" 2>/dev/null

LEDGER_FILE=".yolo-planning/.cost-ledger.json"
if [ -n "$PREV_COST" ] && [ -d ".yolo-planning" ]; then
  _to_cents() {
    local val="$1" w f
    w="${val%%.*}"
    if [ "$w" = "$val" ]; then f="00"; else f="${val#*.}"; f="${f}00"; f="${f:0:2}"; fi
    echo $(( 10#${w:-0} * 100 + 10#$f ))
  }
  PREV_CENTS=$(_to_cents "$PREV_COST")
  CURR_CENTS=$(_to_cents "$COST")
  DELTA_CENTS=$((CURR_CENTS - PREV_CENTS))

  if [ "$DELTA_CENTS" -gt 0 ]; then
    ACTIVE_AGENT="other"
    [ -f ".yolo-planning/.active-agent" ] && ACTIVE_AGENT=$(cat .yolo-planning/.active-agent 2>/dev/null)
    [ -z "$ACTIVE_AGENT" ] && ACTIVE_AGENT="other"

    if [ -f "$LEDGER_FILE" ] && jq empty "$LEDGER_FILE" 2>/dev/null; then
      jq --arg agent "$ACTIVE_AGENT" --argjson delta "$DELTA_CENTS" \
        '.[$agent] = ((.[$agent] // 0) + $delta)' "$LEDGER_FILE" > "${LEDGER_FILE}.tmp" 2>/dev/null \
        && mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE"
    else
      printf '{"%s":%d}\n' "$ACTIVE_AGENT" "$DELTA_CENTS" > "$LEDGER_FILE"
    fi
  fi
fi

# --- Usage rendering ---
USAGE_LINE=""
if [ "$FETCH_OK" = "ok" ]; then
  countdown() {
    local epoch="$1"
    if [ "${epoch:-0}" -gt 0 ] 2>/dev/null; then
      local diff=$((epoch - NOW))
      if [ "$diff" -gt 0 ]; then
        if [ "$diff" -ge 86400 ]; then
          local dd=$((diff / 86400)) hh=$(( (diff % 86400) / 3600 ))
          echo "~${dd}d ${hh}h"
        else
          local hh=$((diff / 3600)) mm=$(( (diff % 3600) / 60 ))
          echo "~${hh}h${mm}m"
        fi
      else
        echo "now"
      fi
    fi
  }

  FIVE_REM=$(countdown "$FIVE_EPOCH")
  WEEK_REM=$(countdown "$WEEK_EPOCH")

  # --- Two-pass L3 construction (TD4) ---
  # Segments: session (always), weekly (always), sonnet (conditional), extra (conditional)
  # Pass 1: Build skeleton with [BAR] placeholders to measure non-bar overhead
  # Pass 2: Compute bar widths from remaining budget, rebuild with real bars

  # Compute extra dollar amounts once (used in skeleton and rebuild)
  EXTRA_USED_D=""; EXTRA_LIMIT_D=""
  if [ "${EXTRA_ENABLED:-0}" = "1" ] && [ "${EXTRA_PCT:--1}" -ge 0 ] 2>/dev/null; then
    EXTRA_USED_D="$((EXTRA_USED_C / 100)).$( printf '%02d' $((EXTRA_USED_C % 100)) )"
    EXTRA_LIMIT_D="$((EXTRA_LIMIT_C / 100)).$( printf '%02d' $((EXTRA_LIMIT_C % 100)) )"
  fi

  # Determine which segments are active
  L3_SEGMENTS=("session" "weekly")
  [ "${SONNET_PCT:--1}" -ge 0 ] 2>/dev/null && L3_SEGMENTS+=("sonnet")
  [ "${EXTRA_ENABLED:-0}" = "1" ] && [ "${EXTRA_PCT:--1}" -ge 0 ] 2>/dev/null && L3_SEGMENTS+=("extra")

  # Build skeleton function (placeholder = "[BAR]" = 5 visible chars)
  _build_l3_skeleton() {
    local segments=("$@")
    local skel="Session: [BAR] ${FIVE_PCT:-0}%"
    [ -n "$FIVE_REM" ] && skel="$skel $FIVE_REM"
    skel="$skel ${D}│${X} Weekly: [BAR] ${WEEK_PCT:-0}%"
    [ -n "$WEEK_REM" ] && skel="$skel $WEEK_REM"
    local has_sonnet=0 has_extra=0
    local s; for s in "${segments[@]}"; do
      [ "$s" = "sonnet" ] && has_sonnet=1
      [ "$s" = "extra" ] && has_extra=1
    done
    if [ "$has_sonnet" = "1" ]; then
      skel="$skel ${D}│${X} Sonnet: [BAR] ${SONNET_PCT}%"
    fi
    if [ "$has_extra" = "1" ]; then
      skel="$skel ${D}│${X} Extra: [BAR] ${EXTRA_PCT}% \$${EXTRA_USED_D}/\$${EXTRA_LIMIT_D}"
    fi
    printf '%s' "$skel"
  }

  # Pass 1+2: Measure skeleton, compute bar width, rebuild with real bars
  _l3_rebuild() {
    local segments=("$@")
    local num_bars=${#segments[@]}
    local skeleton
    skeleton=$(_build_l3_skeleton "${segments[@]}")
    local skel_width
    skel_width=$(visible_width "$skeleton")
    # Add back placeholder widths (each [BAR] = 5 visible chars)
    local available=$(( MAX_WIDTH - skel_width + (num_bars * 5) ))
    local bar_w
    bar_w=$(compute_bar_width "$available" "$num_bars")

    # If bar_w = 0, drop rightmost segment and retry
    if [ "$bar_w" -eq 0 ]; then
      return 1  # Signal caller to drop a segment
    fi

    # Pass 2: Build real line with computed bar widths
    local line="Session: $(progress_bar "${FIVE_PCT:-0}" "$bar_w") ${FIVE_PCT:-0}%"
    [ -n "$FIVE_REM" ] && line="$line $FIVE_REM"
    line="$line ${D}│${X} Weekly: $(progress_bar "${WEEK_PCT:-0}" "$bar_w") ${WEEK_PCT:-0}%"
    [ -n "$WEEK_REM" ] && line="$line $WEEK_REM"
    local has_sonnet=0 has_extra=0
    local s; for s in "${segments[@]}"; do
      [ "$s" = "sonnet" ] && has_sonnet=1
      [ "$s" = "extra" ] && has_extra=1
    done
    if [ "$has_sonnet" = "1" ]; then
      line="$line ${D}│${X} Sonnet: $(progress_bar "${SONNET_PCT}" "$bar_w") ${SONNET_PCT}%"
    fi
    if [ "$has_extra" = "1" ]; then
      line="$line ${D}│${X} Extra: $(progress_bar "${EXTRA_PCT}" "$bar_w") ${EXTRA_PCT}% \$${EXTRA_USED_D}/\$${EXTRA_LIMIT_D}"
    fi
    printf '%s' "$line"
  }

  # Iterative segment dropping: try with all segments, drop rightmost on failure
  USAGE_LINE=""
  _l3_segs=("${L3_SEGMENTS[@]}")
  while [ ${#_l3_segs[@]} -gt 0 ]; do
    USAGE_LINE=$(_l3_rebuild "${_l3_segs[@]}")
    if [ $? -eq 0 ] && [ -n "$USAGE_LINE" ]; then
      break
    fi
    # Drop rightmost segment
    unset '_l3_segs[${#_l3_segs[@]}-1]'
    _l3_segs=("${_l3_segs[@]}")
  done
  # Fallback: if all segments dropped, show minimal
  [ -z "$USAGE_LINE" ] && USAGE_LINE="Session: ${FIVE_PCT:-0}% ${D}│${X} Weekly: ${WEEK_PCT:-0}%"
elif [ "$FETCH_OK" = "auth" ]; then
  USAGE_LINE="${D}Limits: auth expired (run /login)${X}"
elif [ "$FETCH_OK" = "fail" ]; then
  USAGE_LINE="${D}Limits: fetch failed (retry in 60s)${X}"
else
  USAGE_LINE="${D}Limits: N/A (using API key)${X}"
fi

# --- GitHub link (OSC 8 clickable) ---
GH_LINK=""
if [ -n "$GH_URL" ]; then
  GH_NAME=$(basename "$GH_URL")
  if [ -n "$BR" ]; then
    GH_BRANCH_URL="${GH_URL}/tree/${BR}"
    GH_LINK="\033]8;;${GH_BRANCH_URL}\a${GH_NAME}:${BR}\033]8;;\a"
  else
    GH_LINK="\033]8;;${GH_URL}\a${GH_NAME}\033]8;;\a"
  fi
fi

[ "$PCT" -ge 90 ] && BC="$R" || { [ "$PCT" -ge 70 ] && BC="$Y" || BC="$G"; }
FL=$((PCT * 20 / 100)); EM=$((20 - FL))
CTX_BAR=""; [ "$FL" -gt 0 ] && CTX_BAR=$(printf "%${FL}s" | tr ' ' '▓')
[ "$EM" -gt 0 ] && CTX_BAR="${CTX_BAR}$(printf "%${EM}s" | tr ' ' '░')"

if [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
  EXEC_PCT=$((EXEC_DONE * 100 / EXEC_TOTAL))
  L1="${C}${B}[YOLO]${X} Build: $(progress_bar "$EXEC_PCT" 8) ${EXEC_DONE}/${EXEC_TOTAL} plans"
  [ "${EXEC_TWAVES:-0}" -gt 1 ] 2>/dev/null && L1="$L1 ${D}│${X} Wave ${EXEC_WAVE}/${EXEC_TWAVES}"
  [ -n "$EXEC_CURRENT" ] && L1="$L1 ${D}│${X} ${C}◆${X} ${EXEC_CURRENT}"
elif [ "$EXEC_STATUS" = "complete" ]; then
  rm -f .yolo-planning/.execution-state.json "$FAST_CF" 2>/dev/null
  EXEC_STATUS=""
  L1="${C}${B}[YOLO]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  [ "$PT" -gt 0 ] 2>/dev/null && L1="$L1 ${D}│${X} Plans: ${PD}/${PT} (${PPD} this phase)"
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  if [ "$QA" = "pass" ]; then L1="$L1 ${D}│${X} ${G}QA: pass${X}"
  else L1="$L1 ${D}│${X} ${D}QA: --${X}"; fi
elif [ -d ".yolo-planning" ]; then
  L1="${C}${B}[YOLO]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  [ "$PT" -gt 0 ] 2>/dev/null && L1="$L1 ${D}│${X} Plans: ${PD}/${PT} (${PPD} this phase)"
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  if [ "$QA" = "pass" ]; then
    L1="$L1 ${D}│${X} ${G}QA: pass${X}"
  else
    L1="$L1 ${D}│${X} ${D}QA: --${X}"
  fi
else
  L1="${C}${B}[YOLO]${X} ${D}no project${X}"
fi
if [ -n "$BR" ]; then
  if [ -n "$GH_LINK" ]; then
    L1="$L1 ${D}│${X} ${GH_LINK}"
  else
    L1="$L1 ${D}│${X} $BR"
  fi
  GIT_IND=""
  [ "${GIT_STAGED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${G}+${GIT_STAGED}${X}"
  [ "${GIT_MODIFIED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${GIT_IND}${Y}~${GIT_MODIFIED}${X}"
  [ -n "$GIT_IND" ] && L1="$L1 ${D}Files:${X} $GIT_IND"
  [ "${GIT_AHEAD:-0}" -gt 0 ] 2>/dev/null && L1="$L1 ${D}Commits:${X} ${C}↑${GIT_AHEAD}${X}"
  L1="$L1 ${D}Diff:${X} ${G}+${ADDED}${X} ${R}-${REMOVED}${X}"
fi

# --- L1 width budget (IP3) ---
_l1_width=$(visible_width "$L1")
if [ "$_l1_width" -gt "$MAX_WIDTH" ]; then
  # Prepare plain text fallback for GH link (no OSC 8)
  _GH_PLAIN=""
  [ -n "$GH_URL" ] && _GH_PLAIN="$(basename "$GH_URL")${BR:+:$BR}"

  _l1_rebuild() {
    local include_diff="$1" include_commits="$2" include_files="$3" include_qa="$4"
    local line
    if [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
      EXEC_PCT=$((EXEC_DONE * 100 / EXEC_TOTAL))
      line="${C}${B}[YOLO]${X} Build: $(progress_bar "$EXEC_PCT" 8) ${EXEC_DONE}/${EXEC_TOTAL} plans"
      [ "${EXEC_TWAVES:-0}" -gt 1 ] 2>/dev/null && line="$line ${D}│${X} Wave ${EXEC_WAVE}/${EXEC_TWAVES}"
      # EXEC_CURRENT is dropped when rebuilding (it is the longest optional segment)
    elif [ -d ".yolo-planning" ]; then
      line="${C}${B}[YOLO]${X}"
      [ "$TT" -gt 0 ] 2>/dev/null && line="$line Phase ${PH}/${TT}" || line="$line Phase ${PH:-?}"
      [ "$PT" -gt 0 ] 2>/dev/null && line="$line ${D}│${X} Plans: ${PD}/${PT} (${PPD} this phase)"
      line="$line ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
      if [ "$include_qa" = "1" ]; then
        if [ "$QA" = "pass" ]; then line="$line ${D}│${X} ${G}QA: pass${X}"
        else line="$line ${D}│${X} ${D}QA: --${X}"; fi
      fi
    else
      line="${C}${B}[YOLO]${X} ${D}no project${X}"
    fi
    if [ -n "$BR" ]; then
      [ -n "$_GH_PLAIN" ] && line="$line ${D}│${X} $_GH_PLAIN" || line="$line ${D}│${X} $BR"
      if [ "$include_files" = "1" ]; then
        local git_ind=""
        [ "${GIT_STAGED:-0}" -gt 0 ] 2>/dev/null && git_ind="${G}+${GIT_STAGED}${X}"
        [ "${GIT_MODIFIED:-0}" -gt 0 ] 2>/dev/null && git_ind="${git_ind}${Y}~${GIT_MODIFIED}${X}"
        [ -n "$git_ind" ] && line="$line ${D}Files:${X} $git_ind"
      fi
      [ "$include_commits" = "1" ] && [ "${GIT_AHEAD:-0}" -gt 0 ] 2>/dev/null && \
        line="$line ${D}Commits:${X} ${C}↑${GIT_AHEAD}${X}"
      [ "$include_diff" = "1" ] && \
        line="$line ${D}Diff:${X} ${G}+${ADDED}${X} ${R}-${REMOVED}${X}"
    fi
    printf '%s' "$line"
  }
  # Try progressively dropping segments (OSC 8 already replaced by _GH_PLAIN)
  L1=$(_l1_rebuild 1 1 1 1)  # All segments, no OSC 8
  if [ "$(visible_width "$L1")" -gt "$MAX_WIDTH" ]; then
    L1=$(_l1_rebuild 0 1 1 1)  # Drop Diff
  fi
  if [ "$(visible_width "$L1")" -gt "$MAX_WIDTH" ]; then
    L1=$(_l1_rebuild 0 0 1 1)  # Drop Commits
  fi
  if [ "$(visible_width "$L1")" -gt "$MAX_WIDTH" ]; then
    L1=$(_l1_rebuild 0 0 0 1)  # Drop Files
  fi
  if [ "$(visible_width "$L1")" -gt "$MAX_WIDTH" ]; then
    L1=$(_l1_rebuild 0 0 0 0)  # Drop QA
  fi
fi

L2="Context: ${BC}${CTX_BAR}${X} ${BC}${PCT}%${X} ${CTX_USED_FMT}/${CTX_SIZE_FMT}"
L2="$L2 ${D}│${X} Tokens: ${IN_TOK_FMT} in  ${OUT_TOK_FMT} out"
L2="$L2 ${D}│${X} Prompt Cache: ${CACHE_COLOR}${CACHE_HIT_PCT}% hit${X} ${CACHE_W_FMT} write ${CACHE_R_FMT} read"

L3="$USAGE_LINE"
L4="Model: ${D}${MODEL}${X} ${D}│${X} Time: ${DUR_FMT} (API: ${API_DUR_FMT})"
[ -n "$AGENT_LINE" ] && L4="$L4 ${D}│${X} ${AGENT_LINE}"
if [ -n "$UPDATE_AVAIL" ]; then
  L4="$L4 ${D}│${X} ${Y}${B}YOLO ${_VER:-?} → ${UPDATE_AVAIL}${X} ${Y}/yolo:update${X} ${D}│${X} ${D}CC ${VER}${X}"
else
  L4="$L4 ${D}│${X} ${D}YOLO ${_VER:-?}${X} ${D}│${X} ${D}CC ${VER}${X}"
fi

# Safety-net truncation (IP4): truncate_line ensures no line exceeds MAX_WIDTH.
# Lines that already went through budget construction (L1, L2, L3 in plan 01-02)
# will pass the fast path (visible_width check) and skip awk.
# Uses %s (not %b) because truncate_line already interprets \033 to real ESC bytes.
# Using %b would double-interpret backslashes (e.g., ESC\ ST becomes ESC + \t = TAB).
printf '%s\n' "$(truncate_line "$L1")"
printf '%s\n' "$(truncate_line "$L2")"
printf '%s\n' "$(truncate_line "$L3")"
printf '%s\n' "$(truncate_line "$L4")"

exit 0
