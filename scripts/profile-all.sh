#!/bin/bash
# profile-all.sh — Profile all YOLO shell scripts with nanosecond timing
#
# Usage: profile-all.sh [--iterations N] [--output FILE] [--category CATEGORY]
#
# Produces JSONL output: one line per iteration + summary per script.
# Compatible with bash 3.2+ (macOS default).
set -euo pipefail

ITERATIONS=5
OUTPUT=""
CATEGORY_FILTER=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMEOUT_SECS=5

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --output)     OUTPUT="$2"; shift 2 ;;
    --category)   CATEGORY_FILTER="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# --- Nanosecond timing function ---
# macOS date lacks %N; use perl Time::HiRes as primary, date +%s%N as fallback
if perl -MTime::HiRes=time -e 'exit 0' 2>/dev/null; then
  _nano() { perl -MTime::HiRes=time -e 'printf("%.0f\n",time*1e9)'; }
elif [[ "$(date +%s%N 2>/dev/null)" != *N* ]]; then
  _nano() { date +%s%N; }
else
  echo "ERROR: No nanosecond timing available (need perl Time::HiRes or GNU date)" >&2
  exit 1
fi

# --- Temp files for stdin mocking and iteration data ---
TMPDIR_PROFILE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROFILE"' EXIT

# --- Category lookup (bash 3.2 compatible, no associative arrays) ---
_category() {
  case "$1" in
    security-filter.sh|file-guard.sh|department-guard.sh) echo hook ;;
    validate-commit.sh|validate-summary.sh|validate-frontmatter.sh) echo hook ;;
    validate-send-message.sh|validate-dept-spawn.sh) echo hook ;;
    skill-hook-dispatch.sh|task-verify.sh|state-updater.sh) echo hook ;;
    prompt-preflight.sh|notification-log.sh|qa-gate.sh) echo hook ;;
    agent-start.sh|agent-stop.sh) echo hook ;;
    session-start.sh|session-stop.sh) echo hook ;;
    map-staleness.sh|post-compact.sh|compaction-instructions.sh) echo hook ;;
    hook-wrapper.sh) echo hook ;;
    compile-context.sh|phase-detect.sh|resolve-agent-model.sh) echo utility ;;
    resolve-departments.sh|suggest-next.sh|yolo-statusline.sh) echo utility ;;
    detect-stack.sh|infer-project-context.sh|infer-gsd-summary.sh) echo utility ;;
    generate-gsd-index.sh|bump-version.sh|cache-nuke.sh) echo utility ;;
    install-hooks.sh|verify-go.sh|pre-push-hook.sh) echo utility ;;
    bootstrap-*.sh) echo bootstrap ;;
    *) echo utility ;;
  esac
}

# --- Args lookup ---
_args() {
  case "$1" in
    compile-context.sh)      echo "01 lead" ;;
    resolve-agent-model.sh)  echo "lead .yolo-planning/config.json config/model-profiles.json" ;;
    hook-wrapper.sh)         echo "nonexistent.sh" ;;
    *)                       echo "" ;;
  esac
}

# --- Mock stdin JSON lookup ---
PRETOOLUSE_JSON='{"tool_name":"Write","tool_input":{"file_path":"test.txt"}}'
POSTTOOLUSE_JSON='{"tool_name":"Write","tool_input":{"file_path":".yolo-planning/test.txt"}}'
SENDMESSAGE_JSON='{"tool_name":"SendMessage","tool_input":{"to":"test","schema":"test"}}'
PROMPT_JSON='{"prompt":"test"}'
NOTIFICATION_JSON='{"notification":{"type":"test"}}'
AGENT_JSON='{"agent_name":"yolo-dev"}'

_stdin() {
  case "$1" in
    security-filter.sh|file-guard.sh|department-guard.sh) echo "$PRETOOLUSE_JSON" ;;
    validate-summary.sh|validate-frontmatter.sh|validate-commit.sh) echo "$POSTTOOLUSE_JSON" ;;
    state-updater.sh|skill-hook-dispatch.sh|task-verify.sh) echo "$POSTTOOLUSE_JSON" ;;
    validate-send-message.sh) echo "$SENDMESSAGE_JSON" ;;
    validate-dept-spawn.sh)   echo "$AGENT_JSON" ;;
    prompt-preflight.sh)      echo "$PROMPT_JSON" ;;
    notification-log.sh|qa-gate.sh) echo "$NOTIFICATION_JSON" ;;
    agent-start.sh|agent-stop.sh)   echo "$AGENT_JSON" ;;
    session-start.sh|session-stop.sh) echo "" ;;
    map-staleness.sh|post-compact.sh|compaction-instructions.sh) echo "" ;;
    *) echo "" ;;
  esac
}

