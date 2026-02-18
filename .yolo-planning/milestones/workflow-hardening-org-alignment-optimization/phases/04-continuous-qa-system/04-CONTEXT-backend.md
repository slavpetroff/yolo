# Phase 4 Backend Context: Continuous QA System

## Vision
Transform QA from phase-end-only to continuous. Add QA gates at post-task, post-plan, and post-phase levels matching real company QA processes.

## Department Requirements
- Post-task QA gate: runs unit tests after each Senior-approved batch
- Post-plan QA gate: runs integration verification after plan completion
- Post-phase QA gate: runs full system verification (existing behavior, formalized)
- QA failures block progression at each level
- QA agent prompts (yolo-qa.md, yolo-qa-code.md) updated for continuous operation
- Integrate with existing test-summary.sh infrastructure
- Priority: post-task gate first (catches issues earliest)

## Constraints
- Zero-dependency design: no npm, no package.json
- All scripts target bash, not POSIX sh
- Use jq for all JSON parsing
- Build on existing test-summary.sh, qa-gate.sh, validate-gates.sh
- QA gates must not break existing 11-step workflow — additive only
- Post-task gate must work in both team_mode=task and team_mode=teammate

## Integration Points
- execute-protocol.md Step 7 (implementation): post-task gate hooks
- execute-protocol.md Step 9 (QA): formalized post-phase gate
- qa-gate.sh: existing QA script to extend
- test-summary.sh: existing test runner to integrate with
- Phase 3 metric collection hooks: instrument at observation points
