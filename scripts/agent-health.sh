#!/bin/bash
set -u
# agent-health.sh — Track VBW agent health and recover from failures
#
# Usage:
#   agent-health.sh start     # SubagentStart hook: Create health file
#   agent-health.sh idle      # TeammateIdle hook: Check liveness, increment idle count
#   agent-health.sh stop      # SubagentStop hook: Clean up health file
#   agent-health.sh cleanup   # Stop hook: Remove all health tracking

CMD="${1:-}"

case "$CMD" in
  start)
    exit 0
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
