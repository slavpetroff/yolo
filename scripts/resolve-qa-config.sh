#!/usr/bin/env bash
# resolve-qa-config.sh — Resolve QA gate configuration with fallback
#
# Reads qa_gates from config.json, merges with defaults.json,
# falls back to hardcoded defaults when keys are missing.
#
# Usage: resolve-qa-config.sh <config-path> <defaults-path>
#   config-path:   path to .yolo-planning/config.json
#   defaults-path: path to config/defaults.json
#
# Output: stdout = JSON object with all 5 resolved qa_gates fields
# Exit 0 on success, exit 1 on usage error
# Fail-open: if both files missing or jq fails, output hardcoded defaults

set -euo pipefail

HARDCODED='{"post_task":true,"post_plan":true,"post_phase":true,"timeout_seconds":300,"failure_threshold":"critical"}'

# Argument validation
if [ $# -ne 2 ]; then
  echo "Usage: resolve-qa-config.sh <config-path> <defaults-path>" >&2
  exit 1
fi

CONFIG_PATH="$1"
DEFAULTS_PATH="$2"

# jq dependency check — fail-open with hardcoded defaults
if ! command -v jq &>/dev/null; then
  echo "$HARDCODED"
  exit 0
fi

# Resolve file paths — use /dev/null for missing files
config_file="$CONFIG_PATH"
defaults_file="$DEFAULTS_PATH"

[ -f "$config_file" ] || config_file="/dev/null"
[ -f "$defaults_file" ] || defaults_file="/dev/null"

# Helper: resolve with null-aware merge (jq // treats false as falsy)
# Use explicit null checks so boolean false overrides correctly
resolve_field='def resolve(c; d; fallback):
  if c != null then c elif d != null then d else fallback end;';

# Single jq call: merge config over defaults with hardcoded fallback
result=$(jq -n \
  --slurpfile defaults "$defaults_file" \
  --slurpfile config "$config_file" \
  "${resolve_field}"'
   ($defaults[0].qa_gates // {}) as $d |
   ($config[0].qa_gates // {}) as $c |
   {
     post_task:          resolve($c.post_task; $d.post_task; true),
     post_plan:          resolve($c.post_plan; $d.post_plan; true),
     post_phase:         resolve($c.post_phase; $d.post_phase; true),
     timeout_seconds:    resolve($c.timeout_seconds; $d.timeout_seconds; 300),
     failure_threshold:  resolve($c.failure_threshold; $d.failure_threshold; "critical")
   }' 2>/dev/null) || {
  # If jq fails for any reason, output hardcoded defaults (fail-open)
  echo "$HARDCODED"
  exit 0
}

echo "$result"
