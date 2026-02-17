#!/usr/bin/env bash
set -euo pipefail

# compute-dev-count.sh -- Compute optimal Dev agent count
# Formula: min(available_unblocked_tasks, 5)
# Usage: compute-dev-count.sh --available N
# Output: integer on stdout
# Exit: 0 on success, 1 on invalid input

# --- Arg parsing ---
if [ $# -lt 2 ] || [ "$1" != "--available" ]; then
  echo "Usage: compute-dev-count.sh --available N" >&2
  echo "  N: non-negative integer (number of available unblocked tasks)" >&2
  exit 1
fi

N="$2"

# --- Validate N: must be a non-negative integer ---
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --available requires a non-negative integer, got: $N" >&2
  exit 1
fi

# --- Compute min(N, 5) ---
if [ "$N" -gt 5 ]; then
  result=5
else
  result="$N"
fi

echo "$result"
exit 0
