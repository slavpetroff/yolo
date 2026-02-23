# Discovered Issues Display Protocol

When agents or users report pre-existing failures, out-of-scope bugs, or issues unrelated to the current work, collect and display them using this protocol.

## Collection

Extract structured fields on a best-effort basis: use the test name if mentioned (or infer from context), the file path if identifiable, and the error text as reported. If the description is too vague to extract a test name or file, use the description verbatim as the error field and mark test/file as "unknown".

## De-duplication & Cap

De-duplicate by test name and file (when the same test+file pair appears with different error messages, keep the first error message encountered). Cap the displayed list at 20 entries; if more exist, show the first 20 and append `... and {N} more`.

## Display Format

Append after the result box:

```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /yolo:todo <description> to track
```

## Rules

This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /yolo:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.
