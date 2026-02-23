---
disable-model-invocation: true
description: Display all available YOLO commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob, Bash
---

# YOLO Help $ARGUMENTS

## Context

Plugin root: `!`echo ${CLAUDE_PLUGIN_ROOT:-$(ls -1d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/yolo-marketplace/yolo/* 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)}``

## Behavior

### No args: Display all commands

Run the help output script and display the result exactly as-is (pre-formatted terminal output):

```
!`yolo help-output`
```

Display the output above verbatim. Do not reformat, summarize, or add commentary. The script dynamically reads all command files and generates grouped output.

### With arg: Display specific command details

You can get detailed help for any command by passing its name:

```
/yolo:help init
/yolo:help vibe
/yolo:help config
/yolo:help status
```

The `yolo:` prefix is optional — `/yolo:help init` and `/yolo:help yolo:init` both work.

Run the help-output command with the subcommand argument:

```
!`yolo help-output ${CLAUDE_PLUGIN_ROOT} $ARGUMENTS`
```

Display the output above verbatim. If the output says "Unknown command", show it as-is.

The per-command help includes:
- **Name** and **description** from frontmatter
- **Category** from frontmatter
- **Usage:** `/yolo:{name} {argument-hint}`
- **Flags:** available options and their descriptions
- **Examples:** common usage patterns
- **Related:** 1-2 related commands from the same category

If command not found: "Unknown command: {name}. Run /yolo:help for all commands."
