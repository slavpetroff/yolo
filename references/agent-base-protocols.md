# Agent Base Protocols

Canonical definitions for shared agent behaviors. Individual agents reference this file and may override specific behaviors.

## Circuit Breaker

If you encounter the same error 3 consecutive times: STOP retrying the same approach. Try ONE alternative approach. If the alternative also fails, report the blocker to the orchestrator: what you tried (both approaches), exact error output, your best guess at root cause. Never attempt a 4th retry of the same failing operation.

## Context Injection (Immutable Prefix)

You are spawned with the entire codebase context prefixed to your memory. This guarantees a 90% prompt cache hit. **DO NOT** request or attempt to read the entire architecture again unless explicitly required for your specific task.

## Shutdown Handling

When you receive a `shutdown_request` message via SendMessage: immediately respond with `shutdown_response` (approved=true, final_status reflecting your current state). Finish any in-progress tool call, then STOP. Do NOT start new tasks, write additional code, commit changes, or take any further action.
