#!/usr/bin/env bats
# yolo-statusline.bats — Unit tests for scripts/yolo-statusline.sh
# Status line rendering: 4-line dashboard

setup() {
  load '../test_helper/common'
  load '../test_helper/fixtures'
  load '../test_helper/mock_stdin'
  mk_test_workdir
  SUT="$SCRIPTS_DIR/yolo-statusline.sh"

  # Clean temp caches to force fresh computation
  rm -f /tmp/yolo-*-"$(id -u)"* 2>/dev/null

  # Stub curl to prevent network calls
  mkdir -p "$TEST_WORKDIR/bin"
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/curl"
  chmod +x "$TEST_WORKDIR/bin/curl"
  # Stub security to prevent keychain access
  printf '#!/bin/bash\nexit 1\n' > "$TEST_WORKDIR/bin/security"
  chmod +x "$TEST_WORKDIR/bin/security"
  # Stub pgrep to return 0 agents
  printf '#!/bin/bash\necho 1\n' > "$TEST_WORKDIR/bin/pgrep"
  chmod +x "$TEST_WORKDIR/bin/pgrep"
}

teardown() {
  rm -f /tmp/yolo-*-"$(id -u)"* 2>/dev/null
}

# Minimal status JSON for input
STATUS_INPUT='{"context_window":{"used_percentage":45,"remaining_percentage":55,"current_usage":{"input_tokens":50000,"output_tokens":10000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":30000},"context_window_size":200000},"cost":{"total_cost_usd":0.50,"total_duration_ms":120000,"total_api_duration_ms":90000,"total_lines_added":100,"total_lines_removed":20},"model":{"display_name":"Claude Sonnet"},"version":"1.2.3"}'

# Helper: run statusline from TEST_WORKDIR
run_statusline() {
  local input="${1:-$STATUS_INPUT}"
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$input' | bash '$SUT'"
}

# --- 1. Always exits 0 ---

@test "exits 0 with valid input" {
  run_statusline
  assert_success
}

# --- 2. Shows [YOLO] header ---

@test "output contains [YOLO] header" {
  run_statusline
  assert_success
  assert_output --partial "[YOLO]"
}

# --- 3. Shows context percentage ---

@test "output includes context usage percentage" {
  run_statusline
  assert_success
  assert_output --partial "45%"
}

# --- 4. Shows model name ---

@test "output includes model display name" {
  run_statusline
  assert_success
  assert_output --partial "Claude Sonnet"
}

# --- 5. Shows token info ---

@test "output includes token counts" {
  run_statusline
  assert_success
  assert_output --partial "in"
  assert_output --partial "out"
}

# --- 6. Shows no project when .yolo-planning missing ---

@test "shows 'no project' when .yolo-planning does not exist" {
  run_statusline
  assert_success
  assert_output --partial "no project"
}

# --- 7. Shows phase info with .yolo-planning ---

@test "shows phase info when state.json exists" {
  mk_planning_dir
  mk_state_json 2 5 "executing"
  run_statusline
  assert_success
  assert_output --partial "Phase"
}

# --- 8. Handles empty input gracefully ---

@test "exits 0 with minimal empty JSON input" {
  run_statusline '{}'
  assert_success
  assert_output --partial "[YOLO]"
}

# ============================================================
# RED PHASE — Tests 9-31 for plan 01-statusline-resilience
# These tests MUST FAIL until statusline-utils.sh is created
# and yolo-statusline.sh is updated to source it.
# ============================================================

# Helper: source statusline-utils.sh in a subshell and call a function
# Usage: run_util <function> [args...]
_run_util() {
  local fn="$1"; shift
  run bash -c "source '$SCRIPTS_DIR/statusline-utils.sh' && $fn $(printf "'%s' " "$@")"
}

