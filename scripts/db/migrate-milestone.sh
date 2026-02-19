#!/usr/bin/env bash
# migrate-milestone.sh — Full milestone migration from JSONL files to SQLite
# Usage: migrate-milestone.sh --planning-dir <PATH> [--db PATH] [--dry-run]
# Behavior:
#   1. Call init-db.sh to create/verify DB
#   2. Import ROADMAP and requirements via import-roadmap.sh + import-requirements.sh
#   3. For each phase directory: import all artifact JSONL files
#   4. Import research-archive.jsonl
#   5. Report migration summary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/db-common.sh"

# Parse arguments
PLANNING_DIR=""
DRY_RUN=false

parse_db_flag "$@"
DB_EXPLICIT="$_DB_PATH"
set -- ${_REMAINING_ARGS[@]+"${_REMAINING_ARGS[@]}"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planning-dir) PLANNING_DIR="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: migrate-milestone.sh --planning-dir <PATH> [--db PATH] [--dry-run]"
      echo ""
      echo "Options:"
      echo "  --planning-dir PATH  Planning directory containing phases/"
      echo "  --db PATH            Database path (default: <planning-dir>/yolo.db)"
      echo "  --dry-run            Count artifacts without importing"
      exit 0
      ;;
    *) echo "error: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PLANNING_DIR" ]]; then
  echo "error: --planning-dir is required" >&2
  exit 1
fi

if [[ ! -d "$PLANNING_DIR" ]]; then
  echo "error: planning directory not found: $PLANNING_DIR" >&2
  exit 1
fi

# Resolve DB path
if [[ -n "$DB_EXPLICIT" ]]; then
  DB="$DB_EXPLICIT"
else
  DB="$PLANNING_DIR/yolo.db"
fi

# Counters
total_phases=0
total_plans=0
total_tasks=0
total_summaries=0
total_research=0
total_decisions=0
total_critique=0
total_escalation=0
total_gaps=0
total_verification=0
total_code_review=0
total_test_plan=0
total_test_results=0
total_qa_gate=0
total_security=0
total_archive=0

# Helper: count lines in JSONL file (excluding empty lines)
count_lines() {
  local file="$1"
  local count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    count=$((count + 1))
  done < "$file"
  echo "$count"
}

# Helper: count tasks in a plan file (lines 2+)
count_plan_tasks() {
  local file="$1"
  local count=0
  local linenum=0
  while IFS= read -r line; do
    linenum=$((linenum + 1))
    [[ $linenum -eq 1 ]] && continue  # skip header
    [[ -z "$line" ]] && continue
    count=$((count + 1))
  done < "$file"
  echo "$count"
}

# Step 1: Initialize DB (skip in dry-run)
if [[ "$DRY_RUN" != true ]]; then
  # Remove existing DB for clean migration
  rm -f "$DB" "${DB}-wal" "${DB}-shm"
  mkdir -p "$(dirname "$DB")"
  # Create schema directly at target DB path
  sqlite3 "$DB" < "$SCRIPT_DIR/schema.sql"
  sqlite3 "$DB" "PRAGMA journal_mode=WAL;" >/dev/null
  sqlite3 "$DB" "PRAGMA busy_timeout=5000;" >/dev/null
  sqlite3 "$DB" "PRAGMA foreign_keys=ON;" >/dev/null
fi

# Step 2: Import ROADMAP.md
ROADMAP_FILE="$PLANNING_DIR/ROADMAP.md"
if [[ -f "$ROADMAP_FILE" ]]; then
  if [[ "$DRY_RUN" != true ]]; then
    bash "$SCRIPT_DIR/import-roadmap.sh" --file "$ROADMAP_FILE" --db "$DB" >/dev/null 2>&1 || true
  fi
  # Count phases from ROADMAP
  total_phases=$(grep -cE '^## Phase [0-9]+' "$ROADMAP_FILE" 2>/dev/null || echo "0")
fi

# Step 2b: Import REQUIREMENTS.md
REQS_FILE="$PLANNING_DIR/REQUIREMENTS.md"
if [[ -f "$REQS_FILE" ]] && [[ -f "$SCRIPT_DIR/import-requirements.sh" ]]; then
  if [[ "$DRY_RUN" != true ]]; then
    bash "$SCRIPT_DIR/import-requirements.sh" --file "$REQS_FILE" --db "$DB" >/dev/null 2>&1 || true
  fi
fi

