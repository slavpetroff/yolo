# Model Profiles

**Purpose:** Control AI model selection for YOLO agents to optimize cost vs quality tradeoff.

## Overview
YOLO spawns 9 specialized agents (Architect, Lead, Senior, Dev, QA, QA-Code, Scout, Security, Debugger) via the Task tool. Model profiles determine which Claude model each agent uses. Three preset profiles cover common use cases, with per-agent overrides for advanced customization.

## Preset Profiles

### Quality
**Use when:** Architecture decisions, production-critical work, anything embarrassing to get wrong.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Architect | opus | Roadmap and phase structure requires strategic thinking |
| Lead | opus | Maximum planning depth and research quality |
| Senior | opus | Design review and code review need highest quality reasoning |
| Dev | opus | Complex implementation, deep reasoning |
| QA | sonnet | Solid verification without Opus cost |
| QA-Code | sonnet | Test/lint execution, pattern-level checks |
| Scout | haiku | Research throughput, 60x cheaper |
| Security | opus | OWASP/secrets/deps audit requires thoroughness |
| Debugger | opus | Root cause analysis needs deep reasoning |

**Est. cost per phase:** ~$2.80 (baseline)

### Balanced (default)
**Use when:** Standard development work, most phases.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Architect | sonnet | Clear roadmaps without Opus overhead |
| Lead | sonnet | Good planning quality, 5x cheaper than Opus |
| Senior | opus | Design review and code review need highest quality reasoning |
| Dev | sonnet | Solid implementation for most tasks |
| QA | sonnet | Standard verification depth |
| QA-Code | sonnet | Adequate for test/lint/pattern checks |
| Scout | haiku | Research throughput, cost-effective |
| Security | sonnet | Solid security audit at lower cost |
| Debugger | sonnet | Good debugging for common issues |

**Est. cost per phase:** ~$1.40 (50% of Quality)

### Budget
**Use when:** Prototyping, exploratory work, tight budget constraints.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Architect | sonnet | Roadmap clarity worth Sonnet cost |
| Lead | sonnet | Minimum viable planning (Haiku too weak) |
| Senior | sonnet | Spec enrichment needs Sonnet minimum |
| Dev | sonnet | Maintains code quality baseline |
| QA | haiku | Quick verification, 25x cheaper |
| QA-Code | haiku | Fast test/lint execution |
| Scout | haiku | Fast research, minimal cost |
| Security | sonnet | Security audit needs Sonnet minimum |
| Debugger | sonnet | Root cause needs Sonnet minimum |

**Est. cost per phase:** ~$0.70 (25% of Quality, 50% of Balanced)

## Per-Agent Overrides
Override individual agents without switching profiles.

**Syntax (via /yolo:config):**
```
/yolo:config model_override <agent> <model>
```

**Example:**
```
/yolo:config model_override dev opus
```
Sets Dev to Opus while keeping other agents at profile defaults.

**When to override:**
- Dev to Opus on budget profile for complex implementation tasks
- QA to Sonnet on budget profile for critical verification
- Lead to Opus on balanced profile for strategic planning phases

**Clearing overrides:**
Switch to a different profile and back, or manually edit .yolo-planning/config.json.

## Cost Comparison

| Profile | Architect | Lead | Senior | Dev | QA | QA-Code | Scout | Security | Debugger | Est. Cost/Phase | vs Quality |
|---------|-----------|------|--------|-----|----|----|-------|----------|----------|-----------------|------------|
| Quality | opus | opus | opus | opus | sonnet | sonnet | haiku | opus | opus | $2.80 | 100% |
| Balanced | sonnet | sonnet | opus | sonnet | sonnet | sonnet | haiku | sonnet | sonnet | $1.40 | 50% |
| Budget | sonnet | sonnet | sonnet | sonnet | haiku | haiku | haiku | sonnet | sonnet | $0.70 | 25% |

*Estimates based on typical 3-plan phase with 2 Dev teammates, 1 QA run, Lead planning. Actual costs vary by phase complexity and plan count.*

## Configuration

**View current profile:**
```
/yolo:config
```
Shows active profile and per-agent model assignments in settings table.

**Switch profile:**
```
/yolo:config model_profile <quality|balanced|budget>
```
Displays before/after cost impact estimate.

**Config file location:**
`.yolo-planning/config.json` -- fields: `model_profile` (string), `model_overrides` (object)

## Implementation Notes
- Model resolution: `scripts/resolve-agent-model.sh` reads config, applies profile preset, merges overrides
- Task tool integration: All agent-spawning commands pass explicit `model` parameter
- Turbo effort bypasses model logic (no agents spawned, direct execution)
- Model names: `opus` = Claude Opus 4.6, `sonnet` = Claude Sonnet 4.5, `haiku` = Claude Haiku 3.5

## Related Documentation
- Effort vs Model: @references/effort-profile-balanced.md (effort controls workflow depth, model profile controls cost)
- Command reference: @commands/help.md
- User guide: @README.md Cost Optimization section
