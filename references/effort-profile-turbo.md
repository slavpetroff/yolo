# Turbo Profile (EFRT-04)

**Model:** Sonnet | **Use when:** Quick fixes, config changes, obvious tasks, low-stakes edits.

## Matrix Row

| Agent | Level | Notes |
|-------|-------|-------|
| Lead | skip | Not spawned. No planning step |
| Architect | skip | Not spawned |
| Dev | low | Direct execution, no research, minimal change, brief commits |
| QA | skip | Not spawned. User judges output directly |
| Scout | skip | Not spawned |
| Debugger | low | Single hypothesis, targeted fix, minimal report (root cause + fix) |

## Plan Approval (EFRT-07)

| Autonomy | Gate |
|----------|------|
| All levels | OFF |

No lead agent at Turbo; plan approval requires a lead.

## Effort Parameter Mapping

| Level | Behavior |
|-------|----------|
| low | Minimal reasoning, direct execution |
| skip | Agent is not spawned at all |

Per-invocation override: `--effort=turbo` overrides config default for one invocation (EFRT-05).
