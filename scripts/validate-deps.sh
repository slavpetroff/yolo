#!/usr/bin/env bash
set -euo pipefail

# validate-deps.sh — Dependency graph validator for roadmap_plan JSON
#
# Validates the dependency graph in a roadmap plan, checking for circular
# dependencies, missing references, orphan phases, and critical path connectivity.
#
# Usage: validate-deps.sh --roadmap-json <path>
# Output: JSON to stdout: {"valid": true|false, "errors": [], "warnings": []}
# Exit codes: 0 = valid, 1 = invalid or usage error
#
# Expected roadmap_plan JSON schema:
#   {
#     "phases": [
#       {"id": "01", "name": "...", "depends_on": ["02"], "critical": true|false}
#     ]
#   }

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed"}' >&2
  exit 1
fi

# --- Arg parsing ---
ROADMAP_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --roadmap-json)
      ROADMAP_JSON="$2"
      shift 2
      ;;
    *)
      echo "Usage: validate-deps.sh --roadmap-json <path>" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ROADMAP_JSON" ]; then
  echo "Error: --roadmap-json is required" >&2
  exit 1
fi

if [ ! -f "$ROADMAP_JSON" ]; then
  echo "Error: roadmap file not found: $ROADMAP_JSON" >&2
  exit 1
fi

# --- Validate JSON ---
if ! jq -e '.' "$ROADMAP_JSON" >/dev/null 2>&1; then
  jq -n '{"valid":false,"errors":["Roadmap file is not valid JSON"],"warnings":[]}'
  exit 1
fi

# --- Check phases array exists ---
HAS_PHASES=$(jq 'has("phases") and (.phases | type == "array")' "$ROADMAP_JSON")
if [ "$HAS_PHASES" != "true" ]; then
  jq -n '{"valid":false,"errors":["Missing or invalid phases array"],"warnings":[]}'
  exit 1
fi

PHASE_COUNT=$(jq '.phases | length' "$ROADMAP_JSON")
if [ "$PHASE_COUNT" -eq 0 ]; then
  jq -n '{"valid":false,"errors":["Phases array is empty"],"warnings":[]}'
  exit 1
fi

# --- Extract all phase IDs ---
ALL_IDS=$(jq -r '.phases[].id' "$ROADMAP_JSON")

ERRORS=()
WARNINGS=()

# --- Check 1: All referenced dependency IDs exist ---
while IFS= read -r line; do
  if [ -n "$line" ]; then
    PHASE_ID=$(echo "$line" | jq -r '.id')
    DEPS=$(echo "$line" | jq -r '.depends_on // [] | .[]')
    for dep in $DEPS; do
      if ! echo "$ALL_IDS" | grep -qx "$dep"; then
        ERRORS+=("Phase '$PHASE_ID' depends on '$dep' which does not exist in phases array")
      fi
    done
  fi
done < <(jq -c '.phases[]' "$ROADMAP_JSON")

