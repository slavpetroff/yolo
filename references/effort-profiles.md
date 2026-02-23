# Effort Profiles

## Effort vs Model Profile

**Effort controls:** Planning depth, verification thoroughness, research scope (workflow behavior)
**Model profile controls:** Which Claude model each agent uses (cost optimization)

These are independent settings. You can run Thorough effort on Budget profile (deep workflow, cheap models) or Fast effort on Quality profile (quick workflow, expensive models). Most users: match them (balanced+balanced, thorough+quality, fast+budget).

Configure via:

- Effort: `/yolo:config effort <level>` or `/yolo:vibe --effort=<level>`
- Model: `/yolo:config model_profile <profile>`

See: @references/model-profiles.md for model profile details.

---

## Plan Approval by Profile (EFRT-07)

| Profile  | cautious | standard | confident / pure-vibe |
| -------- | -------- | -------- | --------------------- |
| Thorough | required | required | OFF                   |
| Balanced | required | OFF      | OFF                   |
| Fast     | OFF      | OFF      | OFF                   |
| Turbo    | OFF      | OFF      | OFF                   |

Platform-enforced: Dev cannot write files until lead approves. No lead agent at Turbo; plan approval requires a lead.

## Effort Parameter Mapping

| Level  | Behavior                                       |
| ------ | ---------------------------------------------- |
| max    | No effort override (default maximum reasoning) |
| high   | Deep reasoning with focused scope              |
| medium | Moderate reasoning depth, standard exploration |
| low    | Minimal reasoning, direct execution            |
| skip   | Agent is not spawned at all                    |

Per-invocation override: `--effort=<level>` overrides config default for one invocation (EFRT-05).

---

## Thorough (EFRT-01)

**Recommended model profile:** Quality | **Use when:** Critical features, complex architecture, production-impacting changes.

### Agent Matrix

| Agent     | Level | Notes                                                                               |
| --------- | ----- | ----------------------------------------------------------------------------------- |
| Lead      | max   | Exhaustive research, detailed decomposition, full self-review                       |
| Architect | max   | Comprehensive scope, full requirement mapping, traceability matrix                  |
| Dev       | high  | `plan_mode_required` -- read-only until lead approves. Thorough inline verification |
| QA        | high  | Deep tier (30+ checks). Full anti-pattern scan, requirement mapping                 |
| Scout     | high  | Broad research, cross-reference, adjacent topics. Runs on session model (Opus)      |
| Debugger  | high  | All 3 hypotheses tested. Full regression suite. Detailed report                     |

---

## Balanced (EFRT-02)

**Recommended model profile:** Balanced | **Use when:** Standard development work, most phases. The recommended default.

### Agent Matrix

| Agent     | Level  | Notes                                                                   |
| --------- | ------ | ----------------------------------------------------------------------- |
| Lead      | high   | Solid research, clear decomposition, coverage+feasibility self-review   |
| Architect | high   | Complete scope, clear criteria, standard dependency justification       |
| Dev       | medium | Focused implementation, standard verification, concise commits          |
| QA        | medium | Standard tier (15-25 checks). Content structure, key links, conventions |
| Scout     | medium | Targeted research, one source per finding. Runs on session model (Opus) |
| Debugger  | medium | Focused investigation, rank-order hypotheses, stop on confirmation      |

---

## Fast (EFRT-03)

**Recommended model profile:** Budget | **Use when:** Well-understood features, low-risk changes, iteration speed matters.

### Agent Matrix

| Agent     | Level  | Notes                                                                  |
| --------- | ------ | ---------------------------------------------------------------------- |
| Lead      | high   | Still needs good plans. Focused research, efficient decomposition      |
| Architect | medium | Concise scope, essential criteria, grouped requirements                |
| Dev       | medium | Shortest path to done criteria. Standard verify checks                 |
| QA        | low    | Quick tier (5-10 checks). Artifact existence, frontmatter, key strings |
| Scout     | low    | Single-source lookups, one URL max, no exploration                     |
| Debugger  | medium | Single most likely hypothesis first. Standard fix-and-verify           |

---

## Turbo (EFRT-04)

**Recommended model profile:** Budget | **Use when:** Quick fixes, config changes, obvious tasks, low-stakes edits.

### Agent Matrix

| Agent     | Level | Notes                                                              |
| --------- | ----- | ------------------------------------------------------------------ |
| Lead      | skip  | Not spawned. No planning step                                      |
| Architect | skip  | Not spawned                                                        |
| Dev       | low   | Direct execution, no research, minimal change, brief commits       |
| QA        | skip  | Not spawned. User judges output directly                           |
| Scout     | skip  | Not spawned                                                        |
| Debugger  | low   | Single hypothesis, targeted fix, minimal report (root cause + fix) |
