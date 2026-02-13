#!/usr/bin/env bash
# suggest-next.sh — Context-aware Next Up suggestions (ADP-03)
#
# Usage: suggest-next.sh <command> [result]
#   command: the YOLO command that just ran (implement, qa, plan, execute, fix, etc.)
#   result:  optional outcome (pass, fail, partial, complete, skipped)
#
# Output: Formatted ➜ Next Up block with 2-3 contextual suggestions.
# Called by commands during their output step.
#
# Context detection (all from disk, no extra args needed):
#   - Phase state: next unplanned/unbuilt phase, all-done
#   - Plan count: number of PLAN.md files in active phase
#   - Effort level: from config.json
#   - Deviations: summed from SUMMARY.md frontmatter in active phase
#   - Failing plans: SUMMARY.md files with status != complete
#   - Map staleness: percentage from META.md git hash comparison
#   - Phase name: human-readable slug from directory name

set -eo pipefail

CMD="${1:-}"
RESULT="${2:-}"
PLANNING_DIR=".yolo-planning"

# --- State detection ---
has_planning=false
has_project=false
phase_count=0
next_unplanned=""
next_unbuilt=""
all_done=false
last_qa_result=""
map_exists=false

# Contextual state (ADP-03)
effort="balanced"
active_phase_dir=""
active_phase_num=""
active_phase_name=""
active_phase_plans=0
deviation_count=0
failing_plan_ids=""
map_staleness=-1

