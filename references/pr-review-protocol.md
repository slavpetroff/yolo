# PR Review Protocol

## Check for Overlapping PRs

Before starting any feature, fix, or refactor, run `gh pr list --state open` and check if any open/draft PR already touches the same area. If a PR exists that overlaps with what you're about to do — even if it's draft, half-finished, or failing CI — STOP and tell the user: "There's an open PR (#M) by @author that overlaps with this work. Proceed anyway?" Do NOT read the PR's diff, copy its approach, or integrate its changes without explicit user approval. Contributors' in-progress work belongs to them. This also applies when resolving GitHub issues — check `gh pr list --search "issue_number"` first.

## Review by Diffing

When reviewing a PR, run `gh pr diff N` and compare the actual changes to what's currently in the repo. A PR that touches files you already modified is NOT automatically redundant — it may contain additional improvements, bug fixes, or edge cases beyond what's already shipped. Only the diff tells you what's new. Don't dismiss a PR as "already done" without confirming every change in the diff is already present in the codebase.
