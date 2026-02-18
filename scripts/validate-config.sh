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

# --- Initialize errors array ---
ERRORS=()

# --- Validate qa_gates section (if present) ---
has_qa_gates=$(jq 'has("qa_gates")' "$CONFIG_PATH")
if [ "$has_qa_gates" = "true" ]; then
  # Check qa_gates is object
  is_object=$(jq -r '.qa_gates | type' "$CONFIG_PATH")
  if [ "$is_object" != "object" ]; then
    ERRORS+=("qa_gates must be an object, got $is_object")
  else
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
  fi
fi

# --- Validate integration_gate section (if present) ---
has_integration_gate=$(jq 'has("integration_gate")' "$CONFIG_PATH")
if [ "$has_integration_gate" = "true" ]; then
  ig_type=$(jq -r '.integration_gate | type' "$CONFIG_PATH")
  if [ "$ig_type" != "object" ]; then
    ERRORS+=("integration_gate must be an object, got $ig_type")
  else
    # Check enabled is boolean (if present)
    if jq -e '.integration_gate | has("enabled")' "$CONFIG_PATH" >/dev/null 2>&1; then
      ig_enabled_type=$(jq -r '.integration_gate.enabled | type' "$CONFIG_PATH")
      if [ "$ig_enabled_type" != "boolean" ]; then
        ERRORS+=("integration_gate.enabled must be boolean, got $ig_enabled_type")
      fi
    fi

    # Check timeout_seconds is number 60-3600 (if present)
    if jq -e '.integration_gate | has("timeout_seconds")' "$CONFIG_PATH" >/dev/null 2>&1; then
      ig_ts_valid=$(jq '.integration_gate.timeout_seconds | (type == "number") and (. >= 60) and (. <= 3600)' "$CONFIG_PATH")
      if [ "$ig_ts_valid" != "true" ]; then
        ERRORS+=("integration_gate.timeout_seconds must be a number between 60 and 3600")
      fi
    fi

    # Check checks is object with boolean values (if present)
    if jq -e '.integration_gate | has("checks")' "$CONFIG_PATH" >/dev/null 2>&1; then
      ig_checks_type=$(jq -r '.integration_gate.checks | type' "$CONFIG_PATH")
      if [ "$ig_checks_type" != "object" ]; then
        ERRORS+=("integration_gate.checks must be an object, got $ig_checks_type")
      else
        ig_checks_valid=$(jq '[.integration_gate.checks | to_entries[] | .value | type == "boolean"] | all' "$CONFIG_PATH")
        if [ "$ig_checks_valid" != "true" ]; then
          ERRORS+=("integration_gate.checks values must all be booleans")
        fi
      fi
    fi

    # Check retry_on_fail is boolean (if present)
    if jq -e '.integration_gate | has("retry_on_fail")' "$CONFIG_PATH" >/dev/null 2>&1; then
      ig_retry_type=$(jq -r '.integration_gate.retry_on_fail | type' "$CONFIG_PATH")
      if [ "$ig_retry_type" != "boolean" ]; then
        ERRORS+=("integration_gate.retry_on_fail must be boolean, got $ig_retry_type")
      fi
    fi
  fi
fi

# --- Validate po.default_rejection (if present) ---
if jq -e '.po | has("default_rejection")' "$CONFIG_PATH" >/dev/null 2>&1; then
  po_dr_valid=$(jq '.po.default_rejection | (type == "string") and test("^(patch|major)$")' "$CONFIG_PATH")
  if [ "$po_dr_valid" != "true" ]; then
    ERRORS+=("po.default_rejection must be one of: patch, major")
  fi
fi

# --- Validate delivery section (if present) ---
has_delivery=$(jq 'has("delivery")' "$CONFIG_PATH")
if [ "$has_delivery" = "true" ]; then
  del_type=$(jq -r '.delivery | type' "$CONFIG_PATH")
  if [ "$del_type" != "object" ]; then
    ERRORS+=("delivery must be an object, got $del_type")
  else
    # Check mode is valid enum (if present)
    if jq -e '.delivery | has("mode")' "$CONFIG_PATH" >/dev/null 2>&1; then
      del_mode_valid=$(jq '.delivery.mode | (type == "string") and test("^(auto|manual)$")' "$CONFIG_PATH")
      if [ "$del_mode_valid" != "true" ]; then
        ERRORS+=("delivery.mode must be one of: auto, manual")
      fi
    fi

    # Check present_to_user is boolean (if present)
    if jq -e '.delivery | has("present_to_user")' "$CONFIG_PATH" >/dev/null 2>&1; then
      del_ptu_type=$(jq -r '.delivery.present_to_user | type' "$CONFIG_PATH")
      if [ "$del_ptu_type" != "boolean" ]; then
        ERRORS+=("delivery.present_to_user must be boolean, got $del_ptu_type")
      fi
    fi
  fi
