# Agent Routing & Release Automation Roadmap

**Goal:** Fix two workflow issues: (1) execute-protocol spawns generic `general-purpose` agents instead of specialized agents (yolo-dev, yolo-architect) — losing tool constraints, turn limits, and role isolation; (2) archive flow has no consolidated release step — version bump, changelog finalization, and release tagging are done manually in a dedicated phase instead of automatically on milestone complete.

**Scope:** 3 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|----------|
| 1 | Complete | 2 | 6 | 5 |
| 2 | Complete | 1 | 3 | 2 |
| 3 | Pending | — | — | — |

---

## Phase List
- [x] [Phase 1: Specialized Agent Routing](#phase-1-specialized-agent-routing)
- [x] [Phase 2: Archive Release Automation](#phase-2-archive-release-automation)
- [ ] [Phase 3: Testing & Release](#phase-3-testing--release)

---

## Phase 1: Specialized Agent Routing

**Goal:** Fix all Task tool spawn points in execute-protocol SKILL.md to pass `subagent_type` so that specialized agents with proper tool constraints, turn limits, and permission modes are used instead of generic general-purpose agents.

**Success Criteria:**
- Step 3 Dev spawning includes `subagent_type: "yolo:yolo-dev"` in TaskCreate
- Step 2b Architect spawning (review feedback loop) includes `subagent_type: "yolo:yolo-architect"` in TaskCreate
- Step 3d Dev spawning (QA remediation loop) includes `subagent_type: "yolo:yolo-dev"` in TaskCreate
- Each spawn point passes `model` and `max_turns` from resolve-model/resolve-turns to the Task tool
- Agent frontmatter (tools, disallowedTools, permissionMode, maxTurns) is respected by the platform when subagent_type is set
- Document the subagent_type mapping table in execute-protocol (role → subagent_type)
- All existing tests pass

**Dependencies:** None

---

## Phase 2: Archive Release Automation

**Goal:** Add a consolidated release step to archive.md so that on milestone complete, version is automatically bumped, changelog finalized, release committed, tagged, and optionally pushed — eliminating the need for a manual release phase.

**Success Criteria:**
- New Step 5c in archive.md invokes release automation after archive commit
- Version bump via `yolo bump-version` (patch by default)
- CHANGELOG.md `[Unreleased]` section finalized with new version + date
- Release commit: `chore: release v{version}`
- Git tag: `v{version}` (in addition to existing milestone tag)
- Push gated by `auto_push` config (`never` → skip, `always` → push, `after_phase` → push)
- `--no-release` flag on archive to skip release step entirely
- `--major` / `--minor` flags forwarded to bump-version
- Existing archive steps (audit, move, milestone tag, ACTIVE update) remain intact
- Release step runs AFTER milestone tag but BEFORE ACTIVE update

**Dependencies:** Phase 1

---

## Phase 3: Testing & Release

**Goal:** Add tests for both fixes, update documentation, and bump version.

**Success Criteria:**
- Bats tests verifying `subagent_type` appears in execute-protocol spawn blocks
- Bats tests verifying archive.md contains release automation step
- README.md updated with agent routing and auto-release documentation
- CHANGELOG.md updated with v2.8.0 entry
- Version bumped to 2.8.0
- All existing + new tests pass

**Dependencies:** Phase 2