if [ -d "$PLANNING_DIR" ]; then
  has_planning=true

  # Resolve phases directory (milestone-aware)
  PHASES_DIR="$PLANNING_DIR/phases"
  if [ -f "$PLANNING_DIR/ACTIVE" ]; then
    ACTIVE=$(tr -d '[:space:]' < "$PLANNING_DIR/ACTIVE")
    if [ -d "$PLANNING_DIR/milestones/$ACTIVE/phases" ]; then
      PHASES_DIR="$PLANNING_DIR/milestones/$ACTIVE/phases"
    fi
  fi

  # Check PROJECT.md exists and isn't template
  if [ -f "$PLANNING_DIR/PROJECT.md" ] && ! grep -q '{project-name}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    has_project=true
  fi

  # Read effort from config
  if [ -f "$PLANNING_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
    # Auto-migrate: add model_profile if missing
    if ! jq -e '.model_profile' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' "$PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$PLANNING_DIR/config.json"
    fi
    e=$(jq -r '.effort // "balanced"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ -n "$e" ] && [ "$e" != "null" ] && effort="$e"
  fi

  # Scan phases
  if [ -d "$PHASES_DIR" ]; then
    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      phase_count=$((phase_count + 1))
      phase_num=$(basename "$dir" | sed 's/[^0-9].*//')
      phase_slug=$(basename "$dir" | sed 's/^[0-9]*-//')

      plans=$(find "$dir" -maxdepth 1 \( -name '*.plan.jsonl' -o -name '*-PLAN.md' \) 2>/dev/null | wc -l | tr -d ' ')
      summaries=$(find "$dir" -maxdepth 1 \( -name '*.summary.jsonl' -o -name '*-SUMMARY.md' \) 2>/dev/null | wc -l | tr -d ' ')

      if [ "$plans" -eq 0 ] && [ -z "$next_unplanned" ]; then
        next_unplanned="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans=0
      elif [ "$plans" -gt 0 ] && [ "$summaries" -lt "$plans" ] && [ -z "$next_unbuilt" ]; then
        next_unbuilt="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans="$plans"
      fi

      # Track the last phase as fallback active phase
      last_phase_dir="$dir"
      last_phase_num="$phase_num"
      last_phase_name="$phase_slug"
      last_phase_plans="$plans"
    done

    # If no unplanned/unbuilt, use the last phase (most recently completed)
    if [ -z "$active_phase_dir" ] && [ -n "$last_phase_dir" ]; then
      active_phase_dir="$last_phase_dir"
      active_phase_num="$last_phase_num"
      active_phase_name="$last_phase_name"
      active_phase_plans="$last_phase_plans"
    fi

    # All done if phases exist and nothing is unplanned/unbuilt
    if [ "$phase_count" -gt 0 ] && [ -z "$next_unplanned" ] && [ -z "$next_unbuilt" ]; then
      all_done=true
    fi

    # Find most recent QA result (JSONL or legacy MD)
    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      # Check JSONL verification
      if [ -f "$dir/verification.jsonl" ] && command -v jq >/dev/null 2>&1; then
        r=$(head -1 "$dir/verification.jsonl" | jq -r '.r // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        [ -n "$r" ] && last_qa_result="$r"
      fi
      # Check legacy VERIFICATION.md
      for vf in "$dir"/*-VERIFICATION.md; do
        [ -f "$vf" ] || continue
        r=$(grep -m1 '^result:' "$vf" 2>/dev/null | sed 's/result:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
        [ -n "$r" ] && last_qa_result="$r"
      done
    done

    # Count deviations and find failing plans in active phase
    if [ -n "$active_phase_dir" ] && [ -d "$active_phase_dir" ]; then
      # Check JSONL summaries
      for sf in "$active_phase_dir"/*.summary.jsonl; do
        [ -f "$sf" ] || continue
        if command -v jq >/dev/null 2>&1; then
          d=$(jq -r '.dv // [] | length' "$sf" 2>/dev/null || echo 0)
          deviation_count=$((deviation_count + d))
          s=$(jq -r '.s // "complete"' "$sf" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
          if [ "$s" = "failed" ] || [ "$s" = "partial" ]; then
            plan_id=$(basename "$sf" | sed 's/\.summary\.jsonl//')
            failing_plan_ids="${failing_plan_ids:+$failing_plan_ids }$plan_id"
          fi
        fi
      done
      # Check legacy SUMMARY.md files
      for sf in "$active_phase_dir"/*-SUMMARY.md; do
        [ -f "$sf" ] || continue
        d=$(grep -m1 '^deviations:' "$sf" 2>/dev/null | sed 's/deviations:[[:space:]]*//' || true)
        case "$d" in
          0|"[]"|"") ;;
          [0-9]*) deviation_count=$((deviation_count + d)) ;;
          *) deviation_count=$((deviation_count + 1)) ;;
        esac
        s=$(grep -m1 '^status:' "$sf" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
        if [ "$s" = "failed" ] || [ "$s" = "partial" ]; then
          plan_id=$(basename "$sf" | sed 's/-SUMMARY.md//')
          failing_plan_ids="${failing_plan_ids:+$failing_plan_ids }$plan_id"
        fi
      done
    fi
  fi

  # Check map staleness (not just existence)
  if [ -d "$PLANNING_DIR/codebase" ]; then
    map_exists=true
    META="$PLANNING_DIR/codebase/META.md"
    if [ -f "$META" ] && git rev-parse --git-dir >/dev/null 2>&1; then
      git_hash=$(grep '^git_hash:' "$META" 2>/dev/null | awk '{print $2}' || true)
      file_count=$(grep '^file_count:' "$META" 2>/dev/null | awk '{print $2}' || true)
      if [ -n "$git_hash" ] && [ -n "$file_count" ] && [ "$file_count" -gt 0 ] 2>/dev/null; then
        if git cat-file -e "$git_hash" 2>/dev/null; then
          changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')
          map_staleness=$((changed * 100 / file_count))
        else
          map_staleness=100
        fi
      fi
    fi
  fi
fi

# Use explicit result if provided, fall back to detected QA result
effective_result="${RESULT:-$last_qa_result}"

# Format phase name for display (replace hyphens with spaces)
fmt_phase_name() {
  echo "$1" | tr '-' ' '
}

# --- Output ---
echo "➜ Next Up"

suggest() {
  echo "  $1"
}

case "$CMD" in
  init)
    suggest "/yolo:go -- Define your project and start building"
    ;;

  vibe|implement|execute)
    case "$effective_result" in
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/yolo:fix -- Fix plan $first_fail (failed verification)"
        else
          suggest "/yolo:fix -- Fix the failing checks"
        fi
        suggest "/yolo:qa -- Re-run verification after fixing"
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/yolo:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/yolo:fix -- Address partial failures"
        fi
        if [ "$all_done" != true ]; then
          suggest "/yolo:go -- Continue to next phase"
        fi
        ;;
      *)
        if [ "$all_done" = true ]; then
          if [ "$deviation_count" -eq 0 ]; then
            suggest "/yolo:go --archive -- All phases complete, zero deviations"
          else
            suggest "/yolo:go --archive -- Archive completed work ($deviation_count deviation(s) logged)"
            suggest "/yolo:qa -- Review before archiving"
          fi
        elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$active_phase_name" ] && [ "$target" != "$active_phase_num" ]; then
            # Next phase is different from active — show its name
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/yolo:go -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/yolo:go -- Continue to next phase"
          fi
        fi
        if [ "$RESULT" = "skipped" ]; then
          suggest "/yolo:qa -- Verify completed work"
        fi
        ;;
    esac
    ;;

  plan)
    if [ "$active_phase_plans" -gt 0 ]; then
      suggest "/yolo:go -- Execute $active_phase_plans plans ($effort effort)"
    else
      suggest "/yolo:go -- Execute the planned phase"
    fi
    ;;

  qa)
    case "$effective_result" in
      pass)
        if [ "$all_done" = true ]; then
          if [ "$deviation_count" -eq 0 ]; then
            suggest "/yolo:go --archive -- All phases complete, zero deviations"
          else
            suggest "/yolo:go --archive -- Archive completed work ($deviation_count deviation(s) logged)"
          fi
        else
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/yolo:go -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/yolo:go -- Continue to next phase"
          fi
        fi
        ;;
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/yolo:fix -- Fix plan $first_fail (failed QA)"
        else
          suggest "/yolo:fix -- Fix the failing checks"
        fi
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/yolo:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/yolo:fix -- Address partial failures"
        fi
        suggest "/yolo:go -- Continue despite warnings"
        ;;
      *)
        suggest "/yolo:go -- Continue building"
        ;;
    esac
    ;;

  fix)
    suggest "/yolo:qa -- Verify the fix"
    suggest "/yolo:go -- Continue building"
    ;;

  debug)
    suggest "/yolo:fix -- Apply the fix"
    suggest "/yolo:go -- Continue building"
    ;;

  config)
    if [ "$has_project" = true ]; then
      suggest "/yolo:status -- View project state"
    else
      suggest "/yolo:go -- Define your project and start building"
    fi
    ;;

  archive)
    suggest "/yolo:go -- Start new work"
    ;;

  status)
    if [ "$all_done" = true ]; then
      if [ "$deviation_count" -eq 0 ]; then
        suggest "/yolo:go --archive -- All phases complete, zero deviations"
      else
        suggest "/yolo:go --archive -- Archive completed work"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      for dir in "$PHASES_DIR"/*/; do
        [ -d "$dir" ] || continue
        pn=$(basename "$dir" | sed 's/[^0-9].*//')
        if [ "$pn" = "$target" ]; then
          tname=$(basename "$dir" | sed 's/^[0-9]*-//')
          suggest "/yolo:go -- Continue Phase $target: $(fmt_phase_name "$tname")"
          break
        fi
      done
    else
      suggest "/yolo:go -- Start building"
    fi
    ;;

  map)
    suggest "/yolo:go -- Start building"
    suggest "/yolo:status -- View project state"
    ;;

  discuss|assumptions)
    suggest "/yolo:go --plan -- Plan this phase"
    suggest "/yolo:go -- Plan and execute in one flow"
    ;;

  resume)
    suggest "/yolo:go -- Continue building"
    suggest "/yolo:status -- View current progress"
    ;;

  *)
    # Fallback for help, whats-new, update, etc.
    if [ "$has_project" = true ]; then
      suggest "/yolo:go -- Continue building"
      suggest "/yolo:status -- View project progress"
    else
      suggest "/yolo:go -- Start a new project"
    fi
    ;;
esac

# Map staleness hint (skip for map/init/help commands)
case "$CMD" in
  map|init|help|update|whats-new|uninstall) ;;
  *)
    if [ "$has_project" = true ] && [ "$phase_count" -gt 0 ]; then
      if [ "$map_exists" = false ]; then
        suggest "/yolo:map -- Map your codebase for better planning"
      elif [ "$map_staleness" -gt 30 ]; then
        suggest "/yolo:map --incremental -- Codebase map is ${map_staleness}% stale"
      fi
    fi
    ;;
esac
