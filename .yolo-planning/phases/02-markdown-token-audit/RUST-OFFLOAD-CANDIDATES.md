# Rust Offload Candidates

Inventory of Markdown inline patterns that should be replaced by Rust CLI commands. Each candidate replaces repeated shell/jq code with a single `yolo <command>` call, reducing token count and eliminating copy-paste drift.

## P0 — Highest Impact

### 1. `yolo update-exec-state`

| Field | Value |
|-------|-------|
| **Location** | `skills/execute-protocol/SKILL.md` L95-110, L190-210, L214-230, L235-240, L642-655 |
| **Pattern** | 8x `jq '.key = val' state.json > tmp && mv tmp state.json` + interleaved `yolo log-event` calls |
| **Proposed command** | `yolo update-exec-state <plan-id> <key> <value> [--log-event <event-type> <fields...>]` |
| **Savings** | HIGH — eliminates ~80 tokens per invocation x8 = ~640 tokens per execution run |
| **Priority** | P0 |
| **Complexity** | Medium — state JSON mutation + optional log-event subsumption |

### 2. `yolo spawn-params`

| Field | Value |
|-------|-------|
| **Location** | `skills/execute-protocol/SKILL.md` L117-118, L401-403, L656; `commands/config.md` L54-57, L130-136, L153-168, L265, L334; `commands/fix.md` L26; `commands/debug.md` L50, L67; `commands/research.md` L28 |
| **Pattern** | Paired `resolve-model` + `resolve-turns` calls in 7+ files (2-6 lines each occurrence) |
| **Proposed command** | `yolo spawn-params <role> <effort> [--config <path>]` — returns JSON `{"model":"opus","max_turns":30,"effort":"balanced"}` |
| **Savings** | HIGH — 2 shell calls -> 1, repeated in 7+ files, ~50 tokens per pair x12+ occurrences |
| **Priority** | P0 |
| **Complexity** | Simple — wrapper around existing resolve-model + resolve-turns |

### 3. Plugin root resolution

| Field | Value |
|-------|-------|
| **Location** | 17/23 command files: `init.md` L16, `config.md` L12, `map.md` L13, `status.md` L12, `debug.md` L11, `fix.md` L11, `verify.md` L12, `vibe.md` L14, `discuss.md` L13, `todo.md` L13, `help.md` L12, `research.md` L12, `resume.md` L13, `whats-new.md` L12, `list-todos.md` L12, `teach.md` L13, `update.md` L12 |
| **Pattern** | 118-char shell expression: `${CLAUDE_PLUGIN_ROOT:-$(ls -1d ... \| sort -V \| tail -1)}` |
| **Proposed command** | `yolo plugin-root` or guaranteed `$CLAUDE_PLUGIN_ROOT` env injection via SessionStart hook |
| **Savings** | HIGH — 118 tokens x17 files = ~2006 tokens eliminated per session context load |
| **Priority** | P0 |
| **Complexity** | Simple — env var injection in hook or thin wrapper |

## P1 — High Impact

### 4. `yolo config-set`

| Field | Value |
|-------|-------|
| **Location** | `commands/config.md` L182, L188, L191, L194, L197, L298, L340, L343 |
| **Pattern** | 8x `jq '.key = val' config.json > tmp && mv tmp config.json` |
| **Proposed command** | `yolo config-set <key> <value> [--json]` |
| **Savings** | HIGH — eliminates 8 jq-tmp-mv blocks (~90 tokens each) = ~720 tokens |
| **Priority** | P1 |
| **Complexity** | Simple — JSON key-value write with atomic I/O (already have `atomic_io.rs`) |

### 5. `yolo diff-findings`

| Field | Value |
|-------|-------|
| **Location** | `skills/execute-protocol/SKILL.md` L130-156 |
| **Pattern** | 22-line jq block extracting delta findings (new + changed severity) between review cycles |
| **Proposed command** | `yolo diff-findings <current.json> <previous.json> [--min-severity medium]` |
| **Savings** | HIGH — 22 lines of complex jq -> 1 CLI call, ~200 tokens |
| **Priority** | P1 |
| **Complexity** | Medium — jq logic translation to Rust serde_json filtering |

### 6. `yolo size-codebase`