# --- Output helper ---
_emit() {
  if [[ -n "$OUTPUT" ]]; then
    echo "$1" >> "$OUTPUT"
  else
    echo "$1"
  fi
}

# --- Collect scripts ---
ALL_SCRIPTS=""
for s in "$SCRIPT_DIR"/*.sh; do
  sname="$(basename "$s")"
  [[ "$sname" == "profile-all.sh" ]] && continue
  ALL_SCRIPTS="$ALL_SCRIPTS $s"
done
for s in "$SCRIPT_DIR"/bootstrap/*.sh; do
  [[ -f "$s" ]] && ALL_SCRIPTS="$ALL_SCRIPTS $s"
done

# --- Environment for safe execution ---
export SESSION_START_SKIP_UPDATE=1

# --- Main profiling loop ---
for script_path in $ALL_SCRIPTS; do
  script_name="$(basename "$script_path")"
  category="$(_category "$script_name")"

  # Apply category filter
  if [[ -n "$CATEGORY_FILTER" && "$category" != "$CATEGORY_FILTER" ]]; then
    continue
  fi

  # Get args and stdin for this script
  args="$(_args "$script_name")"
  stdin_data="$(_stdin "$script_name")"

  # Write stdin data to temp file if needed
  stdin_file=""
  if [[ -n "$stdin_data" ]]; then
    stdin_file="$TMPDIR_PROFILE/stdin_${script_name}"
    printf '%s\n' "$stdin_data" > "$stdin_file"
  fi

  # Iteration data file
  iter_file="$TMPDIR_PROFILE/iter_${script_name}"
  : > "$iter_file"

  for i in $(seq 1 "$ITERATIONS"); do
    start_ns=$(_nano)

    # Run with timeout using perl (macOS lacks timeout command)
    # Perl handles fork, stdin redirect, and alarm-based timeout
    set +e
    perl -e '
      use POSIX ":sys_wait_h";
      my $timeout = $ARGV[0];
      my $stdin_f = $ARGV[1];
      my $spath   = $ARGV[2];
      my $sargs   = $ARGV[3];
      my $pid = fork();
      if (!defined $pid) { exit 127 }
      if ($pid == 0) {
        if ($stdin_f ne "") {
          open(STDIN, "<", $stdin_f) or die;
        } else {
          open(STDIN, "<", "/dev/null") or die;
        }
        open(STDOUT, ">", "/dev/null");
        open(STDERR, ">", "/dev/null");
        my @cmd = ("bash", $spath);
        if ($sargs ne "") { push @cmd, split(/\s+/, $sargs) }
        exec @cmd;
        exit 127;
      }
      my $elapsed = 0;
      my $step = 0.005;
      while ($elapsed < $timeout) {
        my $w = waitpid($pid, WNOHANG);
        if ($w > 0) { exit($? >> 8) }
        select(undef, undef, undef, $step);
        $elapsed += $step;
      }
      kill("TERM", $pid);
      waitpid($pid, 0);
      exit 124;
    ' "$TIMEOUT_SECS" "${stdin_file:-}" "$script_path" "$args" 2>/dev/null
    exit_code=$?
    set -e

    end_ns=$(_nano)
    duration_ms=$(awk "BEGIN { printf \"%.3f\", ($end_ns - $start_ns) / 1000000 }")

    echo "$duration_ms" >> "$iter_file"

    _emit "{\"script\":\"$script_name\",\"iteration\":$i,\"ms\":$duration_ms,\"exit_code\":$exit_code,\"category\":\"$category\"}"
  done

  # Compute summary statistics
  summary=$(awk '
    BEGIN { min=999999; max=0; sum=0; n=0 }
    {
      v=$1; n++; sum+=v; vals[n]=v
      if (v < min) min=v
      if (v > max) max=v
    }
    END {
      mean=sum/n
      sumsq=0
      for (i=1; i<=n; i++) sumsq+=(vals[i]-mean)^2
      stddev=sqrt(sumsq/n)
      printf "{\"script\":\"%s\",\"mean_ms\":%.3f,\"min_ms\":%.3f,\"max_ms\":%.3f,\"stddev_ms\":%.3f,\"category\":\"%s\",\"type\":\"summary\"}", script, mean, min, max, stddev, category
    }
  ' script="$script_name" category="$category" "$iter_file")

  _emit "$summary"
done