fi

# --- Validate complexity_routing section (if present) ---
has_complexity_routing=$(jq 'has("complexity_routing")' "$CONFIG_PATH")
if [ "$has_complexity_routing" = "true" ]; then
  # Check complexity_routing is object
  cr_type=$(jq -r '.complexity_routing | type' "$CONFIG_PATH")
  if [ "$cr_type" != "object" ]; then
    ERRORS+=("complexity_routing must be an object, got $cr_type")
  else
    # Check enabled is boolean (if present)
    if jq -e '.complexity_routing | has("enabled")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_enabled_type=$(jq -r '.complexity_routing.enabled | type' "$CONFIG_PATH")
      if [ "$cr_enabled_type" != "boolean" ]; then
        ERRORS+=("complexity_routing.enabled must be boolean, got $cr_enabled_type")
      fi
    fi

    # Check trivial_confidence_threshold is float 0.0-1.0 (if present)
    if jq -e '.complexity_routing | has("trivial_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_trivial_valid=$(jq '.complexity_routing.trivial_confidence_threshold | (type == "number") and (. >= 0.0) and (. <= 1.0)' "$CONFIG_PATH")
      if [ "$cr_trivial_valid" != "true" ]; then
        ERRORS+=("complexity_routing.trivial_confidence_threshold must be a number between 0.0 and 1.0")
      fi
    fi

    # Check medium_confidence_threshold is float 0.0-1.0 (if present)
    if jq -e '.complexity_routing | has("medium_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_medium_valid=$(jq '.complexity_routing.medium_confidence_threshold | (type == "number") and (. >= 0.0) and (. <= 1.0)' "$CONFIG_PATH")
      if [ "$cr_medium_valid" != "true" ]; then
        ERRORS+=("complexity_routing.medium_confidence_threshold must be a number between 0.0 and 1.0")
      fi
    fi

    # Check trivial threshold > medium threshold (if both present)
    if jq -e '.complexity_routing | has("trivial_confidence_threshold") and has("medium_confidence_threshold")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_order_valid=$(jq '.complexity_routing.trivial_confidence_threshold > .complexity_routing.medium_confidence_threshold' "$CONFIG_PATH")
      if [ "$cr_order_valid" != "true" ]; then
        ERRORS+=("complexity_routing.trivial_confidence_threshold must be greater than medium_confidence_threshold")
      fi
    fi

    # Check fallback_path is valid enum (if present)
    if jq -e '.complexity_routing | has("fallback_path")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_fp_valid=$(jq '.complexity_routing.fallback_path | (type == "string") and test("^(trivial|medium|high)$")' "$CONFIG_PATH")
      if [ "$cr_fp_valid" != "true" ]; then
        ERRORS+=("complexity_routing.fallback_path must be one of: trivial, medium, high")
      fi
    fi

    # Check force_analyze_model is valid enum (if present)
    if jq -e '.complexity_routing | has("force_analyze_model")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_fam_valid=$(jq '.complexity_routing.force_analyze_model | (type == "string") and test("^(opus|sonnet|haiku)$")' "$CONFIG_PATH")
      if [ "$cr_fam_valid" != "true" ]; then
        ERRORS+=("complexity_routing.force_analyze_model must be one of: opus, sonnet, haiku")
      fi
    fi

    # Check max_trivial_files is positive integer (if present)
    if jq -e '.complexity_routing | has("max_trivial_files")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_mtf_valid=$(jq '.complexity_routing.max_trivial_files | (type == "number") and (. > 0) and (. == floor)' "$CONFIG_PATH")
      if [ "$cr_mtf_valid" != "true" ]; then
        ERRORS+=("complexity_routing.max_trivial_files must be a positive integer")
      fi
    fi

    # Check max_medium_tasks is positive integer (if present)
    if jq -e '.complexity_routing | has("max_medium_tasks")' "$CONFIG_PATH" >/dev/null 2>&1; then
      cr_mmt_valid=$(jq '.complexity_routing.max_medium_tasks | (type == "number") and (. > 0) and (. == floor)' "$CONFIG_PATH")
      if [ "$cr_mmt_valid" != "true" ]; then
        ERRORS+=("complexity_routing.max_medium_tasks must be a positive integer")
      fi
    fi
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
