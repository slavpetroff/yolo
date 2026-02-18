#!/usr/bin/env bats
# agent-persona-voice.bats -- Static tests verifying all 26 agent files have
# proper ## Persona & Voice sections per Phase 02 architecture requirements.
# Plan 02 TD4: section exists, non-empty, no old heading, subsections, no examples.

setup() {
  load '../test_helper/common'
}

# All 26 agent files under test
AGENT_FILES=(
  "agents/yolo-architect.md"
  "agents/yolo-lead.md"
  "agents/yolo-senior.md"
  "agents/yolo-dev.md"
  "agents/yolo-tester.md"
  "agents/yolo-qa.md"
  "agents/yolo-qa-code.md"
  "agents/yolo-owner.md"
  "agents/yolo-critic.md"
  "agents/yolo-scout.md"
  "agents/yolo-debugger.md"
  "agents/yolo-security.md"
  "agents/yolo-fe-architect.md"
  "agents/yolo-fe-lead.md"
  "agents/yolo-fe-senior.md"
  "agents/yolo-fe-dev.md"
  "agents/yolo-fe-tester.md"
  "agents/yolo-fe-qa.md"
  "agents/yolo-fe-qa-code.md"
  "agents/yolo-ux-architect.md"
  "agents/yolo-ux-lead.md"
  "agents/yolo-ux-senior.md"
  "agents/yolo-ux-dev.md"
  "agents/yolo-ux-tester.md"
  "agents/yolo-ux-qa.md"
  "agents/yolo-ux-qa-code.md"
)

# --- Helper: count non-blank lines in Persona & Voice section ---
# Reads lines after "## Persona & Voice" until the next "##" heading or EOF
persona_voice_content_lines() {
  local file="$1"
  local in_section=0
  local count=0
  while IFS= read -r line; do
    if [[ "$line" == "## Persona & Voice" ]]; then
      in_section=1
      continue
    fi
    if [ "$in_section" -eq 1 ]; then
      # Stop at next ## heading
      if [[ "$line" =~ ^## ]]; then
        break
      fi
      # Count non-blank lines
      if [[ -n "${line// /}" ]]; then
        count=$((count + 1))
      fi
    fi
  done < "$file"
  echo "$count"
}

# --- Test 1: All 26 agents have ## Persona & Voice section ---

@test "(1) all 26 agent files contain ## Persona & Voice section" {
  local missing=()
  for rel_path in "${AGENT_FILES[@]}"; do
    local file="$PROJECT_ROOT/$rel_path"
    if ! grep -q "^## Persona & Voice$" "$file" 2>/dev/null; then
      missing+=("$rel_path")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing ## Persona & Voice in:"
    for f in "${missing[@]}"; do echo "  $f"; done
    return 1
  fi
}

# --- Test 2: All sections are non-empty (4+ non-blank lines of content) ---

@test "(2) all ## Persona & Voice sections have at least 4 non-blank content lines" {
  local violations=()
  for rel_path in "${AGENT_FILES[@]}"; do
    local file="$PROJECT_ROOT/$rel_path"
    local count
    count=$(persona_voice_content_lines "$file")
    if [ "$count" -lt 4 ]; then
      violations+=("$rel_path (found $count non-blank lines)")
    fi
  done
  if [ "${#violations[@]}" -gt 0 ]; then
    echo "Insufficient content in ## Persona & Voice section:"
    for f in "${violations[@]}"; do echo "  $f"; done
    return 1
  fi
}

# --- Test 3: No agent file contains old ## Persona & Expertise heading ---

@test "(3) no agent file contains old ## Persona & Expertise heading" {
  local violations=()
  for rel_path in "${AGENT_FILES[@]}"; do
    local file="$PROJECT_ROOT/$rel_path"
    if grep -q "^## Persona & Expertise$" "$file" 2>/dev/null; then
      violations+=("$rel_path")
    fi
  done
  if [ "${#violations[@]}" -gt 0 ]; then
    echo "Old ## Persona & Expertise heading found in:"
    for f in "${violations[@]}"; do echo "  $f"; done
    return 1
  fi
}

# --- Test 4: All sections contain the four required bold subsection headers ---

@test "(4) all ## Persona & Voice sections contain the four required bold subsection headers" {
  local required_headers=(
    "**Professional Archetype**"
    "**Vocabulary Domains**"
    "**Communication Standards**"
    "**Decision-Making Framework**"
  )
  local violations=()

  for rel_path in "${AGENT_FILES[@]}"; do
    local file="$PROJECT_ROOT/$rel_path"
    # Extract section content between ## Persona & Voice and next ##
    local section_content
    section_content=$(awk '/^## Persona & Voice$/{found=1; next} found && /^## /{exit} found{print}' "$file" 2>/dev/null)

    for header in "${required_headers[@]}"; do
      if ! echo "$section_content" | grep -qF "$header"; then
        violations+=("$rel_path: missing $header")
      fi
    done
  done

  if [ "${#violations[@]}" -gt 0 ]; then
    echo "Missing required subsection headers:"
    for v in "${violations[@]}"; do echo "  $v"; done
    return 1
  fi
}

# --- Test 5: No sections contain example phrases or templates ---

@test "(5) no ## Persona & Voice sections contain example phrases or quoted speech templates" {
  # Patterns that indicate example phrasing (prescriptive language examples)
  local bad_patterns=(
    'say:'
    'example:'
    'e\.g\., "'
    '"I '
    '"We '
    '"As a '
  )
  local violations=()

  for rel_path in "${AGENT_FILES[@]}"; do
    local file="$PROJECT_ROOT/$rel_path"
    local section_content
    section_content=$(awk '/^## Persona & Voice$/{found=1; next} found && /^## /{exit} found{print}' "$file" 2>/dev/null)

    for pattern in "${bad_patterns[@]}"; do
      if echo "$section_content" | grep -qiE "$pattern"; then
        violations+=("$rel_path: matches pattern '$pattern'")
      fi
    done
  done

  if [ "${#violations[@]}" -gt 0 ]; then
    echo "Example phrases found in ## Persona & Voice sections:"
    for v in "${violations[@]}"; do echo "  $v"; done
    return 1
  fi
}
