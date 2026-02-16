#!/bin/bash
set -u
# agent-health.sh — Track VBW agent health and recover from failures
#
# Usage:
#   agent-health.sh start     # SubagentStart hook: Create health file
#   agent-health.sh idle      # TeammateIdle hook: Check liveness, increment idle count
#   agent-health.sh stop      # SubagentStop hook: Clean up health file
#   agent-health.sh cleanup   # Stop hook: Remove all health tracking

HEALTH_DIR=".vbw-planning/.agent-health"

cmd_start() {
  local input pid role now
  input=$(cat)

  # Extract PID and role from hook JSON
  pid=$(echo "$input" | jq -r '.pid // ""' 2>/dev/null)
  role=$(echo "$input" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)

  # Normalize role (strip prefixes like vbw:, @, etc.)
  role=$(echo "$role" | sed -E 's/^@?vbw[:-]//i' | tr '[:upper:]' '[:lower:]')

  # Skip if no role extracted
  if [ -z "$role" ] || [ -z "$pid" ]; then
    exit 0
  fi

  # Create health directory
  mkdir -p "$HEALTH_DIR"

  # Generate ISO8601 timestamp
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Write health file
  jq -n \
    --arg pid "$pid" \
    --arg role "$role" \
    --arg ts "$now" \
    '{
      pid: $pid,
      role: $role,
      started_at: $ts,
      last_event_at: $ts,
      last_event: "start",
      idle_count: 0
    }' > "$HEALTH_DIR/${role}.json"

  # Output hook response
  jq -n \
    --arg event "SubagentStart" \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: ""
      }
    }'
}

CMD="${1:-}"

case "$CMD" in
  start)
    cmd_start
    ;;
  idle)
    exit 0
    ;;
  stop)
    exit 0
    ;;
  cleanup)
    exit 0
    ;;
  *)
    echo "Usage: $0 {start|idle|stop|cleanup}" >&2
    exit 1
    ;;
esac
