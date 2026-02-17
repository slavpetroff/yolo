#!/usr/bin/env bash
set -euo pipefail

# validate-config.sh — Validate config.json schema including qa_gates
#
# Checks qa_gates field types: booleans, positive numbers, enum strings.
# Designed for session-start.sh integration (warn-only, non-blocking).
#
# Usage: validate-config.sh <config-path> [<defaults-path>]
# Output: JSON {"valid":true,"errors":[]} or {"valid":false,"errors":[...]}
# Exit codes: 0 = valid, 1 = invalid or usage error

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: validate-config.sh <config-path> [<defaults-path>]" >&2
  exit 1
fi

CONFIG_PATH="$1"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Usage: validate-config.sh <config-path> [<defaults-path>]" >&2
  echo "Error: File not found: $CONFIG_PATH" >&2
  exit 1
fi

# --- Validate JSON ---
if ! jq -e '.' "$CONFIG_PATH" >/dev/null 2>&1; then
  printf '%s\n' "Config file is not valid JSON" | jq -R . | jq -s '{"valid":false,"errors":.}'
  exit 1
fi

# --- Check if qa_gates key exists; if not, valid (backward compat) ---
has_qa_gates=$(jq 'has("qa_gates")' "$CONFIG_PATH")
if [ "$has_qa_gates" = "false" ]; then
  jq -n '{"valid":true,"errors":[]}'
  exit 0
fi

# --- Validate qa_gates structure ---
ERRORS=()

# Check qa_gates is object
is_object=$(jq -r '.qa_gates | type' "$CONFIG_PATH")
if [ "$is_object" != "object" ]; then
  ERRORS+=("qa_gates must be an object, got $is_object")
  # Can't validate fields if not an object
  printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '{"valid":false,"errors":.}'
  exit 1
fi

# Check post_task is boolean (if present)
if jq -e '.qa_gates | has("post_task")' "$CONFIG_PATH" >/dev/null 2>&1; then
  pt_type=$(jq -r '.qa_gates.post_task | type' "$CONFIG_PATH")
  if [ "$pt_type" != "boolean" ]; then
    ERRORS+=("qa_gates.post_task must be boolean, got $pt_type")
  fi
fi

# Check post_plan is boolean (if present)
if jq -e '.qa_gates | has("post_plan")' "$CONFIG_PATH" >/dev/null 2>&1; then
  pp_type=$(jq -r '.qa_gates.post_plan | type' "$CONFIG_PATH")
  if [ "$pp_type" != "boolean" ]; then
    ERRORS+=("qa_gates.post_plan must be boolean, got $pp_type")
  fi
fi

# Check post_phase is boolean (if present)
if jq -e '.qa_gates | has("post_phase")' "$CONFIG_PATH" >/dev/null 2>&1; then
  pph_type=$(jq -r '.qa_gates.post_phase | type' "$CONFIG_PATH")
  if [ "$pph_type" != "boolean" ]; then
    ERRORS+=("qa_gates.post_phase must be boolean, got $pph_type")
  fi
fi

# Check timeout_seconds is positive number (if present)
if jq -e '.qa_gates | has("timeout_seconds")' "$CONFIG_PATH" >/dev/null 2>&1; then
  ts_valid=$(jq '.qa_gates.timeout_seconds | (type == "number") and (. > 0)' "$CONFIG_PATH")
  if [ "$ts_valid" != "true" ]; then
    ERRORS+=("qa_gates.timeout_seconds must be a positive number")
  fi
fi

# Check failure_threshold is valid enum (if present)
if jq -e '.qa_gates | has("failure_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
  ft_valid=$(jq '.qa_gates.failure_threshold | (type == "string") and test("^(critical|major|minor)$")' "$CONFIG_PATH")
  if [ "$ft_valid" != "true" ]; then
    ERRORS+=("qa_gates.failure_threshold must be one of: critical, major, minor")
  fi
fi

# --- Output ---
if [ ${#ERRORS[@]} -eq 0 ]; then
  jq -n '{"valid":true,"errors":[]}'
  exit 0
else
  printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '{"valid":false,"errors":.}'
  exit 1
fi