# Helper: measure visible width of the Nth line of output (1-based)
# Usage: _measure_line_width <output_var> <line_number>
# bats $output already contains raw ESC bytes; use printf '%s' not '%b'
_measure_line_width() {
  local text="$1" linenum="$2"
  # Extract line N — $output has actual ESC bytes, use printf '%s'
  local raw_line
  raw_line=$(printf '%s' "$text" | sed -n "${linenum}p")
  # Strip OSC 8 hyperlinks using sourceble visible_width from the utils
  # Fallback: use awk to count non-escape chars if utils not sourced
  local ESC=$'\033'
  local no_osc8
  no_osc8=$(printf '%s' "$raw_line" | sed -E "s/${ESC}\]8;[^${ESC}]*${ESC}\\\\([^${ESC}]*)${ESC}\]8;;${ESC}\\\\/\1/g")
  # Strip all CSI sequences
  local visible
  visible=$(printf '%s' "$no_osc8" | sed -E "s/${ESC}\[[0-9;]*[a-zA-Z]//g")
  printf '%s' "$visible" | wc -m | tr -d ' '
}

# -----------------------------------------------------------
# Category 1: Direct function tests (T9-T23)
# Source statusline-utils.sh directly and test each function.
# All will fail with "No such file or directory" until T1 is done.
# -----------------------------------------------------------

# --- T9: visible_width — plain text ---

@test "T9: visible_width returns correct count for plain text" {
  _run_util visible_width "hello world"
  assert_success
  assert_output "11"
}

# --- T10: visible_width — ANSI SGR codes stripped ---

@test "T10: visible_width strips ANSI SGR codes from colored text" {
  local colored
  colored=$'\033[31mred text\033[0m'
  _run_util visible_width "$colored"
  assert_success
  assert_output "8"
}

# --- T11: visible_width — OSC 8 hyperlinks stripped ---

@test "T11: visible_width strips OSC 8 hyperlinks, counts visible text only" {
  # OSC 8 hyperlink: ESC]8;;URL ST visible_text ESC]8;; ST
  # "Link Text" = 9 visible chars
  local ESC=$'\033'
  local ST="${ESC}\\"
  local hyperlink="${ESC}]8;;https://example.com${ST}Link Text${ESC}]8;;${ST}"
  _run_util visible_width "$hyperlink"
  assert_success
  assert_output "9"
}

# --- T12: visible_width — mixed ANSI + OSC 8 ---

@test "T12: visible_width handles mixed ANSI colors and OSC 8 hyperlinks" {
  # Bold cyan "[YOLO]" (6 visible) + " " (1) + OSC 8 "repo:main" (9 visible) = 16
  local ESC=$'\033'
  local ST="${ESC}\\"
  local mixed="${ESC}[1m${ESC}[36m[YOLO]${ESC}[0m ${ESC}]8;;https://github.com/repo${ST}repo:main${ESC}]8;;${ST}"
  _run_util visible_width "$mixed"
  assert_success
  assert_output "16"
}

# --- T13: visible_width — non-m CSI sequences (erase-line) ---

@test "T13: visible_width strips non-m CSI sequences like erase-line ESC[K" {
  # "text" + ESC[K (erase line) = 4 visible chars
  local with_erase
  with_erase=$'text\033[K'
  _run_util visible_width "$with_erase"
  assert_success
  assert_output "4"
}

# --- T14: strip_osc8_links — replaces hyperlink with visible text ---

@test "T14: strip_osc8_links replaces OSC 8 hyperlink with visible text" {
  local ESC=$'\033'
  local ST="${ESC}\\"
  local hyperlink="${ESC}]8;;https://github.com/foo${ST}foo${ESC}]8;;${ST}"
  _run_util strip_osc8_links "$hyperlink"
  assert_success
  assert_output "foo"
}

# --- T15: strip_ansi — removes all escape sequences ---

@test "T15: strip_ansi removes all escape sequences leaving plain text" {
  local ESC=$'\033'
  local ST="${ESC}\\"
  # Dim + bold + OSC 8 + CSI reset
  local dirty="${ESC}[2m${ESC}[1mHello${ESC}[0m ${ESC}]8;;https://x.com${ST}World${ESC}]8;;${ST}"
  _run_util strip_ansi "$dirty"
  assert_success
  assert_output "Hello World"
}

