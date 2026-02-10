# Balanced Profile (EFRT-02)

**Model:** Opus | **Use when:** Standard development work, most phases. The recommended default.

## Matrix Row

| Agent | Level | Notes |
|-------|-------|-------|
| Lead | high | Solid research, clear decomposition, coverage+feasibility self-review |
| Architect | high | Complete scope, clear criteria, standard dependency justification |
| Dev | medium | Focused implementation, standard verification, concise commits |
| QA | medium | Standard tier (15-25 checks). Content structure, key links, conventions |
| Scout | medium | Targeted research, one source per finding. Runs on session model (Opus) |
| Debugger | medium | Focused investigation, rank-order hypotheses, stop on confirmation |

## Plan Approval (EFRT-07)

| Autonomy | Gate |
|----------|------|
| cautious | required |
| standard | OFF |
| confident / pure-vibe | OFF |

## Effort Parameter Mapping

| Level | Behavior |
|-------|----------|
| high | Deep reasoning with focused scope |
| medium | Moderate reasoning depth, standard exploration |

Per-invocation override: `--effort=balanced` overrides config default for one invocation (EFRT-05).
