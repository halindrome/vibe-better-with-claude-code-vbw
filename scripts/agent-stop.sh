#!/bin/bash
set -u
# SubagentStop hook: Clear active agent marker
# Removes .vbw-planning/.active-agent so no stale agent is attributed

PLANNING_DIR=".vbw-planning"
[ -f "$PLANNING_DIR/.active-agent" ] && rm -f "$PLANNING_DIR/.active-agent"

exit 0
