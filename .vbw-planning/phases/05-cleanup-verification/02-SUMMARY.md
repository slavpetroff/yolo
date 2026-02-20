---
phase: 5
plan: 02
status: complete
---
## What Was Built
Replaced all `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh` and `bash scripts/<name>.sh` references in 14 command .md files with their Rust CLI equivalents (`yolo <name>`). This completes the migration from bash scripts to the native Rust CLI for all command instructions.

## Files Modified
- commands/init.md -- replaced generate-gsd-index, install-hooks, install-mcp, infer-gsd-summary script calls
- commands/vibe.md -- replaced compile-context, compile-rolling-summary, persist-state-after-ship, phase-detect, suggest-next references
- commands/todo.md -- replaced persist-state-after-ship, migrate-orphaned-state script calls
- commands/config.md -- replaced migrate-config script call
- commands/help.md -- replaced help-output script call
- commands/release.md -- replaced 3 bump-version script calls
- commands/doctor.md -- replaced bump-version, doctor-cleanup script calls; updated check 8 from scripts/*.sh to yolo binary
- commands/update.md -- replaced cache-nuke script call
- commands/skills.md -- updated detect-stack error string
- commands/discuss.md -- prior path normalization included
- commands/list-todos.md -- prior path normalization included
- commands/resume.md -- prior path normalization included
- commands/status.md -- prior path normalization included
- commands/verify.md -- prior path normalization included

## Results
- Tasks completed: 5/5
- Commit: bb6be71

## Deviations
- commands/discuss.md, commands/list-todos.md, commands/resume.md, commands/status.md, commands/verify.md had prior changes from Plan 05-01 (replacing long ${CLAUDE_PLUGIN_ROOT}/yolo-mcp-server/target/release/yolo paths with $HOME/.cargo/bin/yolo). These were uncommitted and included in this commit since they are part of the same cleanup effort.
- doctor.md check 8 ("Scripts executable") was updated to check for the yolo binary instead of scripts/*.sh permissions, since the bash scripts no longer exist.
- Skills.sh references (proper noun for the external registry service) were preserved in init.md and skills.md as expected.