# --- T16: truncate_line — string under MAX_WIDTH returned unchanged ---

@test "T16: truncate_line returns string unchanged when under MAX_WIDTH" {
  local short="short string"
  _run_util truncate_line "$short"
  assert_success
  assert_output "short string"
}

# --- T17: truncate_line — truncates long plain text to MAX_WIDTH ---

@test "T17: truncate_line truncates long plain text to MAX_WIDTH (120) chars" {
  # Build a 130-char plain string (no ANSI)
  local long_str
  long_str=$(printf '%0.s-' {1..130})
  run bash -c "source '$SCRIPTS_DIR/statusline-utils.sh' && result=\$(truncate_line '$long_str') && printf '%s' \"\$result\" | sed -E \"s/\$'\\\\033'\[[0-9;]*[a-zA-Z]//g\" | wc -m | tr -d ' '"
  assert_success
  assert_output "120"
}

# --- T18: truncate_line — appends reset code when truncating colored text ---

@test "T18: truncate_line appends ANSI reset when truncating colored text" {
  # 130 chars of "X" wrapped in red color
  local ESC=$'\033'
  local long_colored
  long_colored="${ESC}[31m$(printf '%0.sX' {1..130})${ESC}[0m"
  run bash -c "source '$SCRIPTS_DIR/statusline-utils.sh' && truncate_line '$long_colored'"
  assert_success
  # Output must end with ESC[0m (reset) since it was truncated
  [[ "$output" == *$'\033[0m' ]]
}

# --- T19: truncate_line — empty input returns empty output ---

@test "T19: truncate_line returns empty string for empty input" {
  run bash -c "source '$SCRIPTS_DIR/statusline-utils.sh' && truncate_line ''"
  assert_success
  assert_output ""
}

# --- T20: truncate_line — respects custom max_width second argument ---

@test "T20: truncate_line respects custom max_width passed as second argument" {
  # 50-char string, custom limit of 20
  local long_str
  long_str=$(printf '%0.sA' {1..50})
  run bash -c "source '$SCRIPTS_DIR/statusline-utils.sh' && result=\$(truncate_line '$long_str' 20) && printf '%s' \"\$result\" | sed -E \"s/\$'\\\\033'\[[0-9;]*[a-zA-Z]//g\" | wc -m | tr -d ' '"
  assert_success
  assert_output "20"
}

# --- T21: compute_bar_width — large budget clamped to MAX_BAR (20) ---

@test "T21: compute_bar_width returns 20 (MAX_BAR) for large budget" {
  # 100 available / 2 bars = 50 per bar; clamped to MAX_BAR=20
  _run_util compute_bar_width 100 2
  assert_success
  assert_output "20"
}

# --- T22: compute_bar_width — tight budget returns MIN_BAR (3) ---

@test "T22: compute_bar_width returns 3 (MIN_BAR) for tight budget" {
  # 12 available / 4 bars = 3 per bar; exactly MIN_BAR=3
  _run_util compute_bar_width 12 4
  assert_success
  assert_output "3"
}

# --- T23: compute_bar_width — insufficient budget returns 0 (drop signal) ---

@test "T23: compute_bar_width returns 0 (drop signal) when budget too tight" {
  # 8 available / 4 bars = 2 per bar; less than MIN_BAR=3 -> drop signal
  _run_util compute_bar_width 8 4
  assert_success
  assert_output "0"
}

# -----------------------------------------------------------
# Category 2: L3 and L1 integration tests (T24-T27)
# These tests run the full statusline script and measure
# visible width of output lines. They will fail until:
# - statusline-utils.sh is sourced from yolo-statusline.sh
# - truncate_line is applied to L1-L4 output
# -----------------------------------------------------------

