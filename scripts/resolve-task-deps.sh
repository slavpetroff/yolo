#!/usr/bin/env bash
set -euo pipefail

# resolve-task-deps.sh -- Resolve task execution order from plan.jsonl
# Reads td (intra-plan) and d (cross-plan) dependencies
# Outputs JSON array of task execution groups
# Usage: resolve-task-deps.sh --plan path/to/plan.jsonl [--all-plans dir/]
# Output: JSON on stdout
# Exit: 0 on success, 1 on circular dependency

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

# --- Arg parsing ---
PLAN_FILE=""
ALL_PLANS_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)
      PLAN_FILE="$2"
      shift 2
      ;;
    --all-plans)
      ALL_PLANS_DIR="$2"
      shift 2
      ;;
    *)
      echo "Usage: resolve-task-deps.sh --plan path/to/plan.jsonl [--all-plans dir/]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PLAN_FILE" ]; then
  echo "Usage: resolve-task-deps.sh --plan path/to/plan.jsonl [--all-plans dir/]" >&2
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

# --- Read plan.jsonl ---
# Line 1 is header, lines 2+ are tasks
task_count=$(tail -n +2 "$PLAN_FILE" | wc -l | tr -d ' ')

if [ "$task_count" -eq 0 ]; then
  echo "[]"
  exit 0
fi

# Build task graph as JSON: [{id, td}]
task_graph=$(tail -n +2 "$PLAN_FILE" | jq -s '[.[] | {id: .id, td: (.td // [])}]')

# --- Topological sort (Kahn's algorithm) ---
# Use bash loop calling jq for each iteration

# State: JSON object {in_degree: {id: N}, remaining: [ids], groups: []}
state=$(echo "$task_graph" | jq '
  # deps map: task_id -> [dependency task ids]
  (reduce .[] as $t ({}; . + {($t.id): $t.td})) as $deps |
  # all task IDs
  [.[] | .id] as $all_ids |
  # in-degree: count how many valid deps each task has
  (reduce $all_ids[] as $id (
    {};
    . + {($id): ([$deps[$id][] | select(. as $d | $all_ids | index($d))] | length)}
  )) as $in_degree |
  {
    deps: $deps,
    in_degree: $in_degree,
    remaining: $all_ids,
    groups: []
  }
')

while true; do
  remaining_count=$(echo "$state" | jq '.remaining | length')
  if [ "$remaining_count" -eq 0 ]; then
    break
  fi

  # Find tasks with in_degree 0 among remaining
  state=$(echo "$state" | jq '
    . as $s |
    # Find ready tasks (in_degree == 0 and in remaining)
    [.remaining[] | select(. as $id | $s.in_degree[$id] == 0)] as $ready |

    if ($ready | length) == 0 then
      # Circular dependency
      .error = ("Circular dependency detected among tasks: " + (.remaining | join(", ")))
    else
      # Add group
      .groups += [{group: ((.groups | length) + 1), tasks: $ready}] |
      # Remove ready from remaining
      .remaining = [.remaining[] | select(. as $id | $ready | index($id) | not)] |
      # Decrement in_degree for dependents of ready tasks
      reduce $ready[] as $done (
        .;
        reduce .remaining[] as $rem (
          .;
          if (.deps[$rem] | index($done)) then
            .in_degree[$rem] -= 1
          else
            .
          end
        )
      )
    end
  ')

  # Check for error
  has_error=$(echo "$state" | jq 'has("error")')
  if [ "$has_error" = "true" ]; then
    error_msg=$(echo "$state" | jq -r '.error')
    echo "ERROR: $error_msg" >&2
    exit 1
  fi
done

# Output groups
echo "$state" | jq '.groups'
exit 0
