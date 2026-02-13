# Dependencies

## Required

| Dependency | Purpose | Guard Location |
|-----------|---------|----------------|
| jq | JSON parsing throughout all hooks and scripts | session-start.sh, phase-detect.sh, security-filter.sh, every hook script |
| git | Version control, brownfield detection, hook installation, commit validation | phase-detect.sh, validate-commit.sh, install-hooks.sh |
| bash | Script execution (all scripts target bash, not POSIX sh) | hook-wrapper.sh, all *.sh files |

## Optional

| Dependency | Purpose | Fallback |
|-----------|---------|----------|
| curl | Update checks (session-start.sh), usage API fetching (yolo-statusline.sh) | Silently skipped, no update notification |
| npx | Skills installation (`npx skills add ...`) | Manual skill installation |
| sort -V | Version sorting for plugin cache resolution | Fallback to `sort -t. -k1,1n -k2,2n -k3,3n` |

## System Tools (Unix Standard)

| Tool | Usage |
|------|-------|
| sed | Text substitution in state-updater.sh, compile-context.sh, multiple hooks |
| awk | YAML frontmatter parsing in file-guard.sh, suggest-next.sh |
| grep | Pattern matching throughout all scripts |
| find | File discovery in qa-gate.sh, yolo-statusline.sh, suggest-next.sh |
| wc | File/line counting |
| stat | File modification time checks (platform-aware: -f %m on macOS, -c %Y on Linux) |
| date | Timestamps in ISO 8601 and Unix epoch |
| tr | Character translation and whitespace cleanup |
| cut/paste | Field extraction in compile-context.sh |
| mktemp | Temporary file creation for atomic JSON updates |
| pgrep | Agent process counting in yolo-statusline.sh |
| id | User ID for cache path uniqueness |
| uname | Platform detection (Darwin vs Linux) |

## Claude Code Platform Dependencies

| Feature | Purpose |
|---------|---------|
| Plugin cache system | `~/.claude/plugins/cache/yolo-marketplace/yolo/*/` -- versioned plugin storage |
| Hook system | hooks.json declares PreToolUse, PostToolUse, SessionStart, SubagentStart, etc. |
| Agent Teams | Experimental feature for parallel Dev/Scout/QA execution |
| Slash commands | `commands/*.md` files registered as `/yolo:*` commands |
| Agent definitions | `agents/yolo-*.md` define subagent behavior, tools, model, maxTurns |
| CLAUDE.md | Project instruction injection at session start |
| settings.json | Environment configuration (agent teams, statusline) |
| AskUserQuestion | Interactive prompts within command flows |
| Task tool | Subagent spawning with model parameter |

## macOS-Specific

| Feature | Purpose |
|---------|---------|
| security command | Keychain access for OAuth token in yolo-statusline.sh |
| stat -f %m | File modification time (macOS variant) |
| brew | Suggested jq install method |

## No Dependencies

The following are explicitly NOT used:
- No Node.js runtime (npx is optional, for skills only)
- No Python runtime (peripheral files exist but are not part of YOLO)
- No package.json or npm
- No build tools or compilers
- No Docker
