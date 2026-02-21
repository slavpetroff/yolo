# YOLO Roadmap

**Goal:** YOLO

**Scope:** 2 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 3/3 | 12 | 12 |
| 2 | Complete | 1/1 | 4 | 2 |

---

## Phase List
- [x] [Phase 1: General Improvements](#phase-1-general-improvements)
- [x] [Phase 2: Fix Statusline](#phase-2-fix-statusline)

---

## Phase 1: General Improvements

**Goal:** Address open improvements, bug fixes, and enhancements across the YOLO plugin

**Requirements:** REQ-01, REQ-02, REQ-03, REQ-04, REQ-05

**Success Criteria:**
- All targeted improvements implemented and tested
- CI pipeline passes
- No regressions in existing functionality

**Dependencies:** None

---

## Phase 2: Fix Statusline

**Goal:** Rewrite the YOLO statusline to read stdin JSON from Claude Code, parse state files correctly, display context window/cost/model info, and add OAuth usage + git awareness — matching VBW statusline functionality

**Requirements:** REQ-06

**Success Criteria:**
- Statusline reads stdin JSON for context_window, cost, model data
- Phase/plans/progress parsed correctly from STATE.md or execution-state.json
- No Anthropic API calls for rate limits (uses OAuth usage endpoint instead)
- Model name comes from stdin JSON, not hardcoded
- Git branch and file change indicators displayed
- Multi-tier caching for OAuth and update checks
- All tests pass after rewrite

**Dependencies:** None

