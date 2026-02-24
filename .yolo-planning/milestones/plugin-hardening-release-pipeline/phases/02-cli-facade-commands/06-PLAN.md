---
phase: 02
plan: 06
title: "Instruction updates for facade commands"
wave: 2
depends_on: [1, 2, 3, 4]
must_haves:
  - "execute-protocol SKILL.md uses qa-suite instead of 5 sequential calls"
  - "execute-protocol uses resolve-agent instead of resolve-model + resolve-turns"
  - "archive.md uses release-suite instead of sequential release steps"
  - "bootstrap.md uses bootstrap-all instead of sequential bootstrap calls"
---

# Plan 06: Instruction updates for facade commands

**Files modified:** `skills/execute-protocol/SKILL.md`, `skills/vibe-modes/archive.md`, `skills/vibe-modes/bootstrap.md`

Updates instruction files to use the new facade commands, replacing old sequential patterns.

## Task 1: Update execute-protocol QA section

**Files:** `skills/execute-protocol/SKILL.md`

**What to do:**
1. Find the QA step (Step 3d or similar) where 5 sequential QA commands are called
2. Replace the 5 individual `yolo verify-plan-completion`, `yolo commit-lint`, `yolo check-regression`, `yolo diff-against-plan`, `yolo validate-requirements` calls with a single:
   ```
   yolo qa-suite <summary_path> <plan_path> --commit-range <range> --phase-dir <dir>
   ```
3. Update the result parsing instructions: note that all 5 check results are in `delta.results`
4. Keep the remediation loop logic but update it to reference `delta.results` sub-keys

## Task 2: Update execute-protocol agent resolution

**Files:** `skills/execute-protocol/SKILL.md`

**What to do:**
1. Find all locations where `yolo resolve-model` and `yolo resolve-turns` are called as a pair (6 pairs per research: Reviewer, Architect, Dev, QA, Lead, Researcher)
2. Replace each pair with a single `yolo resolve-agent <agent> <config> <profiles> [effort]`
3. Update the result parsing: model is at `delta.model`, turns is at `delta.turns`
4. For the Lead agent startup that resolves ALL agents, replace with `yolo resolve-agent --all <config> <profiles> [effort]` and note results are in `delta.agents`

## Task 3: Update archive.md for release-suite

**Files:** `skills/vibe-modes/archive.md`

**What to do:**
1. Find the release section where bump-version, changelog, git add, commit, tag, push are called sequentially
2. Replace with single: `yolo release-suite [--major|--minor] [--no-push]`
3. Note `--dry-run` option for previewing
4. Update result parsing to reference `delta.steps` array
5. Keep the conditional logic for when to use `--major` vs `--minor` vs default patch

## Task 4: Update bootstrap.md for bootstrap-all

**Files:** `skills/vibe-modes/bootstrap.md`

**What to do:**
1. Find where `yolo bootstrap project`, `yolo bootstrap requirements`, `yolo bootstrap roadmap`, `yolo bootstrap state` are called sequentially
2. Replace with single: `yolo bootstrap-all <output_dir> <name> <description> <phases_json> <discovery_json> [--core-value V] [--research R] [--milestone M]`
3. Update result parsing to reference `delta.steps` sub-keys
4. Note that individual bootstrap commands still exist for ad-hoc use

**Commit:** `docs(yolo): update instructions to use facade commands`
