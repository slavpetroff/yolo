# Phase 4 UI/UX Context: Continuous QA System

## Vision
Transform QA from phase-end-only to continuous. Ensure QA gate feedback is clear, actionable, and well-formatted for CLI output.

## Department Requirements
- QA gate failure messages: clear, structured CLI output showing what failed and how to fix
- QA gate success messages: concise confirmation with metrics (tests passed, time)
- QA status in statusline: show current QA gate state during execution
- Error output follows yolo-brand-essentials.toon patterns (semantic symbols, no ANSI)
- Help text for new QA-related config options

## Constraints
- CLI-only project: no web UI, no graphical components
- Follow existing yolo-brand-essentials.toon conventions
- UX maps to help/error output patterns (not visual design)
- All output via echo/printf, no external formatting tools

## Integration Points
- Brand essentials: symbols for QA pass/fail/partial states
- Status output: gate results displayed during 11-step execution
- Error messages: actionable remediation instructions on gate failure
