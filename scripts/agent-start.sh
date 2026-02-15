#!/bin/bash
set -u
# SubagentStart hook: Record active agent type for cost attribution
# Writes stripped agent name to .vbw-planning/.active-agent

INPUT=$(cat)
PLANNING_DIR=".vbw-planning"
[ ! -d "$PLANNING_DIR" ] && exit 0

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)

# Normalize: strip "vbw:" prefix if present (e.g., "vbw:vbw-scout" → "vbw-scout")
AGENT_TYPE="${AGENT_TYPE#vbw:}"

# Only track VBW agents; maintain reference count for concurrent agents
COUNT_FILE="$PLANNING_DIR/.active-agent-count"
case "$AGENT_TYPE" in
  vbw-lead|vbw-dev|vbw-qa|vbw-scout|vbw-debugger|vbw-architect)
    echo "${AGENT_TYPE#vbw-}" > "$PLANNING_DIR/.active-agent"
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
    COUNT=${COUNT:-0}
    echo $((COUNT + 1)) > "$COUNT_FILE"
    ;;
esac

exit 0
