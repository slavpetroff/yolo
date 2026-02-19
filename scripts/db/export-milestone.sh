#!/usr/bin/env bash
# export-milestone.sh — Export DB back to JSONL files for rollback
# Usage: export-milestone.sh --planning-dir <PATH> [--db PATH] [--phase PHASE]
# Safety net: if SQLite causes issues, export back to files and continue
# with file-based system.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/db-common.sh"

# Parse arguments
PLANNING_DIR=""
PHASE_FILTER=""

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planning-dir) PLANNING_DIR="$2"; shift 2 ;;
    --phase)        PHASE_FILTER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: export-milestone.sh --planning-dir <PATH> [--db PATH] [--phase PHASE]"
      echo ""
      echo "Options:"
      echo "  --planning-dir PATH  Planning directory to write JSONL files"
      echo "  --db PATH            Database path (default: <planning-dir>/yolo.db)"
      echo "  --phase PHASE        Export single phase (e.g., 01), default exports all"
      exit 0
      ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PLANNING_DIR" ]]; then
  echo "error: --planning-dir is required" >&2
  exit 1
fi

# Resolve DB path
if [[ -n "$DB_EXPLICIT" ]]; then
  DB="$DB_EXPLICIT"
else
  DB="$PLANNING_DIR/yolo.db"
fi

require_db "$DB"

# Counters
total_plans=0
total_summaries=0
total_critique=0
total_research=0
total_decisions=0
total_escalation=0
total_gaps=0

# Helper: SQL escape for filter values
esc() { echo "${1//\'/\'\'}"; }

# Build phase filter clause
phase_clause=""
if [[ -n "$PHASE_FILTER" ]]; then
  phase_clause="WHERE phase='$(esc "$PHASE_FILTER")'"
fi

# Get list of phases to export
phases=()
if [[ -n "$PHASE_FILTER" ]]; then
  phases=("$PHASE_FILTER")
else
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    phases+=("$p")
  done < <(sql_query "$DB" "SELECT DISTINCT phase FROM plans ORDER BY phase;")
fi

