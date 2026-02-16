# Phase 3 Context: Token Optimization & Context Packages

## User Vision
Reduce token overhead per phase execution by offloading more LLM work to shell scripts, reorganize references into self-contained department packages, and adapt agent tool permissions based on detected project type.

## Essential Features
- At least 3 new validation/generation scripts that replace work currently done by LLM (REQ-04)
- Department references reorganized into self-contained packages (REQ-05)
- Agent tool permissions adapt to detected project type (REQ-06)
- Measurable token reduction per phase execution

## Technical Preferences
- Shell scripts (bash), no external dependencies (zero-dependency design)
- jq for all JSON parsing
- BATS for testing
- Existing patterns: compile-context.sh, detect-stack.sh, generate-department-toons.sh
- Project type config in config/project-types.json (7 types from Phase 1)

## Boundaries
- No runtime project type switching
- No cross-project learning
- Must preserve backward compatibility with existing workflows
- All existing tests must continue to pass (606 regression baseline)

## Acceptance Criteria
- Token usage per phase execution measurably reduced
- Each agent loads only its department package, not full reference tree
- Agent YAML files have project-type-specific tool restrictions
- At least 3 scripts replace LLM work (validation, artifact generation, context compilation)

## Decisions Made
- compile-context.sh already handles per-role context compilation (Phase 1)
- Department TOON templates already generate per-project-type (Phase 1)
- File-based coordination scripts already offload orchestration work (Phase 2)

## Dependencies
- Phase 1 outputs: detect-stack.sh, generate-department-toons.sh, project-types.json, department templates
- Phase 2 outputs: dept-orchestrate.sh, dept-status.sh, dept-gate.sh, dept-cleanup.sh
