#!/bin/bash
# detect-stack.sh — Detect project tech stack and recommend skills
# Called by /yolo:init Step 3 and /yolo:skills to avoid 50+ inline tool calls.
# Reads stack-mappings.json, checks project files, outputs JSON.
#
# Usage: bash detect-stack.sh [project-dir]
# Output: JSON object with detected stack, installed skills, and suggestions.

set -euo pipefail

# --- jq dependency check ---
if ! command -v jq &>/dev/null; then
  echo '{"error":"jq is required but not installed. Install: brew install jq (macOS) / apt install jq (Linux)"}' >&2
  exit 1
fi

PROJECT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAPPINGS="$SCRIPT_DIR/../config/stack-mappings.json"
PROJECT_TYPES="$SCRIPT_DIR/../config/project-types.json"

if [ ! -f "$MAPPINGS" ]; then
  echo '{"error":"stack-mappings.json not found"}' >&2
  exit 1
fi

# Check project-types.json availability (graceful fallback, no exit)
PROJECT_TYPES_AVAILABLE=true
if [ ! -f "$PROJECT_TYPES" ]; then
  PROJECT_TYPES_AVAILABLE=false
fi

# --- Collect installed skills ---
INSTALLED_GLOBAL=""
INSTALLED_PROJECT=""
INSTALLED_AGENTS=""
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -d "$CLAUDE_DIR/skills" ]; then
  INSTALLED_GLOBAL=$(command ls -1 "$CLAUDE_DIR/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
if [ -d "$PROJECT_DIR/.claude/skills" ]; then
  INSTALLED_PROJECT=$(command ls -1 "$PROJECT_DIR/.claude/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
if [ -d "$HOME/.agents/skills" ]; then
  INSTALLED_AGENTS=$(command ls -1 "$HOME/.agents/skills/" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
ALL_INSTALLED="$INSTALLED_GLOBAL,$INSTALLED_PROJECT,$INSTALLED_AGENTS"

# --- Read manifest files once ---
PKG_JSON=""
if [ -f "$PROJECT_DIR/package.json" ]; then
  PKG_JSON=$(<"$PROJECT_DIR/package.json")
fi

REQUIREMENTS_TXT=""
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
  REQUIREMENTS_TXT=$(<"$PROJECT_DIR/requirements.txt")
fi

PYPROJECT_TOML=""
if [ -f "$PROJECT_DIR/pyproject.toml" ]; then
  PYPROJECT_TOML=$(<"$PROJECT_DIR/pyproject.toml")
fi

GEMFILE=""
if [ -f "$PROJECT_DIR/Gemfile" ]; then
  GEMFILE=$(<"$PROJECT_DIR/Gemfile")
fi

CARGO_TOML=""
if [ -f "$PROJECT_DIR/Cargo.toml" ]; then
  CARGO_TOML=$(<"$PROJECT_DIR/Cargo.toml")
fi

GO_MOD=""
if [ -f "$PROJECT_DIR/go.mod" ]; then
  GO_MOD=$(<"$PROJECT_DIR/go.mod")
fi

# --- Check a single detect pattern ---
# Returns 0 (true) if pattern matches, 1 (false) if not.
check_pattern() {
  local pattern="$1"

  if echo "$pattern" | grep -qF ':'; then
    # Dependency pattern: "file:dependency"
    local file dep content
    file=$(echo "$pattern" | cut -d: -f1)
    dep=$(echo "$pattern" | cut -d: -f2-)

    case "$file" in
      package.json)   content="$PKG_JSON" ;;
      requirements.txt) content="$REQUIREMENTS_TXT" ;;
      pyproject.toml) content="$PYPROJECT_TOML" ;;
      Gemfile)        content="$GEMFILE" ;;
      Cargo.toml)     content="$CARGO_TOML" ;;
      go.mod)         content="$GO_MOD" ;;
      *)              content="" ;;
    esac

    if [ -n "$content" ] && echo "$content" | grep -qF "\"$dep\""; then
      return 0
    fi
    # Also check without quotes (requirements.txt, go.mod, etc.)
    if [ -n "$content" ] && echo "$content" | grep -qiw "$dep"; then
      return 0
    fi
    return 1
  else
    # File/directory pattern
    if [ -e "$PROJECT_DIR/$pattern" ]; then
      return 0
    fi
    return 1
  fi
}

# --- Iterate stack-mappings.json and check all entries ---
# Uses jq to extract entries, then checks each detect pattern in bash.
DETECTED=""
RECOMMENDED_SKILLS=""

