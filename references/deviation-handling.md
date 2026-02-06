# VBW Deviation Handling

Single source of truth for how agents handle unexpected situations during plan execution.

## Overview

Deviations are differences between what the plan specified and what reality requires during execution. They are normal and expected -- plans cannot anticipate every implementation detail. The key is classification and appropriate response.

Every agent executing a plan applies these rules automatically. The deviation type determines whether the agent fixes silently, logs and continues, or stops for user input.

## Deviation Types

| Type           | Severity | Agent Action                  | Example                                           |
|----------------|----------|-------------------------------|----------------------------------------------------|
| Minor          | Low      | Auto-fix silently             | Missing import, typo in path, wrong casing         |
| Critical Path  | Medium   | Auto-add, log in SUMMARY.md   | Missing validation, edge case handler, required field not in plan |
| Blocking       | High     | Auto-resolve, log prominently | Test failure, build error, type mismatch, dependency conflict |
| Architectural  | Critical | STOP and checkpoint to user   | Design pattern change, new dependency, schema restructure |

## Handling Rules

### Rule 1: Minor (DEVN-01)

**Detection:** Issue is syntactic, not semantic. Fix is obvious and mechanical.

**Action:** Fix inline without comment. Do not log in deviations.

**Boundary:** If the fix requires more than 5 lines of new code, escalate to Critical Path.

**Examples:**
- Missing import statement
- Incorrect file path in reference
- Wrong method name casing
- Trivial formatting mismatch

### Rule 2: Critical Path (DEVN-02)

**Detection:** Plan omitted something functionally necessary that was discovered during implementation.

**Action:** Implement the missing piece. Log as deviation in SUMMARY.md with description.

**Boundary:** If the addition changes the plan's scope or affects other plans, escalate to Architectural.

**Examples:**
- API endpoint needs input validation the plan did not specify
- Component needs error boundary not in the plan
- Database query needs index for performance
- Missing null check on a critical code path

### Rule 3: Blocking (DEVN-03)

**Detection:** Execution cannot continue without resolving this issue first.

**Action:** Diagnose and fix. Log prominently in SUMMARY.md with root cause. If fix fails after 2 attempts, escalate to Architectural.

**Boundary:** If the blocker reveals a design flaw (not just a bug), escalate to Architectural immediately.

**Examples:**
- Tests failing due to incorrect mock setup
- Build error from type mismatch
- Dependency version conflict
- Missing environment variable preventing startup

### Rule 4: Architectural (DEVN-04)

**Detection:** Resolution requires changing the design, adding dependencies not in the plan, or affecting multiple files outside this plan's scope.

**Action:** STOP execution. Present the deviation to the user using the checkpoint protocol (see `references/checkpoints.md`). Include: what was expected, what was found, proposed options, impact assessment.

**Resume:** Only after user approves a direction.

**Examples:**
- Chosen library does not support required feature -- need alternative
- Schema design does not accommodate a discovered use case
- Plan assumed an API exists but it does not
- Change requires restructuring files owned by a different plan

## Escalation Ladder

```
Minor --(>5 lines)--> Critical Path --(scope change)--> Architectural
                      Blocking --(design flaw)--> Architectural
                      Blocking --(2 failed fixes)--> Architectural
```

**Priority when multiple rules could apply:**

1. If Rule 4 applies --> STOP and checkpoint (architectural decision)
2. If Rules 1-3 apply --> Fix automatically, track for SUMMARY.md
3. If genuinely unsure --> Apply Rule 4 (checkpoint for safety)

## SUMMARY.md Logging Format

Deviations are recorded in the SUMMARY.md frontmatter `deviations` field:

```yaml
deviations:
  - "[Rule 2 - Critical] Added input validation to POST /api/projects -- plan omitted request body schema check"
  - "[Rule 3 - Blocking] Fixed type mismatch in User model -- createdAt was string, needed Date"
```

**Rule 1 (minor) deviations are NOT logged.** Rules 2-4 are ALWAYS logged.

Rule 4 (architectural) deviations additionally include the checkpoint outcome:

```yaml
  - "[Rule 4 - Architectural] Switched from library-x to library-y -- user approved at checkpoint"
```
