#!/usr/bin/env bash
# resolve-agent-max-turns.sh - Turn budget resolution for VBW agents
#
# Reads agent_max_turns from config.json and resolves maxTurns for a given
# agent and effort profile.
#
# Usage: resolve-agent-max-turns.sh <agent-name> <config-path> <effort>
#   agent-name: lead|dev|qa|scout|debugger|architect
#   config-path: path to .vbw-planning/config.json
#   effort: thorough|balanced|fast|turbo
#
# Returns: stdout = integer maxTurns (0 means "disabled"), exit 0
# Errors: stderr = error message, exit 1

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: resolve-agent-max-turns.sh <agent-name> <config-path> <effort>" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
EFFORT="$3"

case "$AGENT" in
  lead|dev|qa|scout|debugger|architect)
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect" >&2
    exit 1
    ;;
esac

case "$EFFORT" in
  thorough|balanced|fast|turbo)
    ;;
  *)
    echo "Invalid effort '$EFFORT'. Valid: thorough, balanced, fast, turbo" >&2
    exit 1
    ;;
esac

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /vbw:init first." >&2
  exit 1
fi

if ! jq empty "$CONFIG_PATH" >/dev/null 2>&1; then
  echo "Malformed config JSON at $CONFIG_PATH" >&2
  exit 1
fi

default_base_turns() {
  case "$1" in
    scout) echo 15 ;;
    qa) echo 25 ;;
    architect) echo 30 ;;
    debugger) echo 80 ;;
    lead) echo 50 ;;
    dev) echo 75 ;;
  esac
}

multiplier_for_effort() {
  # Output "numerator denominator"
  case "$1" in
    thorough) echo "3 2" ;;   # 1.5x
    balanced) echo "1 1" ;;   # 1.0x
    fast) echo "4 5" ;;       # 0.8x
    turbo) echo "3 5" ;;      # 0.6x
  esac
}

normalize_turn_value() {
  local value="$1"

  case "$value" in
    false|FALSE|False)
      echo 0
      return 0
      ;;
  esac

  if [ "$value" = "null" ] || [ -z "$value" ]; then
    echo ""
    return 0
  fi

  if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
    echo "Invalid turn budget value '$value' for agent '$AGENT'" >&2
    return 1
  fi

  if [ "$value" -le 0 ]; then
    echo 0
    return 0
  fi

  echo "$value"
}

CONFIGURED_TYPE=$(jq -r ".agent_max_turns.$AGENT | type? // \"null\"" "$CONFIG_PATH")

# Object mode: explicit per-effort values, no multiplier applied.
if [ "$CONFIGURED_TYPE" = "object" ]; then
  RAW_VALUE=$(jq -r ".agent_max_turns.$AGENT.$EFFORT // .agent_max_turns.$AGENT.balanced // empty" "$CONFIG_PATH")
  EXPLICIT_VALUE=$(normalize_turn_value "$RAW_VALUE")
  if [ -n "$EXPLICIT_VALUE" ]; then
    echo "$EXPLICIT_VALUE"
    exit 0
  fi
fi

# Scalar mode: configured or default base value with effort multiplier.
RAW_BASE=$(jq -r ".agent_max_turns.$AGENT" "$CONFIG_PATH")
BASE=$(normalize_turn_value "$RAW_BASE")
if [ -z "$BASE" ]; then
  BASE=$(default_base_turns "$AGENT")
fi

if [ "$BASE" -eq 0 ]; then
  echo 0
  exit 0
fi

read -r NUM DEN <<<"$(multiplier_for_effort "$EFFORT")"
RESOLVED=$(( (BASE * NUM + DEN / 2) / DEN ))

if [ "$RESOLVED" -lt 1 ]; then
  RESOLVED=1
fi

echo "$RESOLVED"
exit 0