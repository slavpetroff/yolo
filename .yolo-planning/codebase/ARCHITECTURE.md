# Architecture

## System Overview
YOLO is a Claude Code plugin providing structured development workflows (planning, execution, verification) via slash commands, specialized agents, and an MCP server.

## Components

### 1. Rust Binary (`yolo-mcp-server/`)
Dual-purpose binary: CLI tool (`yolo`) and MCP server (`yolo-mcp-server`).

- **CLI Router** (`src/cli/router.rs`) — 70+ subcommands dispatched by name
- **Commands** (`src/commands/`) — 70+ command implementations including: bootstrap, detect-stack, infer, state-update, planning-git, resolve-model, verify, statusline, token-baseline, delta-files, help-output, plus 6 QA/review commands (review-plan, verify-plan-completion, commit-lint, check-regression, diff-against-plan, validate-requirements)
- **Hooks** (`src/hooks/`) — 19 hook handlers across 11 event types: agent lifecycle (start/stop, health, compaction), security filter, message validation, schema validation, map-staleness, plus dispatcher and utilities
- **MCP Server** (`src/mcp/`) — JSON-RPC server exposing tools: compile_context, acquire_lock, release_lock, run_test_suite, request_human_approval
- **Telemetry** (`src/telemetry/`) — SQLite-backed usage tracking with measured metrics and event log

### MCP/CLI Hybrid Pattern

The binary operates in two modes:
- **CLI mode** (`yolo <command>`): Used by skills, hooks, and orchestrator scripts. Synchronous, file-based output. All 70+ commands available.
- **MCP mode** (`yolo` with no args, reads stdin): JSON-RPC 2.0 server for agent-initiated actions. 5 tools: compile_context, acquire_lock, release_lock, run_test_suite, request_human_approval.

**Tool ownership:**
| Tool | Mode | Why |
|------|------|-----|
| compile_context | Both (CLI primary) | CLI called by SKILL.md scripts; MCP version adds cache tracking + tier hashing |
| acquire_lock / release_lock | MCP | Agent-initiated concurrent file locking (22+ calls per phase) |
| run_test_suite | MCP | Agent-initiated test execution with auto-detection |
| request_human_approval | MCP | HITL workflow trigger |

**Cache prefix optimization:** The MCP compile_context computes SHA-256 hashes of Tier 1 and Tier 2 content. When a second agent requests context and the hash matches, it reports a cache hit. This enables Anthropic API prompt prefix caching — identical prefixes across agents are served from cache.

### 2. Plugin Definition (`.claude-plugin/`)
- `plugin.json` — Name, version (2.5.0), description, author
- `marketplace.json` — Discovery metadata

### 3. Slash Commands (`commands/`)
23 markdown-defined commands with frontmatter (name, category, allowed-tools, argument-hint). Key commands: init, vibe, map, status, config, verify, fix, debug, research, teach, skills, release, todo, help.

### 4. Agent Definitions (`agents/`)
8 agents (architect, debugger, dev, docs, lead, researcher, reviewer, qa). Each has role-specific tool access, protocols, and compiled context tiers.

- **Architect** — Roadmaps and phase structure (planning family)
- **Lead** — Planning orchestrator, decomposes phases into executable plans (planning family)
- **Dev** — Execution swarm agent with full tool access, atomic commits (execution family)
- **Debugger** — Scientific method bug hunting, read-only `plan` mode (execution family)
- **Docs** — Documentation specialist, manual-only spawn (execution family)
- **Researcher** — Internet + codebase research with WebFetch/WebSearch access (planning family)
- **Reviewer** — Adversarial plan critique and quality gate before execution, write-restricted (planning family)
- **QA** — Automated verification of code delivery against plans using Rust commands, write-restricted (execution family)

### 5. Hook Scripts (`hooks/`)
Lifecycle hooks for Claude Code PreToolUse/PostToolUse/SubagentStart/SessionStart events. `hooks.json` defines hook dispatch.

### 6. Reference Protocols (`references/`)
Execution protocol, effort profiles (fast/balanced/thorough/turbo), model profiles, verification protocol, handoff schemas, brand essentials.

### 7. Configuration (`config/`)
defaults.json, model-profiles.json, stack-mappings.json, token-budgets.json, rollout-stages.json, hooks.json.

## Data Flow
```
User → /yolo:command → Command Markdown → Orchestrator Agent
                                              ↓
                                    yolo CLI (Rust binary)
                                              ↓
                              .yolo-planning/ (state, plans, config)
                                              ↓
                                    MCP Server (tools)
```

### QA/Review CLI Commands

6 Rust-backed verification commands used by Reviewer and QA agents:

| Command | Purpose |
|---------|---------|
| `review-plan` | Automated plan quality checks (frontmatter, task count, file conflicts) |
| `verify-plan-completion` | Cross-references SUMMARY vs PLAN (task count, commit hashes) |
| `commit-lint` | Validates conventional commit format (`{type}({scope}): {description}`) |
| `check-regression` | Counts Rust and bats tests, flags regressions against baselines |
| `diff-against-plan` | Compares declared files in SUMMARY against actual git diff |
| `validate-requirements` | Checks must_haves from PLAN against evidence in SUMMARY and commits |

### Quality Gates

Config options in `.yolo-planning/config.json`:
- `review_gate` — When enabled, Reviewer agent must approve plans before execution proceeds
- `qa_gate` — When enabled, QA agent must pass verification before phase is marked complete

## Key Patterns
- **Phased workflow**: init → vibe (plan) → execute → verify → ship
- **Agent teams**: Lead plans, Architect designs, Dev executes, Reviewer gates plans, QA verifies delivery
- **MCP tools**: compile_context (stable/volatile split), acquire_lock, run_test_suite for agent coordination
- **Token budgets**: Per-role char limits with task-complexity multipliers
- **Planning artifacts**: .yolo-planning/ holds all state (config, roadmap, plans, phases)
