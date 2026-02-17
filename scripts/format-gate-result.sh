#!/usr/bin/env bash
# format-gate-result.sh - Format QA gate results into abbreviated JSONL
#
# Transforms raw gate result JSON into abbreviated-key JSONL per
# artifact-formats.md schemas. Used by all three gate scripts for
# consistent output to .qa-gate-results.jsonl.
#
# Usage: format-gate-result.sh <gate-level> [<raw-json>]
#   gate-level: post-task|post-plan|post-phase (required)
#   raw-json: JSON string (optional -- if omitted, reads from stdin)
#
# Output: stdout = single JSONL line with abbreviated keys
# Exit 0 on success, exit 1 on invalid gate level or invalid JSON input.

set -euo pipefail

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "jq is required but not found in PATH" >&2
  exit 1
fi

# --- Argument validation ---
if [ $# -lt 1 ]; then
  echo "Usage: format-gate-result.sh <gate-level> [<raw-json>]" >&2
  exit 1
fi

GATE_LEVEL="$1"

case "$GATE_LEVEL" in
  post-task|post-plan|post-phase) ;;
  *)
    echo "Invalid gate level: $GATE_LEVEL (must be post-task|post-plan|post-phase)" >&2
    exit 1
    ;;
esac

# --- Input handling ---
INPUT="${2:-$(cat)}"

# Validate input is valid JSON
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  echo "Invalid JSON input" >&2
  exit 1
fi

# --- Current timestamp ---
DT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Transform per gate level ---
case "$GATE_LEVEL" in
  post-task)
    echo "$INPUT" | jq -c --arg dt "$DT" '{
      gl: "post-task",
      r: (.result // .r // "WARN"),
      plan: (.plan_id // .plan // "unknown"),
      task: (.task_id // .task // "unknown"),
      tst: (.tests // .tst // {ps:0,fl:0}),
      dur: (.duration_ms // .dur // 0),
      f: (.files_tested // .f // []),
      dt: $dt
    }'
    ;;
  post-plan)
    echo "$INPUT" | jq -c --arg dt "$DT" '{
      gl: "post-plan",
      r: (.result // .r // "WARN"),
      plan: (.plan_id // .plan // "unknown"),
      tc: (.tasks_completed // .tc // 0),
      tt: (.tasks_total // .tt // 0),
      tst: (.tests // .tst // {ps:0,fl:0}),
      dur: (.duration_ms // .dur // 0),
      mh: (.must_have_coverage // .mh // {ps:0,fl:0,tt:0}),
      dt: $dt
    }'
    ;;
  post-phase)
    echo "$INPUT" | jq -c --arg dt "$DT" '{
      gl: "post-phase",
      r: (.result // .r // "WARN"),
      ph: (.phase // .ph // "unknown"),
      plans: (.plan_results // .plans // []),
      tst: (.tests // .tst // {ps:0,fl:0}),
      dur: (.duration_ms // .dur // 0),
      esc: (.escalations // .esc // 0),
      gates: (.gate_check // .gates // {ps:0,fl:0,tt:0}),
      dt: $dt
    }'
    ;;
esac
