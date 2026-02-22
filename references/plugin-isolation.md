# Plugin Isolation

## File Boundary

- All planning artifacts live under `.yolo-planning/`. Agents and commands MUST NOT manually edit files in this directory; use YOLO commands instead.
- Hook-enforced: PreToolUse hooks block unauthorized writes to `.yolo-planning/`.

## Platform Tool Permissions

- Agents operate within their assigned directory boundaries.
- File writes outside the project root are blocked.
- Secrets (`.env`, `.pem`, `.key`, credentials) are never staged or committed.

## Hook Enforcement

- `PreToolUse` hooks validate file paths before any read/write operation.
- Violations are denied with a JSON `permissionDecision: "deny"` response.
- Department-level guards enforce per-agent file boundaries during execution.
