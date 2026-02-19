#!/usr/bin/env bash
# import-jsonl.sh — Bulk import JSONL artifacts into SQLite
# Usage: import-jsonl.sh --type <TYPE> --file <PATH> --phase <PHASE> [--db PATH]
# Migration bridge for existing JSONL artifacts.
# Types: plan, summary, critique, research, decisions, escalation, gaps
set -euo pipefail

source "$(dirname "$0")/db-common.sh"

# Parse arguments
TYPE=""
FILE=""
PHASE=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- "${_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)  TYPE="$2";  shift 2 ;;
    --file)  FILE="$2";  shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$TYPE" ]]; then
  echo "error: --type is required" >&2
  exit 1
fi
if [[ -z "$FILE" ]]; then
  echo "error: --file is required" >&2
  exit 1
fi
if [[ ! -f "$FILE" ]]; then
  echo "error: file not found: $FILE" >&2
  exit 1
fi
if [[ -z "$PHASE" ]]; then
  echo "error: --phase is required" >&2
  exit 1
fi

DB=$(db_path "$DB_EXPLICIT")
require_db "$DB"

# Helper: escape single quotes for SQL
esc() { echo "${1//\'/\'\'}"; }

# Helper: extract field from jq, return empty string for null
jf() { echo "$1" | jq -r ".$2 // empty"; }

# Helper: extract raw JSON field (for arrays/objects)
jfr() { echo "$1" | jq -c ".$2 // null"; }

count=0

case "$TYPE" in
  plan)
    # Line 1 = plan header, lines 2+ = tasks
    # Read header (line 1)
    header=$(head -1 "$FILE")
    if [[ -z "$header" ]]; then
      echo "error: empty plan file" >&2
      exit 1
    fi

    # Extract plan header fields (abbreviated JSONL keys -> SQL columns)
    p=$(jf "$header" p)
    n=$(jf "$header" n)
    t=$(jf "$header" t)
    w=$(jf "$header" w)
    d=$(jfr "$header" d)
    xd=$(jfr "$header" xd)
    mh=$(jfr "$header" mh)
    obj=$(jf "$header" obj)
    eff=$(jf "$header" eff)
    sk=$(jfr "$header" sk)
    fm=$(jfr "$header" fm)
    auto_val=$(jf "$header" auto)

    # Use phase from file if available, else from --phase flag
    plan_phase="${p:-$PHASE}"
    plan_num="${n:-00}"
    auto_int=0
    [[ "$auto_val" == "true" ]] && auto_int=1

    # Build SQL for transaction
    sql_stmts="INSERT OR REPLACE INTO plans (phase, plan_num, title, wave, depends_on, xd, must_haves, objective, effort, skills, fm, autonomous)
VALUES ('$(esc "$plan_phase")','$(esc "$plan_num")','$(esc "$t")',${w:-1},'$(esc "$d")','$(esc "$xd")','$(esc "$mh")','$(esc "$obj")','${eff:-balanced}','$(esc "$sk")','$(esc "$fm")',$auto_int);"

    count=1  # header counts as 1

    # Read task lines (2+) — use process substitution to avoid subshell
    plan_rowid_sql="(SELECT rowid FROM plans WHERE phase='$(esc "$plan_phase")' AND plan_num='$(esc "$plan_num")')"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Validate it's JSON
      echo "$line" | jq empty 2>/dev/null || continue

      tid=$(jf "$line" id)
      [[ -z "$tid" ]] && continue

      tp=$(jf "$line" tp)
      a=$(jf "$line" a)
      f=$(jfr "$line" f)
      v=$(jf "$line" v)
      done_val=$(jf "$line" done)
      spec=$(jf "$line" spec)
      ts=$(jf "$line" ts)
      td=$(jfr "$line" td)

      sql_stmts="$sql_stmts
INSERT OR REPLACE INTO tasks (plan_id, task_id, type, action, files, verify, done, spec, test_spec, task_depends)
VALUES ($plan_rowid_sql, '$(esc "$tid")','${tp:-auto}','$(esc "$a")','$(esc "$f")','$(esc "$v")','$(esc "$done_val")','$(esc "$spec")','$(esc "$ts")','$(esc "$td")');"
      count=$((count + 1))
    done < <(tail -n +2 "$FILE")

    sql_exec "$DB" "$sql_stmts"
    # Count actual rows
    task_count=$(sql_query "$DB" "SELECT count(*) FROM tasks WHERE plan_id IN (SELECT rowid FROM plans WHERE phase='$(esc "$plan_phase")' AND plan_num='$(esc "$plan_num")');")
    count=$((1 + task_count))
    echo "Imported $count rows into plans+tasks for phase $PHASE"
    ;;

  summary)
    # Single line per summary file
    line=$(head -1 "$FILE")
    [[ -z "$line" ]] && { echo "error: empty summary file" >&2; exit 1; }

    p=$(jf "$line" p)
    n=$(jf "$line" n)
    s=$(jf "$line" s)
    dt=$(jf "$line" dt)
    tc=$(jf "$line" tc)
    tt=$(jf "$line" tt)
    ch=$(jfr "$line" ch)
    fm=$(jfr "$line" fm)
    dv=$(jfr "$line" dv)
    built=$(jfr "$line" built)
    tst=$(jf "$line" tst)
    sg=$(jfr "$line" sg)

    plan_phase="${p:-$PHASE}"
    plan_num="${n:-00}"

    plan_rowid_sql="(SELECT rowid FROM plans WHERE phase='$(esc "$plan_phase")' AND plan_num='$(esc "$plan_num")')"
    sql_exec "$DB" "INSERT OR REPLACE INTO summaries (plan_id, status, date_completed, tasks_completed, tasks_total, commit_hashes, fm, deviations, built, test_status, suggestions)
