#!/usr/bin/env bash
set -u

# smart-route.sh <agent_role> <effort_level>
# Determines whether an agent should be included or skipped based on effort.
# Smart routing (v3_smart_routing graduated):
#   - Scout skipped for turbo/fast (no research needed)
#   - Architect skipped for non-thorough (architecture review only for thorough)
# Output: JSON {"agent":"<role>","decision":"include|skip","reason":"<reason>"}
# Exit: 0 always — routing must never block execution.

if [ $# -lt 2 ]; then
  echo '{"agent":"unknown","decision":"include","reason":"insufficient arguments"}'
  exit 0
fi

AGENT_ROLE="$1"
EFFORT="$2"

PLANNING_DIR=".vbw-planning"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DECISION="include"
REASON="default include"

case "$AGENT_ROLE" in
  scout)
    case "$EFFORT" in
      turbo|fast)
        DECISION="skip"
        REASON="effort=${EFFORT}: scout not needed"
        ;;
      *)
        REASON="effort=${EFFORT}: scout included"
        ;;
    esac
    ;;
  architect)
    case "$EFFORT" in
      thorough)
        REASON="effort=${EFFORT}: architect included"
        ;;
      *)
        DECISION="skip"
        REASON="effort=${EFFORT}: architect only for thorough"
        ;;
    esac
    ;;
  *)
    REASON="role=${AGENT_ROLE}: always included"
    ;;
esac

# Emit smart_route metric
if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  bash "${SCRIPT_DIR}/collect-metrics.sh" smart_route 0 \
    "agent=${AGENT_ROLE}" "effort=${EFFORT}" "decision=${DECISION}" 2>/dev/null || true
fi

echo "{\"agent\":\"${AGENT_ROLE}\",\"decision\":\"${DECISION}\",\"reason\":\"${REASON}\"}"
