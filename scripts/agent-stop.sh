#!/bin/bash
set -u
# SubagentStop hook: Clear active agent marker
# Removes .yolo-planning/.active-agent so no stale agent is attributed

PLANNING_DIR=".yolo-planning"
[ -f "$PLANNING_DIR/.active-agent" ] && rm -f "$PLANNING_DIR/.active-agent"

exit 0
