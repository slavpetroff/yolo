#!/usr/bin/env bash
# append-finding.sh — Insert append-only artifact findings into the DB
# Usage: append-finding.sh --type <TYPE> --phase <PHASE> --data <JSON> [--db PATH]
# Types: critique, research, decisions, escalation, gaps,
#        code-review-comment, security-finding, qa-gate-result
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# Parse arguments
TYPE=""
PHASE=""
DATA=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- "${_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)  TYPE="$2";  shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --data)  DATA="$2";  shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$TYPE" ]]; then
  echo "error: --type is required" >&2
  exit 1
fi
if [[ -z "$PHASE" ]]; then
  echo "error: --phase is required" >&2
  exit 1
fi
if [[ -z "$DATA" ]]; then
  echo "error: --data is required" >&2
  exit 1
fi

# Validate JSON
if ! echo "$DATA" | jq empty 2>/dev/null; then
  echo "error: --data must be valid JSON" >&2
  exit 1
fi

DB=$(db_path "$DB_EXPLICIT")
require_db "$DB"

# Helper: extract field from JSON, return empty string if missing
jf() { echo "$DATA" | jq -r ".$1 // empty"; }

# Helper: escape single quotes for SQL
esc() { echo "${1//\'/\'\'}"; }

case "$TYPE" in
  critique)
    # Required: id, cat, sev, q
    id=$(jf id); cat=$(jf cat); sev=$(jf sev); q=$(jf q)
    if [[ -z "$id" || -z "$cat" || -z "$sev" || -z "$q" ]]; then
      echo "error: critique requires id, cat, sev, q fields" >&2
      exit 1
    fi
    ctx=$(jf ctx); sug=$(jf sug); st=$(jf st); cf=$(jf cf); rd=$(jf rd)
    sql_with_retry "$DB" "INSERT INTO critique (id, cat, sev, q, ctx, sug, st, cf, rd, phase)
      VALUES ('$(esc "$id")','$(esc "$cat")','$(esc "$sev")','$(esc "$q")','$(esc "$ctx")','$(esc "$sug")','${st:-open}',${cf:-0},${rd:-1},'$(esc "$PHASE")');"
    echo "ok: critique $id appended (phase $PHASE)"
    ;;

  research)
    # Required: q, finding, conf
    q=$(jf q); finding=$(jf finding); conf=$(jf conf)
    if [[ -z "$q" || -z "$finding" || -z "$conf" ]]; then
      echo "error: research requires q, finding, conf fields" >&2
      exit 1
    fi
    src=$(jf src); dt=$(jf dt); rel=$(jf rel); brief_for=$(jf brief_for)
    mode=$(jf mode); priority=$(jf priority); ra=$(jf ra); rt=$(jf rt)
    # Insert into research table
    sql_with_retry "$DB" "INSERT INTO research (q, src, finding, conf, dt, rel, brief_for, mode, priority, ra, rt, phase)
      VALUES ('$(esc "$q")','$(esc "$src")','$(esc "$finding")','$(esc "$conf")','$(esc "$dt")','$(esc "$rel")','$(esc "$brief_for")','${mode:-standalone}','${priority:-medium}','$(esc "$ra")','${rt:-informational}','$(esc "$PHASE")');"
    # Update FTS index
    rowid=$(sql_query "$DB" "SELECT last_insert_rowid();")
    sql_with_retry "$DB" "INSERT INTO research_fts (rowid, q, finding, conf, phase)
      VALUES ($rowid, '$(esc "$q")', '$(esc "$finding")', '$(esc "$conf")', '$(esc "$PHASE")');" 2>/dev/null || true
    echo "ok: research appended (phase $PHASE)"
    ;;

  decisions)
    # Required: dec, reason
    dec=$(jf dec); reason=$(jf reason)
    if [[ -z "$dec" || -z "$reason" ]]; then
      echo "error: decisions requires dec, reason fields" >&2
      exit 1
    fi
    ts=$(jf ts); agent=$(jf agent); task=$(jf task); alts=$(jf alts)
    sql_with_retry "$DB" "INSERT INTO decisions (ts, agent, task, dec, reason, alts, phase)
      VALUES ('$(esc "$ts")','$(esc "$agent")','$(esc "$task")','$(esc "$dec")','$(esc "$reason")','$(esc "$alts")','$(esc "$PHASE")');"
    # Update FTS index
    rowid=$(sql_query "$DB" "SELECT last_insert_rowid();")
    sql_with_retry "$DB" "INSERT INTO decisions_fts (rowid, dec, reason, agent, phase)
      VALUES ($rowid, '$(esc "$dec")', '$(esc "$reason")', '$(esc "$agent")', '$(esc "$PHASE")');" 2>/dev/null || true
    echo "ok: decision appended (phase $PHASE)"
    ;;

  escalation)
    # Required: id, reason, sev
    id=$(jf id); reason=$(jf reason); sev=$(jf sev)
    if [[ -z "$id" || -z "$reason" || -z "$sev" ]]; then
      echo "error: escalation requires id, reason, sev fields" >&2
      exit 1
    fi
    dt=$(jf dt); agent=$(jf agent); sb=$(jf sb); tgt=$(jf tgt); st=$(jf st); res=$(jf res)
    sql_with_retry "$DB" "INSERT INTO escalation (id, dt, agent, reason, sb, tgt, sev, st, res, phase)
      VALUES ('$(esc "$id")','$(esc "$dt")','$(esc "$agent")','$(esc "$reason")','$(esc "$sb")','$(esc "$tgt")','$(esc "$sev")','${st:-open}','$(esc "$res")','$(esc "$PHASE")');"
    echo "ok: escalation $id appended (phase $PHASE)"
    ;;

  gaps)
    # Required: id, sev, desc
    id=$(jf id); sev=$(jf sev); desc=$(jf desc)
    if [[ -z "$id" || -z "$sev" || -z "$desc" ]]; then
      echo "error: gaps requires id, sev, desc fields" >&2
      exit 1
    fi
    exp=$(jf exp); act=$(jf act); st=$(jf st); res=$(jf res)
    sql_with_retry "$DB" "INSERT INTO gaps (id, sev, \"desc\", exp, act, st, res, phase)
      VALUES ('$(esc "$id")','$(esc "$sev")','$(esc "$desc")','$(esc "$exp")','$(esc "$act")','${st:-open}','$(esc "$res")','$(esc "$PHASE")');"
    # Update FTS index
    rowid=$(sql_query "$DB" "SELECT last_insert_rowid();")
    sql_with_retry "$DB" "INSERT INTO gaps_fts (rowid, \"desc\", exp, act, res, phase)
      VALUES ($rowid, '$(esc "$desc")', '$(esc "$exp")', '$(esc "$act")', '$(esc "$res")', '$(esc "$PHASE")');" 2>/dev/null || true
    echo "ok: gap $id appended (phase $PHASE)"
    ;;

  code-review-comment)
    # Map to code_review table
    plan=$(jf plan); r=$(jf r); tdd=$(jf tdd); cycle=$(jf cycle); dt=$(jf dt)
    sg_reviewed=$(jf sg_reviewed); sg_promoted=$(jf sg_promoted)
    if [[ -z "$r" ]]; then
      echo "error: code-review-comment requires r field" >&2
      exit 1
    fi
    sql_with_retry "$DB" "INSERT INTO code_review (plan, r, tdd, cycle, dt, sg_reviewed, sg_promoted, phase)
      VALUES ('$(esc "$plan")','$(esc "$r")','$(esc "$tdd")',${cycle:-1},'$(esc "$dt")',${sg_reviewed:-0},'$(esc "$sg_promoted")','$(esc "$PHASE")');"
    echo "ok: code-review appended (phase $PHASE)"
    ;;

  security-finding)
    # Map to security_audit table
    r=$(jf r); findings=$(jf findings); critical=$(jf critical); dt=$(jf dt)
    if [[ -z "$r" ]]; then
      echo "error: security-finding requires r field" >&2
      exit 1
    fi
    sql_with_retry "$DB" "INSERT INTO security_audit (r, findings, critical, dt, phase)
      VALUES ('$(esc "$r")',${findings:-0},${critical:-0},'$(esc "$dt")','$(esc "$PHASE")');"
    echo "ok: security-finding appended (phase $PHASE)"
    ;;

  qa-gate-result)
    # Map to qa_gate_results table
    gl=$(jf gl); r=$(jf r); plan=$(jf plan); task=$(jf task)
    tst=$(jf tst); dur=$(jf dur); f=$(jf f); mh=$(jf mh); dt=$(jf dt)
    if [[ -z "$gl" || -z "$r" ]]; then
      echo "error: qa-gate-result requires gl, r fields" >&2
      exit 1
    fi
    sql_with_retry "$DB" "INSERT INTO qa_gate_results (gl, r, plan, task, tst, dur, f, mh, dt, phase)
      VALUES ('$(esc "$gl")','$(esc "$r")','$(esc "$plan")','$(esc "$task")','$(esc "$tst")',${dur:-0},'$(esc "$f")','$(esc "$mh")','$(esc "$dt")','$(esc "$PHASE")');"
    echo "ok: qa-gate-result appended (phase $PHASE)"
    ;;

  *)
    echo "error: unknown type '$TYPE'. Supported: critique, research, decisions, escalation, gaps, code-review-comment, security-finding, qa-gate-result" >&2
    exit 1
    ;;
esac