for phase in ${phases[@]+"${phases[@]}"}; do
  [[ -z "$phase" ]] && continue

  # Find the phase directory by matching the phase number prefix
  phase_dir=""
  for d in "$PLANNING_DIR/phases/${phase}-"*/; do
    if [[ -d "$d" ]]; then
      phase_dir="$d"
      break
    fi
  done

  # Create phase dir if it doesn't exist
  if [[ -z "$phase_dir" ]]; then
    # Get slug from phases table
    slug=$(sql_query "$DB" "SELECT slug FROM phases WHERE phase_num='$(esc "$phase")';")
    if [[ -n "$slug" ]]; then
      phase_dir="$PLANNING_DIR/phases/${phase}-${slug}/"
    else
      phase_dir="$PLANNING_DIR/phases/${phase}-exported/"
    fi
    mkdir -p "$phase_dir"
  fi

  # Export plans + tasks
  plan_rows=$(sql_query "$DB" "SELECT rowid, phase, plan_num, title, wave, depends_on, xd, must_haves, objective, effort, skills, fm, autonomous FROM plans WHERE phase='$(esc "$phase")' ORDER BY plan_num;")
  while IFS='|' read -r rowid p pn title wave deps xd mh obj eff sk fm auto; do
    [[ -z "$rowid" ]] && continue
    plan_file="${phase_dir}${p}-${pn}.plan.jsonl"

    # Build plan header JSON
    auto_bool="false"
    [[ "$auto" -eq 1 ]] 2>/dev/null && auto_bool="true"

    header=$(jq -nc \
      --arg p "$p" --arg n "$pn" --arg t "$title" --argjson w "${wave:-1}" \
      --argjson d "${deps:-null}" --argjson xd "${xd:-null}" --argjson mh "${mh:-null}" \
      --arg obj "$obj" --arg eff "${eff:-balanced}" --argjson sk "${sk:-null}" \
      --argjson fm "${fm:-null}" --argjson auto "$auto_bool" \
      '{p:$p, n:$n, t:$t, w:$w} +
       (if $d != null then {d:$d} else {} end) +
       (if $xd != null then {xd:$xd} else {} end) +
       (if $mh != null then {mh:$mh} else {} end) +
       (if $obj != "" then {obj:$obj} else {} end) +
       {eff:$eff} +
       (if $sk != null then {sk:$sk} else {} end) +
       (if $fm != null then {fm:$fm} else {} end) +
       (if $auto then {auto:$auto} else {} end)')

    echo "$header" > "$plan_file"

    # Export tasks for this plan
    task_rows=$(sql_query "$DB" "SELECT task_id, type, action, files, verify, done, spec, test_spec, task_depends FROM tasks WHERE plan_id=$rowid ORDER BY rowid;")
    while IFS='|' read -r tid tp act files ver done_val spec ts td; do
      [[ -z "$tid" ]] && continue
      done_bool="false"
      [[ "$done_val" == "true" || "$done_val" == "1" ]] && done_bool="true"

      task_json=$(jq -nc \
        --arg id "$tid" --arg tp "${tp:-auto}" --arg a "$act" \
        --argjson f "${files:-null}" --arg v "$ver" --argjson done "$done_bool" \
        --arg spec "$spec" --arg ts "$ts" --argjson td "${td:-null}" \
        '{id:$id} +
         (if $tp != "auto" then {tp:$tp} else {} end) +
         {a:$a} +
         (if $f != null then {f:$f} else {} end) +
         (if $v != "" then {v:$v} else {} end) +
         {done:$done} +
         (if $spec != "" then {spec:$spec} else {} end) +
         (if $ts != "" then {ts:$ts} else {} end) +
         (if $td != null then {td:$td} else {} end)')
      echo "$task_json" >> "$plan_file"
    done <<< "$task_rows"

    total_plans=$((total_plans + 1))
  done <<< "$plan_rows"

  # Export summaries
  summary_rows=$(sql_query "$DB" "SELECT s.plan_id, p.phase, p.plan_num, s.status, s.date_completed, s.tasks_completed, s.tasks_total, s.commit_hashes, s.fm, s.deviations, s.built, s.test_status, s.suggestions FROM summaries s JOIN plans p ON s.plan_id=p.rowid WHERE p.phase='$(esc "$phase")' ORDER BY p.plan_num;")
  while IFS='|' read -r pid pp pn st dt tc tt ch fm dv built tst sg; do
    [[ -z "$pid" ]] && continue
    summary_file="${phase_dir}${pp}-${pn}.summary.jsonl"

    summary_json=$(jq -nc \
      --arg p "$pp" --arg n "$pn" --arg s "${st:-complete}" --arg dt "$dt" \
      --argjson tc "${tc:-0}" --argjson tt "${tt:-0}" \
      --argjson ch "${ch:-null}" --argjson fm "${fm:-null}" \
      --argjson dv "${dv:-null}" --argjson built "${built:-null}" \
      --arg tst "$tst" --argjson sg "${sg:-null}" \
      '{p:$p, n:$n, s:$s, dt:$dt, tc:$tc, tt:$tt} +
       (if $ch != null then {ch:$ch} else {} end) +
       (if $fm != null then {fm:$fm} else {} end) +
       (if $dv != null then {dv:$dv} else {} end) +
       (if $built != null then {built:$built} else {} end) +
       (if $tst != "" then {tst:$tst} else {} end) +
       (if $sg != null then {sg:$sg} else {} end)')

    echo "$summary_json" > "$summary_file"
    total_summaries=$((total_summaries + 1))
  done <<< "$summary_rows"

  # Export critique.jsonl
  critique_rows=$(sql_query "$DB" "SELECT id, cat, sev, q, ctx, sug, st, cf, rd FROM critique WHERE phase='$(esc "$phase")' ORDER BY rowid;")
  if [[ -n "$critique_rows" ]] && [[ "$critique_rows" != "" ]]; then
    critique_file="${phase_dir}critique.jsonl"
    > "$critique_file"
    while IFS='|' read -r id cat sev q ctx sug st cf rd; do
      [[ -z "$id" ]] && continue
      jq -nc \
        --arg id "$id" --arg cat "$cat" --arg sev "$sev" --arg q "$q" \
        --arg ctx "$ctx" --arg sug "$sug" --arg st "${st:-open}" \
        --argjson cf "${cf:-0}" --argjson rd "${rd:-1}" \
        '{id:$id, cat:$cat, sev:$sev, q:$q, ctx:$ctx, sug:$sug, st:$st, cf:$cf, rd:$rd}' >> "$critique_file"
      total_critique=$((total_critique + 1))
    done <<< "$critique_rows"
  fi

  # Export research.jsonl
  research_rows=$(sql_query "$DB" "SELECT q, src, finding, conf, dt, rel FROM research WHERE phase='$(esc "$phase")' ORDER BY rowid;")
  if [[ -n "$research_rows" ]] && [[ "$research_rows" != "" ]]; then
    research_file="${phase_dir}research.jsonl"
    > "$research_file"
    while IFS='|' read -r q src finding conf dt rel; do
      [[ -z "$q" ]] && continue
      jq -nc \
        --arg q "$q" --arg src "$src" --arg finding "$finding" \
        --arg conf "${conf:-medium}" --arg dt "$dt" --arg rel "$rel" \
        '{q:$q, src:$src, finding:$finding, conf:$conf, dt:$dt, rel:$rel}' >> "$research_file"
      total_research=$((total_research + 1))
    done <<< "$research_rows"
  fi

  # Export decisions.jsonl
  decisions_rows=$(sql_query "$DB" "SELECT ts, agent, task, dec, reason, alts FROM decisions WHERE phase='$(esc "$phase")' ORDER BY rowid;")
  if [[ -n "$decisions_rows" ]] && [[ "$decisions_rows" != "" ]]; then
    decisions_file="${phase_dir}decisions.jsonl"
    > "$decisions_file"
    while IFS='|' read -r ts agent task dec reason alts; do
      [[ -z "$dec" ]] && continue
      jq -nc \
        --arg ts "$ts" --arg agent "$agent" --arg task "$task" \
        --arg dec "$dec" --arg reason "$reason" --argjson alts "${alts:-null}" \
        '{ts:$ts, agent:$agent, task:$task, dec:$dec, reason:$reason} +
         (if $alts != null then {alts:$alts} else {} end)' >> "$decisions_file"
      total_decisions=$((total_decisions + 1))
    done <<< "$decisions_rows"
  fi

  # Export escalation.jsonl
  escalation_rows=$(sql_query "$DB" "SELECT id, dt, agent, reason, sb, tgt, sev, st, res FROM escalation WHERE phase='$(esc "$phase")' ORDER BY rowid;")
  if [[ -n "$escalation_rows" ]] && [[ "$escalation_rows" != "" ]]; then
    escalation_file="${phase_dir}escalation.jsonl"
    > "$escalation_file"
    while IFS='|' read -r id dt agent reason sb tgt sev st res; do
      [[ -z "$id" ]] && continue
      jq -nc \
        --arg id "$id" --arg dt "$dt" --arg agent "$agent" --arg reason "$reason" \
        --arg sb "$sb" --arg tgt "$tgt" --arg sev "$sev" --arg st "${st:-open}" --arg res "$res" \
        '{id:$id, dt:$dt, agent:$agent, reason:$reason, sb:$sb, tgt:$tgt, sev:$sev, st:$st, res:$res}' >> "$escalation_file"
      total_escalation=$((total_escalation + 1))
    done <<< "$escalation_rows"
  fi

  # Export gaps.jsonl
  gaps_rows=$(sql_query "$DB" "SELECT id, sev, \"desc\", exp, act, st, res FROM gaps WHERE phase='$(esc "$phase")' ORDER BY rowid;")
  if [[ -n "$gaps_rows" ]] && [[ "$gaps_rows" != "" ]]; then
    gaps_file="${phase_dir}gaps.jsonl"
    > "$gaps_file"
    while IFS='|' read -r id sev desc exp act st res; do
      [[ -z "$id" ]] && continue
      jq -nc \
        --arg id "$id" --arg sev "$sev" --arg desc "$desc" \
        --arg exp "$exp" --arg act "$act" --arg st "${st:-open}" --arg res "$res" \
        '{id:$id, sev:$sev, desc:$desc, exp:$exp, act:$act, st:$st, res:$res}' >> "$gaps_file"
      total_gaps=$((total_gaps + 1))
    done <<< "$gaps_rows"
  fi
done

echo "Exported: $total_plans plans, $total_summaries summaries, $total_critique critique, $total_research research, $total_decisions decisions, $total_escalation escalation, $total_gaps gaps"
