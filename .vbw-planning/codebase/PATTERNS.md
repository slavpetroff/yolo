# Recurring Patterns

## P1: Hook Wrapper Pattern (DXP-01)

Every hook in hooks.json routes through `hook-wrapper.sh`:

```bash
bash -c 'w=$(ls -1 "$HOME"/.claude/plugins/cache/yolo-marketplace/yolo/*/scripts/hook-wrapper.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1) && [ -f "$w" ] && exec bash "$w" <target-script.sh>; exit 0'
```

The wrapper then:
1. Resolves the target script from the plugin cache (same ls|sort|tail pattern)
2. Passes stdin through to the target
3. Logs failures to `.hook-errors.log`
4. Always exits 0

**Occurrences**: 16 hook entries in hooks.json, all using this pattern.
**Rationale**: Graceful degradation -- no hook can ever break a session.

## P2: Plugin Cache Resolution

```bash
ls -1 "$CLAUDE_DIR"/plugins/cache/yolo-marketplace/yolo/*/scripts/<file> 2>/dev/null | sort -V | tail -1
```

Used everywhere a script needs to locate a file in the versioned plugin cache. The `sort -V` with fallback to numeric sort ensures the latest version is always selected.

**Occurrences**: hook-wrapper.sh, hooks.json (16x), session-start.sh, yolo-statusline.sh, init.md (statusline config)

## P3: Atomic JSON Update

```bash
jq '<mutation>' file.json > file.json.tmp && mv file.json.tmp file.json
```

Every JSON write follows this pattern -- write to temp, then atomic move. Prevents corruption from partial writes.

**Occurrences**: state-updater.sh, session-start.sh, config.md, suggest-next.sh, yolo-statusline.sh

## P4: Fail-Open / Fail-Closed Guards

Scripts declare their failure mode explicitly:
- **Fail-closed** (security-filter.sh): `exit 2` on any parse error. Never allows unvalidated input through.
- **Fail-open** (file-guard.sh, qa-gate.sh, all PostToolUse hooks): `exit 0` on any error. Never blocks legitimate work.

**Pattern**: Security hooks fail-closed; all other hooks fail-open.

## P5: jq Availability Guard

```bash
if ! command -v jq &>/dev/null; then
  # handle missing jq
  exit 0  # or exit 2 for security hooks
fi
```

Every script that uses jq checks for its presence first. Non-blocking hooks exit 0; blocking hooks exit 2.

**Occurrences**: security-filter.sh, session-start.sh, phase-detect.sh, validate-commit.sh, detect-stack.sh, yolo-statusline.sh, resolve-agent-model.sh

## P6: State Detection via Key-Value Output

`phase-detect.sh` outputs `key=value` pairs on stdout:
```
planning_dir_exists=true
project_exists=true
phase_count=3
next_phase_state=needs_execute
config_effort=balanced
```

Commands inject this output via template syntax and parse inline. This pre-computation pattern avoids redundant file reads across commands.

**Used by**: go.md, qa.md (Context section template injection)

## P7: Context-Aware Next Up Suggestions

`suggest-next.sh <command> [result]` reads project state from disk and outputs contextual suggestions:
```
-> Next Up
  /yolo:go -- Continue to Phase 2: Auth
  /yolo:map -- Codebase map is 45% stale
```

The script handles 12 command contexts (init, vibe, execute, plan, qa, fix, debug, config, archive, map, discuss, resume) with result-aware branching (pass/fail/partial).

**Called by**: Every command's output step.

## P8: Agent Model Resolution Chain

```
model_profile (quality|balanced|budget)
    |
    v
model-profiles.json (preset: agent -> model)
    |
    v
model_overrides.{agent} (per-agent override)
    |
    v
Final model (opus|sonnet|haiku)
```

`resolve-agent-model.sh` implements this resolution. Commands call it before spawning any agent and pass the result as `model: "${MODEL}"` to the Task tool.

**Occurrences**: go.md (Lead), execute-protocol.md (Dev, QA), qa.md (QA), debug.md (Debugger), fix.md (Dev)

## P9: Phase Banner + Metrics Block

Commands follow a consistent output structure:
```
Double-line box (Phase Banner)
  Result indicators (checkmarks/crosses/diamonds)
  Metrics Block (plans, effort, deviations, etc.)
  Next Up Block (from suggest-next.sh)
```

Defined in `references/yolo-brand-essentials.md`, implemented inline in each command's Output Format section.

## P10: Brownfield Detection

Two-stage detection used by init.md and phase-detect.sh:
1. Git repo check: `git ls-files --error-unmatch . | head -5`
2. Non-git fallback: Glob `**/*.*` excluding planning/config directories

Any match = BROWNFIELD=true. This gates codebase mapping, context inference, and GSD import flows.

## P11: Template-to-Script Pipeline

Bootstrap operations follow a consistent pattern:
1. Gather data (user input or inference)
2. Write temp JSON file
3. Call `scripts/bootstrap/bootstrap-{target}.sh OUTPUT_PATH [args]`
4. Script generates markdown from args
5. Clean up temp files

**Occurrences**: bootstrap-project.sh, bootstrap-requirements.sh, bootstrap-roadmap.sh, bootstrap-state.sh, bootstrap-claude.sh

## P12: Marker File Coordination

Lightweight inter-process coordination via touch/rm of marker files:
- `.active-agent` -- YOLO agent is running (agent-start.sh / agent-stop.sh)
- `.yolo-session` -- YOLO command is active (prompt-preflight.sh / session-stop.sh)
- `.gsd-isolation` -- GSD isolation enabled (init consent flow)
- `.compaction-marker` -- Compaction occurred (compaction-instructions.sh / session-start.sh cleanup)
- `.hook-errors.log` -- Hook failure log (hook-wrapper.sh)

**Used by**: security-filter.sh reads markers to determine access policy.

## P13: Tiered/Gated Behavior

Multiple features have effort-gated or autonomy-gated behavior:

| Feature | Gating Dimension | Levels |
|---------|-----------------|--------|
| Discovery questions | Profile depth | skip/quick/standard/thorough |
| QA verification | Effort | skip/quick/standard/deep |
| Plan approval | Autonomy x Effort | OFF/cautious+balanced/cautious+thorough |
| Teammate communication | Effort | none/blockers/blockers+findings/all |
| Scout model | Effort | haiku (fast/turbo) / inherit (thorough/balanced) |
| Auto-continue | Autonomy | STOP/STOP/STOP/auto-loop |

## P14: Platform-Aware Code

```bash
if [ "$(uname)" = "Darwin" ]; then
  mt=$(stat -f %m "$cf" 2>/dev/null || echo 0)
else
  mt=$(stat -c %Y "$cf" 2>/dev/null || echo 0)
fi
```

macOS vs Linux divergences handled inline where needed.

**Occurrences**: session-start.sh, yolo-statusline.sh (stat, security command)
