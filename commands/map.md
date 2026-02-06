---
description: Analyze existing codebase with parallel mapper agents to produce structured mapping documents.
argument-hint: [--incremental] [--package=name]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch
---

# VBW Map: $ARGUMENTS

## Context

Working directory: `!`pwd``

Existing codebase mapping:
```
!`ls .planning/codebase/ 2>/dev/null || echo "No codebase mapping found"`
```

Current META.md:
```
!`cat .planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```

Git status:
```
!`git rev-parse --is-inside-work-tree 2>/dev/null && echo "Git repo: yes" || echo "Git repo: no"`
```

Current HEAD:
```
!`git rev-parse HEAD 2>/dev/null || echo "no-git"`
```

Project files detected:
```
!`ls package.json pyproject.toml Cargo.toml go.mod *.sln Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"`
```

Tracked files (sample):
```
!`git ls-files 2>/dev/null || echo "Not a git repo"`
```

Current effort setting:
```
!`cat .planning/config.json 2>/dev/null || echo "No config found"`
```

## Guard

1. **Not initialized:** If .planning/ directory doesn't exist, STOP: "Run /vbw:init first."
2. **No git repo:** If not inside a git repository, WARN: "Not a git repo -- git hash tracking and incremental mapping disabled." Continue with full mapping mode.
3. **Empty project:** If no source files detected (no recognized project files and `git ls-files` returns 0 or git is unavailable and no common source directories exist), STOP: "No source code found to map."

## Steps

### Step 1: Detect incremental vs full mapping (CMAP-05)

Determine whether to perform a full mapping or an incremental refresh.

**Decision logic:**

1. Check if `.planning/codebase/META.md` exists
2. If META.md exists AND (`--incremental` flag is present OR no flag was provided):
   - Read the `git_hash` field from META.md frontmatter
   - Get the list of changed files since that hash:
     ```
     git diff --name-only {stored_hash}..HEAD
     ```
   - Count changed files relative to total tracked files
   - If changed files < 20% of total tracked files: **incremental mode**
     - Store the changed file list for mapper agents
     - Mappers will update only sections affected by changed files
   - If changed files >= 20% of total tracked files: **full mode**
     - Too many changes for incremental -- full rescan is more reliable
3. If META.md does not exist: **full mode** (first mapping)
4. If not a git repo: **full mode** (no diff capability)

Store the result:
- `MAPPING_MODE`: "full" or "incremental"
- `CHANGED_FILES`: list of changed file paths (empty if full mode)

### Step 2: Security enforcement (CMAP-10)

Define the security exclusion list. This list is mandatory for ALL mapper agents -- it is NOT optional and cannot be overridden.

```
SECURITY_EXCLUSIONS:
- .env, .env.*, .env.local, .env.production, .env.development
- *.pem, *.key, *.cert, *.p12, *.pfx
- credentials.json, secrets.json, service-account*.json
- **/node_modules/**, **/.git/**, **/dist/**, **/build/**
- Any file matching patterns in .gitignore
```

Every mapper agent prompt MUST include the following instruction verbatim:

> "NEVER read files matching these patterns: .env, .env.*, .env.local, .env.production, .env.development, *.pem, *.key, *.cert, *.p12, *.pfx, credentials.json, secrets.json, service-account*.json, node_modules/, .git/, dist/, build/. If a file path matches any exclusion pattern, skip it entirely. Do not report its contents. Additionally, respect all patterns listed in the project's .gitignore file."

### Step 3: Detect monorepo structure (CMAP-06)

Check for monorepo indicators:

1. `lerna.json` exists
2. `pnpm-workspace.yaml` exists
3. `packages/` directory exists with subdirectories containing their own package.json
4. `apps/` directory exists with subdirectories containing their own package.json
5. Root `package.json` contains a `workspaces` field

**If monorepo detected:**
- Set `MONOREPO=true`
- Enumerate all packages (name, path, has own package.json)
- If `--package=name` flag provided: scope mapping to that single package only
- Otherwise: map each package individually, then produce a cross-package INDEX.md section

**If not monorepo:**
- Set `MONOREPO=false`
- Proceed with standard single-project mapping

<!-- Step 4: Spawn mapper agents (added in Task 2) -->

<!-- Steps 5-9: Synthesis, validation, META.md, output, security verification (added in Task 3) -->
