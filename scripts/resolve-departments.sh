#!/usr/bin/env bash
set -euo pipefail

# resolve-departments.sh — Deterministic department routing
#
# Reads department config and outputs structured routing data.
# Called by go.md (like phase-detect.sh) to determine multi-department dispatch.
#
# Usage: bash scripts/resolve-departments.sh [config_path]
# Output: Key-value pairs:
#   multi_dept=true|false
#   workflow=backend_only|sequential|parallel
#   active_depts=backend[,frontend][,uiux]
#   leads_to_spawn=<wave1>[|<wave2>]  (| separates waves, , separates parallel)
#   spawn_order=single|wave|sequential
#   owner_active=true|false
#   fe_active=true|false
#   ux_active=true|false
#
# Examples:
#   backend_only:           leads_to_spawn=lead              spawn_order=single
#   parallel (FE only):     leads_to_spawn=fe-lead,lead      spawn_order=wave
#   parallel (UX+FE):       leads_to_spawn=ux-lead|fe-lead,lead  spawn_order=wave
#   sequential (UX+FE):     leads_to_spawn=ux-lead|fe-lead|lead  spawn_order=sequential

CONFIG="${1:-.yolo-planning/config.json}"

if [ ! -f "$CONFIG" ]; then
  # Default: backend only (matches jq fallback when config has no department keys)
  echo "multi_dept=false"
  echo "workflow=backend_only"
  echo "active_depts=backend"
  echo "leads_to_spawn=lead"
  echo "spawn_order=single"
  echo "owner_active=false"
  echo "fe_active=false"
  echo "ux_active=false"
  exit 0
fi

IFS='|' read -r BACKEND FRONTEND UIUX WORKFLOW <<< "$(jq -r '[
  (.departments.backend // true),
  (.departments.frontend // false),
  (.departments.uiux // false),
  (.department_workflow // "backend_only")
] | join("|")' "$CONFIG")"

# Determine multi-department mode
MULTI_DEPT="false"
if [ "$FRONTEND" = "true" ] || [ "$UIUX" = "true" ]; then
  if [ "$WORKFLOW" != "backend_only" ]; then
    MULTI_DEPT="true"
  fi
fi

# Build active departments list
ACTIVE_DEPTS="backend"
if [ "$FRONTEND" = "true" ]; then ACTIVE_DEPTS="${ACTIVE_DEPTS},frontend"; fi
if [ "$UIUX" = "true" ]; then ACTIVE_DEPTS="${ACTIVE_DEPTS},uiux"; fi

# Build leads dispatch plan (| = wave separator, , = parallel within wave)
LEADS=""
SPAWN_ORDER="single"

if [ "$MULTI_DEPT" = "true" ]; then
  if [ "$WORKFLOW" = "parallel" ]; then
    SPAWN_ORDER="wave"
    # Wave 1: UX (if active)
    if [ "$UIUX" = "true" ]; then
      LEADS="ux-lead"
      # Wave 2: FE + BE in parallel
      if [ "$FRONTEND" = "true" ]; then
        LEADS="${LEADS}|fe-lead,lead"
      else
        LEADS="${LEADS}|lead"
      fi
    else
      # No UX, just FE + BE in parallel
      if [ "$FRONTEND" = "true" ]; then
        LEADS="fe-lead,lead"
      else
        LEADS="lead"
      fi
    fi
  elif [ "$WORKFLOW" = "sequential" ]; then
    SPAWN_ORDER="sequential"
    if [ "$UIUX" = "true" ]; then LEADS="ux-lead"; fi
    if [ "$FRONTEND" = "true" ]; then
      if [ -n "$LEADS" ]; then LEADS="${LEADS}|fe-lead"; else LEADS="fe-lead"; fi
    fi
    if [ -n "$LEADS" ]; then LEADS="${LEADS}|lead"; else LEADS="lead"; fi
  fi
else
  LEADS="lead"
fi

# Owner active when multi-department
OWNER_ACTIVE="false"
if [ "$MULTI_DEPT" = "true" ]; then OWNER_ACTIVE="true"; fi

echo "multi_dept=$MULTI_DEPT"
echo "workflow=$WORKFLOW"
echo "active_depts=$ACTIVE_DEPTS"
echo "leads_to_spawn=$LEADS"
echo "spawn_order=$SPAWN_ORDER"
echo "owner_active=$OWNER_ACTIVE"
echo "fe_active=$FRONTEND"
echo "ux_active=$UIUX"