| Field | Value |
|-------|-------|
| **Location** | `commands/map.md` L39-50 |
| **Pattern** | Glob file counting with 11 exclusion patterns + tier selection table lookup |
| **Proposed command** | `yolo size-codebase [--package <dir>]` — returns JSON `{"file_count":450,"tier":"duo","scouts":2}` |
| **Savings** | HIGH — replaces multi-glob + conditional logic, ~120 tokens |
| **Priority** | P1 |
| **Complexity** | Simple — glob counting + threshold lookup |

### 7. `yolo detect-scenario`

| Field | Value |
|-------|-------|
| **Location** | `commands/init.md` L45-47, L52 (Steps 5-8 block) |
| **Pattern** | Brownfield/greenfield detection via git ls-files + glob + file type analysis |
| **Proposed command** | `yolo detect-scenario` — returns JSON `{"brownfield":true,"git":true,"file_types":["rs","md","sh"]}` |
| **Savings** | HIGH — replaces multi-command detection sequence, ~100 tokens |
| **Priority** | P1 |
| **Complexity** | Medium — multiple heuristics combined |

### 8. `yolo estimate-cost`

| Field | Value |
|-------|-------|
| **Location** | `commands/config.md` L138-148, L205, L215, L261, L276 |
| **Pattern** | 2x `get_model_cost()` shell function + arithmetic for 4-agent cost calculation |
| **Proposed command** | `yolo estimate-cost <profile> [--config <path>]` — returns JSON `{"total":X,"per_agent":{"lead":Y,...}}` |
| **Savings** | HIGH — eliminates inline shell function + 4 subshell cost calculations x2, ~150 tokens |
| **Priority** | P1 |
| **Complexity** | Simple — lookup table + arithmetic |

### 9. `yolo config-list-flags`

| Field | Value |
|-------|-------|
| **Location** | `commands/config.md` L72+ |
| **Pattern** | Feature flags rendering with 4-column table layout |
| **Proposed command** | `yolo config-list-flags [--format table\|json]` |
| **Savings** | MEDIUM — replaces flag enumeration + formatting, ~80 tokens |
| **Priority** | P1 |
| **Complexity** | Simple — config read + table formatting |

## P2 — Medium Impact

### 10. `yolo status-economy`

| Field | Value |
|-------|-------|
| **Location** | `commands/status.md` L51, L87 |
| **Pattern** | Multi-jq reads of `.cost-ledger.json` — per-agent costs, total, cache hit rate |
| **Proposed command** | `yolo status-economy` — returns structured JSON with agent costs, totals, cache stats |
| **Savings** | MEDIUM — replaces 3-4 jq reads with single call, ~100 tokens |
| **Priority** | P2 |
| **Complexity** | Simple — JSON aggregation |

### 11. `yolo release-audit`

| Field | Value |
|-------|-------|
| **Location** | `commands/release.md` L30-36 |
| **Pattern** | Pre-release checklist: git log parsing, changelog coverage check, README staleness detection |
| **Proposed command** | `yolo release-audit` — returns JSON `{"commits_since_release":N,"undocumented":[],"readme_stale":bool}` |
| **Savings** | MEDIUM — replaces 4 audit queries (git log, grep, ls+wc, comparison), ~120 tokens |
| **Priority** | P2 |
| **Complexity** | Medium — git log parsing + multi-file analysis |

## Summary

| Priority | Count | Total Token Savings | Complexity Mix |
|----------|-------|---------------------|----------------|
| P0 | 3 | ~3,300 tokens/session | 2 Simple, 1 Medium |
| P1 | 6 | ~1,460 tokens/session | 4 Simple, 2 Medium |
| P2 | 2 | ~220 tokens/session | 1 Simple, 1 Medium |
| **Total** | **11** | **~4,980 tokens/session** | **7 Simple, 4 Medium** |

## Implementation Notes

- P0 candidates share a pattern: high repetition count across many files. Fixing these first maximizes ROI.
- `spawn-params` (P0-2) is the simplest win — just wraps two existing commands.
- `plugin-root` (P0-3) may not need a new command — a SessionStart hook injecting `$CLAUDE_PLUGIN_ROOT` eliminates the pattern entirely.
- `update-exec-state` (P0-1) is the most complex — needs atomic JSON mutation + optional event logging in one call.
- All P1/P2 candidates already have `RUST-OFFLOAD` markers in execute-protocol/SKILL.md where applicable.