# --- Check 2: No circular dependencies (Kahn's algorithm via jq) ---
TOPO_RESULT=$(jq -r '
  # Only consider edges where both endpoints exist in phases
  [.phases[].id] as $all_ids |
  .phases as $phases |

  # Build in-degree: count valid depends_on entries per phase
  (reduce $phases[] as $p ({};
    ($p.depends_on // []) as $deps |
    reduce ($deps[] | select(. as $d | $all_ids | index($d))) as $d (.;
      .[$p.id] = ((.[$p.id] // 0) + 1)
    )
  )) as $in_degree |

  # Kahn: start with nodes having 0 in-degree
  {
    queue: [$all_ids[] | select(($in_degree[.] // 0) == 0)],
    sorted: [],
    deg: $in_degree
  } |

  # Process queue iteratively
  until(.queue | length == 0;
    .queue[0] as $n |
    {
      queue: .queue[1:],
      sorted: (.sorted + [$n]),
      deg: .deg
    } |
    # Find all phases that list $n in their depends_on
    ([$phases[] | select((.depends_on // []) | index($n)) | .id]) as $neighbors |
    # Decrement in-degree for each neighbor
    reduce $neighbors[] as $nb (.;
      .deg[$nb] = ((.deg[$nb] // 1) - 1) |
      if .deg[$nb] == 0 then .queue += [$nb] else . end
    )
  ) |

  .sorted as $sorted_list |
  if ($sorted_list | length) == ($all_ids | length) then
    "OK"
  else
    "CYCLE:" + ([$all_ids[] | select(. as $id | $sorted_list | index($id) | not)] | join(","))
  end
' "$ROADMAP_JSON" 2>/dev/null || echo "TOPO_ERROR")

if [ "${TOPO_RESULT%%:*}" = "CYCLE" ]; then
  CYCLE_NODES="${TOPO_RESULT#CYCLE:}"
  ERRORS+=("Circular dependency detected involving phases: $CYCLE_NODES")
elif [ "$TOPO_RESULT" = "TOPO_ERROR" ]; then
  ERRORS+=("Failed to perform topological sort on dependency graph")
fi

# --- Check 3: No orphan phases that should have edges ---
while IFS= read -r line; do
  if [ -n "$line" ]; then
    PHASE_ID=$(echo "$line" | jq -r '.id')
    HAS_DEPS=$(echo "$line" | jq '(.depends_on // []) | length > 0')
    # Check if any other phase depends on this one
    IS_DEPENDED_ON=$(jq --arg pid "$PHASE_ID" '[.phases[] | .depends_on // [] | index($pid)] | any(. != null)' "$ROADMAP_JSON")
    if [ "$HAS_DEPS" = "false" ] && [ "$IS_DEPENDED_ON" = "false" ] && [ "$PHASE_COUNT" -gt 1 ]; then
      WARNINGS+=("Phase '$PHASE_ID' is orphaned (no dependencies and nothing depends on it)")
    fi
  fi
done < <(jq -c '.phases[]' "$ROADMAP_JSON")

# --- Check 4: Critical path phases are connected ---
CRITICAL_COUNT=$(jq '[.phases[] | select(.critical == true)] | length' "$ROADMAP_JSON")
if [ "$CRITICAL_COUNT" -gt 1 ]; then
  # Verify critical phases form a connected subgraph (at least via transitive deps)
  CRITICAL_IDS=$(jq -r '[.phases[] | select(.critical == true) | .id] | join(" ")' "$ROADMAP_JSON")
  for cid in $CRITICAL_IDS; do
    HAS_CRITICAL_LINK=$(jq --arg pid "$cid" '
      (.phases[] | select(.id == $pid) | .depends_on // []) as $deps |
      [.phases[] | select(.critical == true) | .id] as $critical_ids |
      # Check if this critical phase depends on another critical phase OR is depended on by one
      ([$deps[] | select(. as $d | $critical_ids | index($d))] | length > 0) or
      ([.phases[] | select(.critical == true) | .depends_on // [] | index($pid)] | any(. != null))
    ' "$ROADMAP_JSON")
    if [ "$HAS_CRITICAL_LINK" = "false" ]; then
      WARNINGS+=("Critical phase '$cid' is not connected to other critical phases in the dependency graph")
    fi
  done
fi

# --- Output result ---
if [ ${#ERRORS[@]} -eq 0 ]; then
  if [ ${#WARNINGS[@]} -eq 0 ]; then
    jq -n '{"valid":true,"errors":[],"warnings":[]}'
  else
    printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '{valid: true, errors: [], warnings: .}'
  fi
  exit 0
else
  ERRORS_JSON=$(printf '%s\n' "${ERRORS[@]}" | jq -R . | jq -s '.')
  if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "$ERRORS_JSON" | jq '{valid: false, errors: ., warnings: []}'
  else
    WARNINGS_JSON=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')
    jq -n --argjson errors "$ERRORS_JSON" --argjson warnings "$WARNINGS_JSON" \
      '{valid: false, errors: $errors, warnings: $warnings}'
  fi
  exit 1
fi
