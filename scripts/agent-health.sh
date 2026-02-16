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

orphan_recovery() {
  # Stub for now, will implement in Task 4
  echo "ORPHAN_RECOVERY_CALLED"
}

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

cmd_idle() {
  local input role health_file pid idle_count now advisory
  input=$(cat)

  # Extract role from hook JSON
  role=$(echo "$input" | jq -r '.agent_type // .agent_name // .name // ""' 2>/dev/null)
  role=$(echo "$role" | sed -E 's/^@?vbw[:-]//i' | tr '[:upper:]' '[:lower:]')

  if [ -z "$role" ]; then
    exit 0
  fi

  health_file="$HEALTH_DIR/${role}.json"
  if [ ! -f "$health_file" ]; then
    exit 0
  fi

  # Load health data
  pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)
  idle_count=$(jq -r '.idle_count // 0' "$health_file" 2>/dev/null)

  # Check PID liveness
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    # PID is dead — call orphan recovery
    advisory=$(orphan_recovery "$role" "$pid")
    jq -n \
      --arg event "TeammateIdle" \
      --arg context "$advisory" \
      '{
        hookSpecificOutput: {
          hookEventName: $event,
          additionalContext: $context
        }
      }'
    exit 0
  fi

  # Increment idle count
  idle_count=$((idle_count + 1))
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update health file
  jq --arg ts "$now" --argjson count "$idle_count" \
    '.last_event_at = $ts | .last_event = "idle" | .idle_count = $count' \
    "$health_file" > "${health_file}.tmp" && mv "${health_file}.tmp" "$health_file"

  # Check for stuck agent (idle_count >= 3)
  advisory=""
  if [ "$idle_count" -ge 3 ]; then
    advisory="AGENT HEALTH: Agent $role appears stuck (idle_count=$idle_count)"
  fi

  # Output hook response
  jq -n \
    --arg event "TeammateIdle" \
    --arg context "$advisory" \
    '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $context
      }
    }'
}

CMD="${1:-}"

case "$CMD" in
  start)
    cmd_start
    ;;
  idle)
    cmd_idle
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
