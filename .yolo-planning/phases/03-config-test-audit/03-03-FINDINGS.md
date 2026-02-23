# 03-03 FINDINGS: Test Coverage Gap Analysis and Defaults Audit

## Task 1: Command Coverage Matrix

Cross-reference of 23 command markdown files (`commands/*.md`) against 72 bats test files (`tests/*.bats`).

### Coverage Matrix

| # | Command | Dedicated Test File | Indirect Coverage | Status |
|---|---------|-------------------|-------------------|--------|
| 1 | `config` | `config-read.bats`, `config-migration.bats` | Multiple test files reference config | **Covered** |
| 2 | `debug` | None | `hard-gates.bats` references debug context | **Indirect only** |
| 3 | `discuss` | None | No test references found | **No coverage** |
| 4 | `doctor` | None | No test references found | **No coverage** |
| 5 | `fix` | None | `qa-commands.bats`, `task-verify.bats` reference fix context | **Indirect only** |
| 6 | `help` | None | `token-economics.bats` references help output | **Indirect only** |
| 7 | `init` | None | `sessionstart-compact-hooks.bats`, `planning-git.bats` exercise init paths | **Indirect only** |
| 8 | `list-todos` | `list-todos.bats` | `persist-state-after-ship.bats` also exercises | **Covered** |
| 9 | `map` | None | `sessionstart-compact-hooks.bats`, `persist-state-after-ship.bats` reference codebase map | **Indirect only** |
| 10 | `pause` | None | No test references found | **No coverage** |
| 11 | `profile` | None | `resolve-agent-model.bats`, `token-budgets.bats` test model profiles | **Indirect only** |
| 12 | `release` | `archive-release.bats` | `mcp-integration.bats` also references release | **Covered** |
| 13 | `research` | `research-persistence.bats`, `discovery-research.bats`, `research-warn.bats` | `tier-cache.bats` | **Covered** |
| 14 | `resume` | None | `runtime-foundations.bats` exercises snapshot-resume | **Indirect only** |
| 15 | `skills` | None | `persist-state-after-ship.bats` references skills section | **Indirect only** |
| 16 | `status` | `statusline-cache-isolation.bats` | Many test files check status | **Covered** |
| 17 | `teach` | None | No test references found | **No coverage** |
| 18 | `todo` | `list-todos.bats` | `persist-state-after-ship.bats`, `discovered-issues-surfacing.bats` | **Covered** |
| 19 | `uninstall` | None | No test references found | **No coverage** |
| 20 | `update` | `update-state.bats`, `state-updater.bats` | `planning-git.bats` | **Covered** |
| 21 | `verify` | `task-verify.bats`, `validate-commit.bats` | `phase0-bugfix-verify.bats` | **Covered** |
| 22 | `vibe` | `vibe-mode-split.bats` | `phase4-integration.bats` | **Covered** |
| 23 | `whats-new` | None | No test references found | **No coverage** |

### Summary

- **Directly tested:** 9 commands (config, list-todos, release, research, status, todo, update, verify, vibe)
- **Indirect coverage only:** 7 commands (debug, fix, help, init, map, profile, resume, skills)
- **No coverage at all:** 6 commands (discuss, doctor, pause, teach, uninstall, whats-new)

### Recommendations

| Command | Priority | Recommendation |
|---------|----------|---------------|
| `doctor` | High | Health-check command with system diagnostics. Should have dedicated tests for each check it performs. |
| `pause` | Medium | State management command. Needs tests for pause/resume state transitions. |
| `resume` | Medium | Companion to pause. Needs tests for resume from various paused states. |
| `teach` | Low | Skill teaching command. Needs basic invocation and output format tests. |
| `uninstall` | Medium | Destructive operation (removes plugin). Needs tests to verify clean removal without side effects. |
| `whats-new` | Low | Changelog display command. Needs basic output format test. |
| `discuss` | Low | Interactive discussion command. Harder to test but could verify prompt generation. |