# Slow cache content with all 4 usage segments active
# Format: FIVE_PCT|FIVE_EPOCH|WEEK_PCT|WEEK_EPOCH|SONNET_PCT|EXTRA_ENABLED|EXTRA_PCT|EXTRA_USED_C|EXTRA_LIMIT_C|FETCH_OK|UPDATE_AVAIL
# Also creates the -ok sentinel to prevent stale-cache cleanup from wiping our seeds.
_mk_slow_cache_all_segments() {
  local ver
  ver=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')
  local prefix="/tmp/yolo-${ver:-0}-$(id -u)"
  local future_epoch=$(( $(date +%s) + 3600 ))
  # Create ok sentinel so the script doesn't wipe our seeded caches
  touch "${prefix}-ok"
  # 75% session, 45% weekly, 60% sonnet, extra enabled at 30% ($30/$100)
  printf '%s\n' "75|${future_epoch}|45|${future_epoch}|60|1|30|3000|10000|ok|" > "${prefix}-slow"
}

_mk_slow_cache_no_update() {
  local ver
  ver=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')
  local prefix="/tmp/yolo-${ver:-0}-$(id -u)"
  touch "${prefix}-ok"
  printf '%s\n' "0|0|0|0|-1|0|-1|0|0|noauth|" > "${prefix}-slow"
}

_mk_slow_cache_with_update() {
  local update_ver="${1:-9.9.9}"
  local ver
  ver=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null | tr -d '[:space:]')
  local prefix="/tmp/yolo-${ver:-0}-$(id -u)"
  touch "${prefix}-ok"
  printf '%s\n' "0|0|0|0|-1|0|-1|0|0|noauth|${update_ver}" > "${prefix}-slow"
}

# --- T24: L3 fits within 120 with all 4 usage segments ---

@test "T24: L3 fits within 120 visible chars with all 4 usage segments" {
  _mk_slow_cache_all_segments
  run_statusline
  assert_success
  # Extract L3 (line 3) and measure its visible width
  local width
  width=$(_measure_line_width "$output" 3)
  [ "$width" -le 120 ]
}

# --- T25: L3 fits within 80 with YOLO_MAX_WIDTH=80 ---

@test "T25: L3 fits within 80 visible chars when YOLO_MAX_WIDTH=80" {
  _mk_slow_cache_all_segments
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' YOLO_MAX_WIDTH=80 printf '%s' '$STATUS_INPUT' | bash '$SUT'"
  assert_success
  local width
  width=$(_measure_line_width "$output" 3)
  [ "$width" -le 80 ]
}

# --- T26: L1 fits within 120 with long branch name and OSC 8 link ---

@test "T26: L1 fits within 120 visible chars with long branch name and OSC 8 link" {
  mk_planning_dir
  mk_state_json 2 5 "executing"
  # Set up a git repo with a long branch name
  mk_git_repo
  cd "$TEST_WORKDIR"
  git checkout -q -b "feature/very-long-branch-name-that-goes-on-forever-and-ever-and-ever"
  git remote add origin "https://github.com/testorg/my-super-long-repository-name" 2>/dev/null || true
  _mk_slow_cache_no_update
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$STATUS_INPUT' | bash '$SUT'"
  assert_success
  local width
  width=$(_measure_line_width "$output" 1)
  [ "$width" -le 120 ]
}

# --- T27: L1 in execution mode fits within 120 with long plan name ---

@test "T27: L1 in execution mode fits within 120 with long current plan name" {
  mk_planning_dir
  # Create execution state with a running plan with a very long title
  local long_title="Implementing the comprehensive authentication and authorization module with OAuth2 and JWT"
  jq -n --arg title "$long_title" '{
    status: "running",
    wave: 1,
    total_waves: 3,
    plans: [
      {title: $title, status: "running"},
      {title: "plan2", status: "pending"}
    ]
  }' > "$TEST_WORKDIR/.yolo-planning/.execution-state.json"
  _mk_slow_cache_no_update
  run_statusline
  assert_success
  local width
  width=$(_measure_line_width "$output" 1)
  [ "$width" -le 120 ]
}

# -----------------------------------------------------------
# Category 3: L2, L4, and comprehensive tests (T28-T31)
# -----------------------------------------------------------