VALUES ($plan_rowid_sql, '$(esc "$s")','$(esc "$dt")',${tc:-0},${tt:-0},'$(esc "$ch")','$(esc "$fm")','$(esc "$dv")','$(esc "$built")','$(esc "$tst")','$(esc "$sg")');"

    echo "Imported 1 row into summaries for phase $PHASE"
    ;;

  critique|research|decisions|escalation|gaps)
    # Multi-line artifacts: one finding per line
    sql_stmts=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line" | jq empty 2>/dev/null || continue

      case "$TYPE" in
        critique)
          id=$(jf "$line" id); cat=$(jf "$line" cat); sev=$(jf "$line" sev)
          q=$(jf "$line" q); ctx=$(jf "$line" ctx); sug=$(jf "$line" sug)
          st=$(jf "$line" st); cf=$(jf "$line" cf); rd=$(jf "$line" rd)
          sql_stmts="$sql_stmts
INSERT INTO critique (id, cat, sev, q, ctx, sug, st, cf, rd, phase)
VALUES ('$(esc "$id")','$(esc "$cat")','$(esc "$sev")','$(esc "$q")','$(esc "$ctx")','$(esc "$sug")','${st:-open}',${cf:-0},${rd:-1},'$(esc "$PHASE")');"
          ;;
        research)
          q=$(jf "$line" q); src=$(jf "$line" src); finding=$(jf "$line" finding)
          conf=$(jf "$line" conf); dt=$(jf "$line" dt); rel=$(jf "$line" rel)
          sql_stmts="$sql_stmts
INSERT INTO research (q, src, finding, conf, dt, rel, phase)
VALUES ('$(esc "$q")','$(esc "$src")','$(esc "$finding")','$(esc "$conf")','$(esc "$dt")','$(esc "$rel")','$(esc "$PHASE")');"
          ;;
        decisions)
          ts=$(jf "$line" ts); agent=$(jf "$line" agent); task=$(jf "$line" task)
          dec=$(jf "$line" dec); reason=$(jf "$line" reason); alts=$(jfr "$line" alts)
          sql_stmts="$sql_stmts
INSERT INTO decisions (ts, agent, task, dec, reason, alts, phase)
VALUES ('$(esc "$ts")','$(esc "$agent")','$(esc "$task")','$(esc "$dec")','$(esc "$reason")','$(esc "$alts")','$(esc "$PHASE")');"
          ;;
        escalation)
          id=$(jf "$line" id); dt=$(jf "$line" dt); agent=$(jf "$line" agent)
          reason=$(jf "$line" reason); sb=$(jf "$line" sb); tgt=$(jf "$line" tgt)
          sev=$(jf "$line" sev); st=$(jf "$line" st); res=$(jf "$line" res)
          sql_stmts="$sql_stmts
INSERT INTO escalation (id, dt, agent, reason, sb, tgt, sev, st, res, phase)
VALUES ('$(esc "$id")','$(esc "$dt")','$(esc "$agent")','$(esc "$reason")','$(esc "$sb")','$(esc "$tgt")','$(esc "$sev")','${st:-open}','$(esc "$res")','$(esc "$PHASE")');"
          ;;
        gaps)
          id=$(jf "$line" id); sev=$(jf "$line" sev); desc=$(jf "$line" desc)
          exp=$(jf "$line" exp); act=$(jf "$line" act); st=$(jf "$line" st)
          res=$(jf "$line" res)
          sql_stmts="$sql_stmts
INSERT INTO gaps (id, sev, \"desc\", exp, act, st, res, phase)
VALUES ('$(esc "$id")','$(esc "$sev")','$(esc "$desc")','$(esc "$exp")','$(esc "$act")','${st:-open}','$(esc "$res")','$(esc "$PHASE")');"
          ;;
      esac
      count=$((count + 1))
    done < "$FILE"

    if [[ $count -gt 0 ]]; then
      sql_exec "$DB" "$sql_stmts"
    fi
    echo "Imported $count rows into $TYPE for phase $PHASE"
    ;;

  *)
    echo "error: unknown type '$TYPE'. Supported: plan, summary, critique, research, decisions, escalation, gaps" >&2
    exit 1
    ;;
esac
