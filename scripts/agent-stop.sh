#!/bin/bash
set -u
# SubagentStop hook: Clear active agent marker
# Removes .yolo-planning/.active-agent so no stale agent is attributed

PLANNING_DIR=".yolo-planning"
rm -f "$PLANNING_DIR/.active-agent" 2>/dev/null

exit 0