# --- T28: L2 fits within 120 with large token counts ---

@test "T28: L2 fits within 120 visible chars with large token counts" {
  # Input with very large token counts (near max context window)
  local large_input
  large_input='{"context_window":{"used_percentage":92,"remaining_percentage":8,"current_usage":{"input_tokens":1500000,"output_tokens":250000,"cache_creation_input_tokens":100000,"cache_read_input_tokens":800000},"context_window_size":2000000},"cost":{"total_cost_usd":99.50,"total_duration_ms":7200000,"total_api_duration_ms":5400000,"total_lines_added":9999,"total_lines_removed":8888},"model":{"display_name":"Claude Opus"},"version":"1.2.3"}'
  _mk_slow_cache_no_update
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$large_input' | bash '$SUT'"
  assert_success
  local width
  width=$(_measure_line_width "$output" 2)
  [ "$width" -le 120 ]
}

# --- T29: L4 fits within 120 with update notification and long model name ---

@test "T29: L4 fits within 120 visible chars with update notification and long model name" {
  _mk_slow_cache_with_update "9.9.9"
  # Use a long model name + long duration to push L4 well past 120 chars
  # Without truncation: "Model: Claude Opus 4 Turbo Extended Context Max Tokens │ Time: 2h 0m (API: 1h 30m) │ YOLO 0.2.2 → 9.9.9 /yolo:update │ CC 1.2.3" = 127+ chars
  local long_input
  long_input='{"context_window":{"used_percentage":45},"cost":{"total_cost_usd":0.50,"total_duration_ms":7200000,"total_api_duration_ms":5400000},"model":{"display_name":"Claude Opus 4 Turbo Extended Context Max Tokens"},"version":"1.2.3"}'
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$long_input' | bash '$SUT'"
  assert_success
  local width
  width=$(_measure_line_width "$output" 4)
  [ "$width" -le 120 ]
}

# --- T30: L4 fits within 70 with YOLO_MAX_WIDTH=70 ---

@test "T30: L4 fits within 70 visible chars when YOLO_MAX_WIDTH=70" {
  _mk_slow_cache_with_update "9.9.9"
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' YOLO_MAX_WIDTH=70 printf '%s' '$STATUS_INPUT' | bash '$SUT'"
  assert_success
  local width
  width=$(_measure_line_width "$output" 4)
  [ "$width" -le 70 ]
}

# --- T31: All 4 lines fit within MAX_WIDTH simultaneously ---

@test "T31: All 4 output lines fit within 120 visible chars simultaneously" {
  _mk_slow_cache_all_segments
  mk_planning_dir
  mk_state_json 3 8 "executing"
  mk_git_repo
  cd "$TEST_WORKDIR"
  git checkout -q -b "feature/long-branch-name-for-width-test"
  git remote add origin "https://github.com/testorg/testproject" 2>/dev/null || true
  local wide_input
  wide_input='{"context_window":{"used_percentage":75,"remaining_percentage":25,"current_usage":{"input_tokens":900000,"output_tokens":150000,"cache_creation_input_tokens":50000,"cache_read_input_tokens":500000},"context_window_size":1600000},"cost":{"total_cost_usd":45.00,"total_duration_ms":3600000,"total_api_duration_ms":2700000,"total_lines_added":5000,"total_lines_removed":3000},"model":{"display_name":"Claude Opus 4"},"version":"1.2.3"}'
  run bash -c "cd '$TEST_WORKDIR' && PATH='$TEST_WORKDIR/bin:$PATH' printf '%s' '$wide_input' | bash '$SUT'"
  assert_success
  local w1 w2 w3 w4
  w1=$(_measure_line_width "$output" 1)
  w2=$(_measure_line_width "$output" 2)
  w3=$(_measure_line_width "$output" 3)
  w4=$(_measure_line_width "$output" 4)
  [ "$w1" -le 120 ]
  [ "$w2" -le 120 ]
  [ "$w3" -le 120 ]
  [ "$w4" -le 120 ]
}
