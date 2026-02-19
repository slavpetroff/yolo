# Architect Agent Memory

## Statusline Width Issue (REQ-10)
- Claude Code does NOT pass terminal width to statusline scripts
- $COLUMNS unavailable, tput cols always returns 80
- OSC 8 escape sequence bytes are counted as visible width (confirmed Claude Code issue #14011)
- Issue #5430 (closed as not planned) = no upstream fix coming
- Workaround: compute visible width by stripping ANSI+OSC8, use configurable max (default 120)
- ccstatusline tool uses stty on POSIX + 40-col safety buffer

## Project Structure
- 26 agents across 4 departments (Backend 7, Frontend 6, UI/UX 6, Shared 5)
- 11 base role archetypes: owner, architect, lead, senior, dev, tester, qa, qa-code, security, scout, critic/debugger
- review-ownership-patterns.md covers 16 reviewing agents only
- Shipped milestones: Workflow Hardening, Org Alignment, Teammate API (REQ-01 through REQ-09)

## Scoping Conventions
- Phases: 3-5 per milestone, independently testable, explicit dependencies
- Plans: 3-5 per phase maximum
- Success criteria: observable, measurable conditions
- Phase directories: .yolo-planning/phases/{NN}-{slug}/
- Always write decisions.jsonl in each phase dir during scoping
