# YOLO Roadmap

**Goal:** Dynamic Departments, Agent Teams & Token Optimization

**Scope:** 3 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 1 | Complete | 4 | 13 | 16 |
| 2 | Complete | 3 | 11 | 15 |
| 3 | Pending | 0 | 0 | 0 |

---

## Phase List
- [x] [Phase 1: Project Type Detection & Persona Templates](#phase-1-project-type-detection-persona-templates)
- [x] [Phase 2: Agent Teams Integration](#phase-2-agent-teams-integration)
- [ ] [Phase 3: Token Optimization & Context Packages](#phase-3-token-optimization-context-packages)

---

## Phase 1: Project Type Detection & Persona Templates

**Goal:** Enhance detect-stack.sh to classify project types and generate department TOON files dynamically based on detected type

**Requirements:** REQ-01, REQ-02, REQ-07

**Success Criteria:**
- detect-stack.sh outputs project_type classification
- New generate-department-toons.sh creates per-type department protocols
- UX department maps to project interface type (CLI/web/API/library)
- YOLO project itself gets correct shell-project personas

**Dependencies:** None

---

## Phase 2: Agent Teams Integration

**Goal:** Replace Task-only spawning with Teammate API for multi-dept mode — one team per department with parallel execution

**Requirements:** REQ-03

**Success Criteria:**
- Multi-dept execution uses file-based coordination with background Task subagents
- Department Leads spawn as background agents with sentinel file handoffs
- Coordination via .dept-status-{dept}.json with flock locking
- 3 departments can run in parallel with gate-based synchronization
- Cleanup via dept-cleanup.sh removes coordination files safely

**Dependencies:** Phase 1

---

## Phase 3: Token Optimization & Context Packages

**Goal:** Offload more LLM work to scripts, reorganize references into department packages, adapt agent tool permissions per project type

**Requirements:** REQ-04, REQ-05, REQ-06

**Success Criteria:**
- At least 3 new validation/generation scripts replace LLM work
- Department references reorganized into self-contained packages
- Agent tool permissions adapt to detected project type
- Measurable token reduction per phase execution

**Dependencies:** Phase 1

