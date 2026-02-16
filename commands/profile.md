---
name: profile
disable-model-invocation: true
description: Switch between work profiles or create custom ones. Profiles change effort, autonomy, and verification in one go.
argument-hint: "[profile-name | save | delete <name>]"
allowed-tools: Read, Write, Edit
---

# YOLO Profile $ARGUMENTS

## Context

Config:
```
!`cat .yolo-planning/config.json 2>/dev/null || echo "No config found -- run /yolo:init first"`
```

## Guard

Guard: no .yolo-planning/ -> STOP "YOLO is not set up yet. Run /yolo:init to get started."

## Built-in Profiles

| Profile | Effort | Autonomy | Verification | Discovery | Use case |
|---------|--------|----------|--------------|-----------|----------|
| default | balanced | standard | standard | 3-5 questions | Fresh install baseline |
| prototype | fast | confident | quick | 1-2 quick | Rapid iteration |
| production | thorough | cautious | deep | 5-8 thorough | Production code |
| yolo | turbo | pure-yolo | skip | skip | No guardrails |

## Behavior

### No arguments: List and switch

1. Read config.json for `active_profile` (default: "default") + `custom_profiles`. Display table with * on active. If active_profile is "custom": show "Active: custom (modified from {last_profile})".
2. AskUserQuestion: "Which profile?" Options: all profiles + "Create new profile". Mark current "(active)".
3. Apply: update effort/autonomy/verification_tier in config.json, set active_profile. Display changed values with ➜. If already matching: "✓ Already on {name}". If "Create new profile": go to Save flow.

### `save`: Create custom profile

**S1.** AskUserQuestion: "From current settings" | "From scratch" (pick effort, autonomy, verification).
**S2.** AskUserQuestion for name (suggest 2-3 contextual). Validate: no built-in clash, no spaces, 1-30 chars.
**S3.** Add to `custom_profiles` in config.json. Ask "Switch to {name} now?" Apply if yes.

### Direct name: `profile <name>`

If $ARGUMENTS matches a profile: apply immediately (no listing). If unknown: "⚠ Profile \"{name}\" not found. Available: quality, balanced, budget. Run /yolo:profile to see all."

### `delete <name>`

Built-in: "⚠ Cannot delete built-in profile." Not found: "⚠ Profile \"{name}\" not found. Available: quality, balanced, budget." Otherwise: remove from custom_profiles. If active, reset to "default".

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- single-line box, ✓/⚠/➜ symbols, Next Up, no ANSI.

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/suggest-next.sh profile` and display.
