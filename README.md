# VBW -- Vibe Better with Claude Code

VBW is an AI-native development framework delivered as a Claude Code plugin.
It provides a complete development lifecycle -- from project initialization
through planning, execution, verification, and deployment -- all driven by
slash commands inside Claude Code. VBW uses compaction-aware architecture
and skill-based extensibility to keep Claude effective across long sessions.

## Quick Start

Install from the marketplace:

```
claude plugin install vbw
```

For local development, run Claude Code with the plugin directory:

```
claude --plugin-dir /path/to/vbw
```

Then initialize VBW in your project:

```
/vbw:init
```

## Commands

### Phase 1 -- Core

| Command | Description |
|---|---|
| `/vbw:init` | Initialize VBW in a project, detect stack, suggest skills |
| `/vbw:config` | View and modify VBW preferences |
| `/vbw:help` | Show available commands, status, and usage guidance |

### Future Phases

Additional commands will be added as VBW develops:

- `/vbw:plan` -- Generate execution plans from requirements
- `/vbw:execute` -- Run plans with verification and commit tracking
- `/vbw:verify` -- Run verification pipeline on completed work
- `/vbw:status` -- Show project progress and health
- `/vbw:skill` -- Manage Claude Code skills
- `/vbw:compact` -- Handle context compaction and state preservation

## Development

To develop VBW locally, clone this repository and point Claude Code at it:

```
claude --plugin-dir .
```

Validate the plugin structure:

```
claude plugin validate .
```

Run with debug output:

```
claude --plugin-dir . --debug
```

### Project Structure

```
.claude-plugin/    Plugin manifest
config/            Default settings and stack mappings
skills/            Claude Code skill definitions
agents/            Agent role definitions
references/        Reference documentation
templates/         Artifact templates
```

## License

MIT -- see [LICENSE](LICENSE) for details.