# Extract all entries as flat lines: category|name|description|skills_csv|detect_csv
ENTRIES=$(jq -r '
  to_entries[] |
  select(.key | startswith("_") | not) |
  .key as $cat |
  .value | to_entries[] |
  [$cat, .key, (.value.description // .key), (.value.skills | join(";")), (.value.detect | join(";"))] |
  join("|")
' "$MAPPINGS" 2>/dev/null)

while IFS='|' read -r category name description skills_csv detect_csv; do
  [ -z "$name" ] && continue

  # Check each detect pattern
  matched=false
  IFS=';' read -ra patterns <<< "$detect_csv"
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    if check_pattern "$pattern"; then
      matched=true
      break
    fi
  done

  if [ "$matched" = true ]; then
    # Add to detected list
    if [ -n "$DETECTED" ]; then
      DETECTED="$DETECTED,$name"
    else
      DETECTED="$name"
    fi

    # Add recommended skills
    IFS=';' read -ra skill_list <<< "$skills_csv"
    for skill in ${skill_list[@]+"${skill_list[@]}"}; do
      if ! echo ",$RECOMMENDED_SKILLS," | grep -qF ",$skill,"; then
        if [ -n "$RECOMMENDED_SKILLS" ]; then
          RECOMMENDED_SKILLS="$RECOMMENDED_SKILLS,$skill"
        else
          RECOMMENDED_SKILLS="$skill"
        fi
      fi
    done
  fi
done <<< "$ENTRIES"

# --- Compute suggestions (recommended but not installed) ---
SUGGESTIONS=""
IFS=',' read -ra rec_arr <<< "$RECOMMENDED_SKILLS"
for skill in ${rec_arr[@]+"${rec_arr[@]}"}; do
  [ -z "$skill" ] && continue
  if ! echo ",$ALL_INSTALLED," | grep -qF ",$skill,"; then
    if [ -n "$SUGGESTIONS" ]; then
      SUGGESTIONS="$SUGGESTIONS,$skill"
    else
      SUGGESTIONS="$skill"
    fi
  fi
done

# --- Project Type Classification ---
# Uses parallel arrays for bash 3.2 compatibility (no associative arrays)
PROJECT_TYPE="generic"
TYPE_CONFIDENCE="low"

if [ "$PROJECT_TYPES_AVAILABLE" = true ]; then
  # Parallel arrays: TYPE_IDS[i], TYPE_PRI[i], TYPE_SCR[i]
  TYPE_IDS=()
  TYPE_PRI=()
  TYPE_SCR=()
  type_idx=0

  # Extract types as flat lines: id|priority|patterns_semicolon|weights_semicolon
  TYPE_ENTRIES=$(jq -r '
    .types[] |
    [.id, (.priority | tostring), ([.detect[].pattern] | join(";")), ([.detect[].weight | tostring] | join(";"))] |
    join("|")
  ' "$PROJECT_TYPES" 2>/dev/null)

  while IFS='|' read -r type_id type_priority patterns_csv weights_csv; do
    [ -z "$type_id" ] && continue
    TYPE_IDS[$type_idx]="$type_id"
    TYPE_PRI[$type_idx]="$type_priority"
    TYPE_SCR[$type_idx]=0

    # Skip generic (no detect signals)
    if [ -n "$patterns_csv" ]; then
      IFS=';' read -ra type_patterns <<< "$patterns_csv"
      IFS=';' read -ra type_weights <<< "$weights_csv"

      local_score=0
      for i in "${!type_patterns[@]}"; do
        pattern="${type_patterns[$i]}"
        weight="${type_weights[$i]:-1}"
        if check_pattern "$pattern"; then
          local_score=$((local_score + weight))
        fi
      done

      TYPE_SCR[$type_idx]=$local_score
    fi

    type_idx=$((type_idx + 1))
  done <<< "$TYPE_ENTRIES"

  # Find winner: highest score, ties broken by priority
  # Only types with score > 0 are candidates; fallback to generic if none scored
  best_type="generic"
  best_score=0
  best_priority=1
  runner_up_score=0

  for i in "${!TYPE_IDS[@]}"; do
    score=${TYPE_SCR[$i]}
    priority=${TYPE_PRI[$i]}

    # Skip zero-score types (generic is the default fallback)
    [ "$score" -eq 0 ] && continue

    if [ "$score" -gt "$best_score" ] || { [ "$score" -eq "$best_score" ] && [ "$priority" -gt "$best_priority" ]; }; then
      runner_up_score=$best_score
      best_type="${TYPE_IDS[$i]}"
      best_score=$score
      best_priority=$priority
    elif [ "$score" -gt "$runner_up_score" ]; then
      runner_up_score=$score
    fi
  done

  PROJECT_TYPE="$best_type"

  # Compute confidence
  if [ "$best_score" -eq 0 ]; then
    TYPE_CONFIDENCE="low"
  elif [ "$runner_up_score" -eq 0 ]; then
    TYPE_CONFIDENCE="high"
  elif [ "$best_score" -ge $((runner_up_score * 2)) ]; then
    TYPE_CONFIDENCE="high"
  elif [ "$best_score" -gt "$runner_up_score" ]; then
    TYPE_CONFIDENCE="medium"
  else
    TYPE_CONFIDENCE="low"
  fi

  # Monorepo: detect dominant sub-type
  if [ "$PROJECT_TYPE" = "monorepo" ]; then
    DOMINANT_SUBTYPE="generic"
    # Parallel arrays for sub-type counting
    SUB_NAMES=()
    SUB_COUNTS=()

    # Helper: increment sub-type count
    _inc_subtype() {
      local st="$1"
      local found=false
      for si in "${!SUB_NAMES[@]}"; do
        if [ "${SUB_NAMES[$si]}" = "$st" ]; then
          SUB_COUNTS[$si]=$(( ${SUB_COUNTS[$si]} + 1 ))
          found=true
          break
        fi
      done
      if [ "$found" = false ]; then
        SUB_NAMES+=("$st")
        SUB_COUNTS+=(1)
      fi
    }

    # Check for workspace packages
    for sub_dir in "$PROJECT_DIR"/packages/* "$PROJECT_DIR"/apps/* "$PROJECT_DIR"/libs/*; do
      [ ! -d "$sub_dir" ] && continue
      # Classify each sub-workspace
      if [ -f "$sub_dir/package.json" ]; then
        sub_pkg=$(<"$sub_dir/package.json")
        if echo "$sub_pkg" | grep -qF '"react"'; then
          _inc_subtype "web-app"
        elif echo "$sub_pkg" | grep -qF '"express"'; then
          _inc_subtype "api-service"
        else
          _inc_subtype "library"
        fi
      elif [ -f "$sub_dir/Cargo.toml" ]; then
        _inc_subtype "library"
      elif [ -f "$sub_dir/go.mod" ]; then
        _inc_subtype "api-service"
      fi
    done

    # Find dominant sub-type
    max_count=0
    for si in "${!SUB_NAMES[@]}"; do
      if [ "${SUB_COUNTS[$si]}" -gt "$max_count" ]; then
        max_count=${SUB_COUNTS[$si]}
        DOMINANT_SUBTYPE="${SUB_NAMES[$si]}"
      fi
    done

    # Default to web-app if no sub-workspaces detected
    if [ "$max_count" -eq 0 ]; then
      DOMINANT_SUBTYPE="web-app"
    fi
  fi
fi

# --- Check find-skills availability ---
FIND_SKILLS="false"
if [ -d "$CLAUDE_DIR/skills/find-skills" ] || [ -d "$HOME/.agents/skills/find-skills" ]; then
  FIND_SKILLS="true"
fi

# --- Output JSON ---
jq -n \
  --arg detected "$DETECTED" \
  --arg installed_global "$INSTALLED_GLOBAL" \
  --arg installed_project "$INSTALLED_PROJECT" \
  --arg installed_agents "$INSTALLED_AGENTS" \
  --arg recommended "$RECOMMENDED_SKILLS" \
  --arg suggestions "$SUGGESTIONS" \
  --argjson find_skills "$FIND_SKILLS" \
  --arg project_type "$PROJECT_TYPE" \
  --arg type_confidence "$TYPE_CONFIDENCE" \
  '{
    detected_stack: ($detected | split(",") | map(select(. != ""))),
    installed: {
      global: ($installed_global | split(",") | map(select(. != ""))),
      project: ($installed_project | split(",") | map(select(. != ""))),
      agents: ($installed_agents | split(",") | map(select(. != "")))
    },
    recommended_skills: ($recommended | split(",") | map(select(. != ""))),
    suggestions: ($suggestions | split(",") | map(select(. != ""))),
    find_skills_available: $find_skills,
    project_type: $project_type,
    type_confidence: $type_confidence
  }'