# Step 3: For each phase directory, import all artifact files
PHASES_DIR="$PLANNING_DIR/phases"
if [[ -d "$PHASES_DIR" ]]; then
  for phase_dir in $(command ls -d "$PHASES_DIR"/*/ 2>/dev/null | sort); do
    phase_base=$(basename "$phase_dir")
    phase_num=${phase_base%%-*}
    # Strip leading zeros for display but keep for import
    phase_num_clean=$(echo "$phase_num" | sed 's/^0*//')
    [[ -z "$phase_num_clean" ]] && phase_num_clean="0"

    # 3a: Import plan files (NN-MM.plan.jsonl)
    for plan_file in "$phase_dir"*.plan.jsonl; do
      [[ -f "$plan_file" ]] || continue
      task_count=$(count_plan_tasks "$plan_file")
      total_plans=$((total_plans + 1))
      total_tasks=$((total_tasks + task_count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type plan --file "$plan_file" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    done

    # 3b: Import summary files (NN-MM.summary.jsonl)
    for summary_file in "$phase_dir"*.summary.jsonl; do
      [[ -f "$summary_file" ]] || continue
      total_summaries=$((total_summaries + 1))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type summary --file "$summary_file" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    done

    # 3c: Import critique.jsonl
    if [[ -f "$phase_dir/critique.jsonl" ]]; then
      count=$(count_lines "$phase_dir/critique.jsonl")
      total_critique=$((total_critique + count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type critique --file "$phase_dir/critique.jsonl" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    fi

    # 3d: Import research.jsonl
    if [[ -f "$phase_dir/research.jsonl" ]]; then
      count=$(count_lines "$phase_dir/research.jsonl")
      total_research=$((total_research + count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type research --file "$phase_dir/research.jsonl" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    fi

    # 3e: Import decisions.jsonl
    if [[ -f "$phase_dir/decisions.jsonl" ]]; then
      count=$(count_lines "$phase_dir/decisions.jsonl")
      total_decisions=$((total_decisions + count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type decisions --file "$phase_dir/decisions.jsonl" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    fi

    # 3f: Import escalation.jsonl
    if [[ -f "$phase_dir/escalation.jsonl" ]]; then
      count=$(count_lines "$phase_dir/escalation.jsonl")
      total_escalation=$((total_escalation + count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type escalation --file "$phase_dir/escalation.jsonl" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    fi

    # 3g: Import gaps.jsonl
    if [[ -f "$phase_dir/gaps.jsonl" ]]; then
      count=$(count_lines "$phase_dir/gaps.jsonl")
      total_gaps=$((total_gaps + count))
      if [[ "$DRY_RUN" != true ]]; then
        bash "$SCRIPT_DIR/import-jsonl.sh" --type gaps --file "$phase_dir/gaps.jsonl" --phase "$phase_num" --db "$DB" >/dev/null 2>&1 || true
      fi
    fi

    # 3h: Import verification.jsonl (not yet in import-jsonl.sh, use direct SQL)
    if [[ -f "$phase_dir/verification.jsonl" ]]; then
      count=$(count_lines "$phase_dir/verification.jsonl")
      total_verification=$((total_verification + count))
      if [[ "$DRY_RUN" != true ]]; then
        # verification.jsonl: line 1 = header, lines 2+ = checks
        linenum=0
        ver_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          linenum=$((linenum + 1))
          echo "$line" | jq empty 2>/dev/null || continue
          if [[ $linenum -eq 1 ]]; then
            tier=$(echo "$line" | jq -r '.tier // empty')
            r=$(echo "$line" | jq -r '.r // empty')
            ps=$(echo "$line" | jq -r '.ps // 0')
            fl=$(echo "$line" | jq -r '.fl // 0')
            tt=$(echo "$line" | jq -r '.tt // 0')
            dt=$(echo "$line" | jq -r '.dt // empty')
            tier_esc=${tier//\'/\'\'}
            r_esc=${r//\'/\'\'}
            dt_esc=${dt//\'/\'\'}
            ver_sql="INSERT OR REPLACE INTO verification (tier, r, ps, fl, tt, dt, phase) VALUES ('$tier_esc','$r_esc',${ps:-0},${fl:-0},${tt:-0},'$dt_esc','$phase_num');"
          else
            c=$(echo "$line" | jq -r '.c // empty')
            cr=$(echo "$line" | jq -r '.r // empty')
            ev=$(echo "$line" | jq -r '.ev // empty')
            cat_val=$(echo "$line" | jq -r '.cat // empty')
            c_esc=${c//\'/\'\'}
            cr_esc=${cr//\'/\'\'}
            ev_esc=${ev//\'/\'\'}
            cat_esc=${cat_val//\'/\'\'}
            ver_sql="$ver_sql
INSERT INTO verification_checks (verification_id, c, r, ev, cat) VALUES ((SELECT rowid FROM verification WHERE phase='$phase_num' ORDER BY rowid DESC LIMIT 1),'$c_esc','$cr_esc','$ev_esc','$cat_esc');"
          fi
        done < "$phase_dir/verification.jsonl"
        if [[ -n "$ver_sql" ]]; then
          sql_exec "$DB" "$ver_sql" 2>/dev/null || true
        fi
      fi
    fi

    # 3i: Import code-review.jsonl
    if [[ -f "$phase_dir/code-review.jsonl" ]]; then
      count=$(count_lines "$phase_dir/code-review.jsonl")
      total_code_review=$((total_code_review + count))
      if [[ "$DRY_RUN" != true ]]; then
        cr_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq empty 2>/dev/null || continue
          plan=$(echo "$line" | jq -r '.plan // empty')
          r=$(echo "$line" | jq -r '.r // empty')
          tdd=$(echo "$line" | jq -r '.tdd // empty')
          cycle=$(echo "$line" | jq -r '.cycle // 1')
          dt=$(echo "$line" | jq -r '.dt // empty')
          sg_rev=$(echo "$line" | jq -r '.sg_reviewed // 0')
          sg_pro=$(echo "$line" | jq -c '.sg_promoted // null')
          plan_esc=${plan//\'/\'\'}; r_esc=${r//\'/\'\'}; tdd_esc=${tdd//\'/\'\'}; dt_esc=${dt//\'/\'\'}; sg_pro_esc=${sg_pro//\'/\'\'}
          cr_sql="$cr_sql
INSERT INTO code_review (plan, r, tdd, cycle, dt, sg_reviewed, sg_promoted, phase) VALUES ('$plan_esc','$r_esc','$tdd_esc',${cycle:-1},'$dt_esc',${sg_rev:-0},'$sg_pro_esc','$phase_num');"
        done < "$phase_dir/code-review.jsonl"
        if [[ -n "$cr_sql" ]]; then
          sql_exec "$DB" "$cr_sql" 2>/dev/null || true
        fi
      fi
    fi

    # 3j: Import test-plan.jsonl
    if [[ -f "$phase_dir/test-plan.jsonl" ]]; then
      count=$(count_lines "$phase_dir/test-plan.jsonl")
      total_test_plan=$((total_test_plan + count))
      if [[ "$DRY_RUN" != true ]]; then
        tp_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq empty 2>/dev/null || continue
          id=$(echo "$line" | jq -r '.id // empty')
          tf=$(echo "$line" | jq -c '.tf // null')
          tc=$(echo "$line" | jq -r '.tc // 0')
          red=$(echo "$line" | jq -r '.red // 0')
          desc=$(echo "$line" | jq -r '.desc // empty')
          id_esc=${id//\'/\'\'}; tf_esc=${tf//\'/\'\'}; desc_esc=${desc//\'/\'\'}
          red_int=0; [[ "$red" == "true" ]] && red_int=1
          tp_sql="$tp_sql
INSERT INTO test_plan (id, tf, tc, red, \"desc\", phase) VALUES ('$id_esc','$tf_esc',${tc:-0},$red_int,'$desc_esc','$phase_num');"
        done < "$phase_dir/test-plan.jsonl"
        if [[ -n "$tp_sql" ]]; then
          sql_exec "$DB" "$tp_sql" 2>/dev/null || true
        fi
      fi
    fi

    # 3k: Import test-results.jsonl
    if [[ -f "$phase_dir/test-results.jsonl" ]]; then
      count=$(count_lines "$phase_dir/test-results.jsonl")
      total_test_results=$((total_test_results + count))
      if [[ "$DRY_RUN" != true ]]; then
        tr_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq empty 2>/dev/null || continue
          plan=$(echo "$line" | jq -r '.plan // empty')
          dept=$(echo "$line" | jq -r '.dept // empty')
          tdd_phase=$(echo "$line" | jq -r '.tdd_phase // empty')
          tc=$(echo "$line" | jq -r '.tc // 0')
          ps=$(echo "$line" | jq -r '.ps // 0')
          fl=$(echo "$line" | jq -r '.fl // 0')
          dt=$(echo "$line" | jq -r '.dt // empty')
          tasks=$(echo "$line" | jq -c '.tasks // null')
          plan_esc=${plan//\'/\'\'}; dept_esc=${dept//\'/\'\'}; tdd_esc=${tdd_phase//\'/\'\'}; dt_esc=${dt//\'/\'\'}; tasks_esc=${tasks//\'/\'\'}
          tr_sql="$tr_sql
INSERT INTO test_results (plan, dept, tdd_phase, tc, ps, fl, dt, tasks, phase) VALUES ('$plan_esc','$dept_esc','$tdd_esc',${tc:-0},${ps:-0},${fl:-0},'$dt_esc','$tasks_esc','$phase_num');"
        done < "$phase_dir/test-results.jsonl"
        if [[ -n "$tr_sql" ]]; then
          sql_exec "$DB" "$tr_sql" 2>/dev/null || true
        fi
      fi
    fi

    # 3l: Import qa-gate-results.jsonl (or .qa-gate-results.jsonl)
    qa_gate_file=""
    if [[ -f "$phase_dir/qa-gate-results.jsonl" ]]; then
      qa_gate_file="$phase_dir/qa-gate-results.jsonl"
    elif [[ -f "$phase_dir/.qa-gate-results.jsonl" ]]; then
      qa_gate_file="$phase_dir/.qa-gate-results.jsonl"
    fi
    if [[ -n "$qa_gate_file" ]]; then
      count=$(count_lines "$qa_gate_file")
      total_qa_gate=$((total_qa_gate + count))
      if [[ "$DRY_RUN" != true ]]; then
        qg_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq empty 2>/dev/null || continue
          gl=$(echo "$line" | jq -r '.gl // empty')
          r=$(echo "$line" | jq -r '.r // empty')
          plan=$(echo "$line" | jq -r '.plan // empty')
          task=$(echo "$line" | jq -r '.task // empty')
          tst=$(echo "$line" | jq -c '.tst // null')
          dur=$(echo "$line" | jq -r '.dur // 0')
          f=$(echo "$line" | jq -c '.f // null')
          mh=$(echo "$line" | jq -c '.mh // null')
          dt=$(echo "$line" | jq -r '.dt // empty')
          gl_esc=${gl//\'/\'\'}; r_esc=${r//\'/\'\'}; plan_esc=${plan//\'/\'\'}; task_esc=${task//\'/\'\'}
          tst_esc=${tst//\'/\'\'}; f_esc=${f//\'/\'\'}; mh_esc=${mh//\'/\'\'}; dt_esc=${dt//\'/\'\'}
          qg_sql="$qg_sql
INSERT INTO qa_gate_results (gl, r, plan, task, tst, dur, f, mh, dt, phase) VALUES ('$gl_esc','$r_esc','$plan_esc','$task_esc','$tst_esc',${dur:-0},'$f_esc','$mh_esc','$dt_esc','$phase_num');"
        done < "$qa_gate_file"
        if [[ -n "$qg_sql" ]]; then
          sql_exec "$DB" "$qg_sql" 2>/dev/null || true
        fi
      fi
    fi

    # 3m: Import security-audit.jsonl
    if [[ -f "$phase_dir/security-audit.jsonl" ]]; then
      count=$(count_lines "$phase_dir/security-audit.jsonl")
      total_security=$((total_security + count))
      if [[ "$DRY_RUN" != true ]]; then
        sa_sql=""
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq empty 2>/dev/null || continue
          r=$(echo "$line" | jq -r '.r // empty')
          findings=$(echo "$line" | jq -r '.findings // 0')
          critical=$(echo "$line" | jq -r '.critical // 0')
          dt=$(echo "$line" | jq -r '.dt // empty')
          r_esc=${r//\'/\'\'}; dt_esc=${dt//\'/\'\'}
          sa_sql="$sa_sql
INSERT INTO security_audit (r, findings, critical, dt, phase) VALUES ('$r_esc',${findings:-0},${critical:-0},'$dt_esc','$phase_num');"
        done < "$phase_dir/security-audit.jsonl"
        if [[ -n "$sa_sql" ]]; then
          sql_exec "$DB" "$sa_sql" 2>/dev/null || true
        fi
      fi
    fi
  done
fi

# Step 4: Import research-archive.jsonl
ARCHIVE_FILE="$PLANNING_DIR/research-archive.jsonl"
if [[ -f "$ARCHIVE_FILE" ]]; then
  total_archive=$(count_lines "$ARCHIVE_FILE")
  if [[ "$DRY_RUN" != true ]]; then
    bash "$SCRIPT_DIR/import-research-archive.sh" --file "$ARCHIVE_FILE" --db "$DB" >/dev/null 2>&1 || true
  fi
fi

# Step 5: Report
if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: $total_phases phases, $total_plans plans, $total_tasks tasks, $total_summaries summaries, $total_research research, $total_decisions decisions, $total_critique critique, $total_escalation escalation, $total_gaps gaps, $total_archive archive"
else
  echo "Migrated: $total_phases phases, $total_plans plans, $total_tasks tasks, $total_research research, $total_decisions decisions"
fi
