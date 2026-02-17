#!/usr/bin/env bash
set -euo pipefail
# filter-agent-context.sh -- Extract role-specific fields from JSONL artifacts
# Implements the field mappings documented in references/agent-field-map.md
# Usage: filter-agent-context.sh --role <role> --artifact <path> --type <type> [--mode <design|review>]
# Output: Filtered JSONL to stdout
# Exit: 0=success, 1=error (unknown role, missing file, unknown type)

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo 'Error: jq is required but not installed.' >&2
  exit 1
fi

# --- Argument parsing ---
ROLE=""
ARTIFACT=""
TYPE=""
MODE="design"

while [ $# -gt 0 ]; do
  case "$1" in
    --role)
      ROLE="$2"
      shift 2
      ;;
    --artifact)
      ARTIFACT="$2"
      shift 2
      ;;
    --type)
      TYPE="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    *)
      echo "Usage: filter-agent-context.sh --role <role> --artifact <path> --type <type> [--mode <design|review>]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ROLE" ] || [ -z "$ARTIFACT" ] || [ -z "$TYPE" ]; then
  echo "Usage: filter-agent-context.sh --role <role> --artifact <path> --type <type> [--mode <design|review>]" >&2
  exit 1
fi

if [ ! -f "$ARTIFACT" ]; then
  echo "Error: artifact not found: $ARTIFACT" >&2
  exit 1
fi

# --- Prefix stripping ---
case "$ROLE" in
  fe-*) BASE_ROLE="${ROLE#fe-}" ;;
  ux-*) BASE_ROLE="${ROLE#ux-}" ;;
  owner|critic|scout|debugger) BASE_ROLE="$ROLE" ;;
  *) BASE_ROLE="$ROLE" ;;
esac

# --- Type validation ---
case "$TYPE" in
  plan|summary|critique|research|code-review|verification|qa-code|security-audit|test-plan|gaps)
    : ;;
  *)
    echo "Error: unknown artifact type: $TYPE. Valid types: plan, summary, critique, research, code-review, verification, qa-code, security-audit, test-plan, gaps" >&2
    exit 1
    ;;
esac

# --- Filter by role and type ---
case "$BASE_ROLE" in
  architect)
    case "$TYPE" in
      critique) jq -c '{id,cat,sev,q,ctx,sug,st}' "$ARTIFACT" ;;
      research) jq -c '{q,finding,conf,rel,brief_for:(.brief_for // "")}' "$ARTIFACT" ;;
      plan) head -1 "$ARTIFACT" ;;
      *) echo "Error: architect does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  lead)
    case "$TYPE" in
      plan)
        head -1 "$ARTIFACT"
        tail -n +2 "$ARTIFACT" | jq -c '{id,a,f,done,v}' ;;
      summary) jq -c '{s,tc,tt,fm,dv}' "$ARTIFACT" ;;
      *) echo "Error: lead does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  senior)
    case "$TYPE" in
      plan)
        if [ "$MODE" = "review" ]; then
          tail -n +2 "$ARTIFACT" | jq -c '{id,a,f,spec,ts,done}'
        else
          tail -n +2 "$ARTIFACT" | jq -c '{id,a,f,done,v}'
        fi ;;
      critique) jq -c 'select(.st=="open") | {id, q: (.q // .desc // ""), sug: (.sug // .rec // "")}' "$ARTIFACT" ;;
      test-plan) jq -c '{id,tf,tc,red}' "$ARTIFACT" ;;
      *) echo "Error: senior does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  dev)
    case "$TYPE" in
      plan) tail -n +2 "$ARTIFACT" | jq -c '{id,a,f,spec,ts,done}' ;;
      gaps) jq -c '{id,sev,desc,exp,act,st}' "$ARTIFACT" ;;
      *) echo "Error: dev does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  tester)
    case "$TYPE" in
      plan) tail -n +2 "$ARTIFACT" | jq -c '{id,a,f,ts,spec}' ;;
      *) echo "Error: tester does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  qa)
    case "$TYPE" in
      plan) head -1 "$ARTIFACT" | jq -c '{mh,obj}' ;;
      summary) jq -c '{s,tc,tt,fm,dv,tst}' "$ARTIFACT" ;;
      *) echo "Error: qa does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  qa-code)
    case "$TYPE" in
      summary) jq -c '{fm}' "$ARTIFACT" ;;
      test-plan) jq -c '{id,tf,tc,red}' "$ARTIFACT" ;;
      *) echo "Error: qa-code does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  security)
    case "$TYPE" in
      summary) jq -c '{fm}' "$ARTIFACT" ;;
      *) echo "Error: security does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  scout)
    case "$TYPE" in
      critique) jq -c 'select(.sev=="critical" or .sev=="major") | {id,sev,q}' "$ARTIFACT" ;;
      *) echo "Error: scout does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  critic)
    case "$TYPE" in
      research) jq -c '{q,finding,conf}' "$ARTIFACT" ;;
      *) echo "Error: critic does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  debugger)
    case "$TYPE" in
      research) jq -c '{q,finding}' "$ARTIFACT" ;;
      gaps) cat "$ARTIFACT" ;;
      summary) jq -c '{fm,ch,dv}' "$ARTIFACT" ;;
      *) echo "Error: debugger does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  owner)
    case "$TYPE" in
      plan) head -1 "$ARTIFACT" ;;
      summary) jq -c '{s,fm,dv}' "$ARTIFACT" ;;
      *) echo "Error: owner does not consume $TYPE artifacts" >&2; exit 1 ;;
    esac ;;
  *)
    echo "Error: unknown role: $ROLE (base: $BASE_ROLE). Valid base roles: architect, lead, senior, dev, tester, qa, qa-code, security, scout, critic, debugger, owner" >&2
    exit 1 ;;
esac

exit 0
