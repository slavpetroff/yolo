---
name: update
disable-model-invocation: true
description: Update YOLO to the latest version with automatic cache refresh.
argument-hint: "[--check]"
allowed-tools: Read, Bash, Glob
---

# YOLO Update $ARGUMENTS

**Resolve config directory:** `CLAUDE_DIR` = env var `CLAUDE_CONFIG_DIR` if set, otherwise `~/.claude`. Use for all config paths below.

## Steps

**CRITICAL shell note:** All glob patterns with `*/` MUST run inside `bash -c '...'` to avoid zsh `no matches found` errors.

### Step 1: Read current INSTALLED version

Read the **cached** version (what user actually has installed):
```bash
bash -c 'cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/*/VERSION 2>/dev/null | sort -V | tail -1'
```
Store as `old_version`. If empty, fall back to `${CLAUDE_PLUGIN_ROOT}/VERSION`.

**CRITICAL:** Do NOT read `${CLAUDE_PLUGIN_ROOT}/VERSION` as primary — in dev sessions it resolves to source repo (may be ahead), causing false "already up to date."

### Step 2: Handle --check

If `--check`: display version banner with installed version and STOP.

### Step 3: Check for update

```bash
curl -sf --max-time 5 "https://raw.githubusercontent.com/slavpetroff/yolo/main/VERSION"
```
Store as `remote_version`. Curl fails → STOP: "⚠ Could not reach GitHub to check for updates."
If remote == old: display "✓ Already at latest (v{old_version}). Refreshing cache..." Continue to Step 4 for clean cache refresh.

### Step 4: Nuclear cache wipe

**MANDATORY:** Use the cache-nuke script. Do NOT run rm -rf inline.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/cache-nuke.sh
```
Removes CLAUDE_DIR/plugins/cache/yolo-marketplace/yolo/, CLAUDE_DIR/commands/yolo/, /tmp/yolo-* for pristine update.

### Step 5: Perform update

Same version: "Refreshing YOLO v{old_version} cache..." Different: "Updating YOLO v{old_version}..."

**CRITICAL: Refresh marketplace FIRST** (stale checkout → plugin update re-caches old code):
```bash
claude plugin marketplace update yolo-marketplace 2>&1
```
If fails: "⚠ Marketplace refresh failed — trying update anyway..."

Try in order (stop at first success): A) `claude plugin update yolo@yolo-marketplace` B) Uninstall + reinstall C) Manual fallback, STOP.

Wait for cache population (poll 3x with 1s sleep for VERSION file). Re-sync global commands (copy from cache to CLAUDE_DIR/commands/yolo/).

### Step 5.5: Ensure YOLO statusline

Check `statusLine` in settings.json. If contains `yolo-statusline`: skip. Else set to statusline command object (same as init.md Step 0b). Use jq to write. Display `✓ Statusline restored (restart to activate)` if changed.

### Step 6: Verify update

```bash
bash -c 'CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; for i in 1 2 3; do V=$(cat "$CLAUDE_DIR"/plugins/cache/yolo-marketplace/yolo/*/VERSION 2>/dev/null | sort -V | tail -1); [ -n "$V" ] && echo "$V" && exit 0; sleep 1; done; echo ""'
```
Use result as authoritative version. If empty or equals old_version when it shouldn't: "Cache not populated yet. Restart Claude Code — files will appear on next session."

### Step 7: Display result

Use verified version from Step 6 for all display. Same version = "YOLO Cache Refreshed" banner. Different = "YOLO Updated" banner with old→new + "Restart Claude Code" + "/yolo:whats-new" suggestion.

## Output Format

Per @${CLAUDE_PLUGIN_ROOT}/references/yolo-brand-essentials.toon -- double-line box, ✓/⚠ symbols, Next Up, no ANSI.
