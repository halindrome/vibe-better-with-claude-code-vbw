#!/bin/bash
set -u
# SubagentStop hook: Decrement active agent count
# Uses reference counting so concurrent agents (e.g., Scout + Lead) don't
# delete the marker while siblings are still running.
# Final cleanup happens in session-stop.sh.

PLANNING_DIR=".vbw-planning"
COUNT_FILE="$PLANNING_DIR/.active-agent-count"

if [ -f "$COUNT_FILE" ]; then
  COUNT=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
  COUNT=${COUNT:-0}
  COUNT=$((COUNT - 1))
  if [ "$COUNT" -le 0 ]; then
    rm -f "$PLANNING_DIR/.active-agent" "$COUNT_FILE"
  else
    echo "$COUNT" > "$COUNT_FILE"
  fi
elif [ -f "$PLANNING_DIR/.active-agent" ]; then
  # Legacy: no count file but marker exists — remove (single agent case)
  rm -f "$PLANNING_DIR/.active-agent"
fi

exit 0
