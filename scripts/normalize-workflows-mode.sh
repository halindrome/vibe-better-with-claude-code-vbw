#!/usr/bin/env bash
set -u

# normalize-workflows-mode.sh — emit canonical workflows executor-backend values.
#
# Usage:
#   bash scripts/normalize-workflows-mode.sh [path/to/config.json]
#   bash scripts/normalize-workflows-mode.sh --value <raw-value>
#
# Canonical values:
#   always | auto | never
#
#   always — prefer the Claude Workflows executor for qualifying (wide/parallel)
#            steps whenever the runtime supports it.
#   auto   — use the Workflows executor only when it is available AND the step is
#            a good fit (high fan-out); otherwise fall back to team/subagent/direct.
#   never  — never route through Workflows; always use the existing delegation modes.
#
# Legacy/loose normalization:
#   true       -> always
#   false/null -> auto
#   on         -> always
#   off        -> never

read_raw_value() {
  local config_path="$1"

  if [ ! -f "$config_path" ] || ! command -v jq >/dev/null 2>&1; then
    echo "auto"
    return 0
  fi

  jq -r '.workflows // "auto"' "$config_path" 2>/dev/null || echo "auto"
}

normalize_workflows_mode() {
  case "${1:-auto}" in
    ""|null|false)
      echo "auto"
      ;;
    true|on)
      echo "always"
      ;;
    off)
      echo "never"
      ;;
    always|auto|never)
      echo "$1"
      ;;
    *)
      # Intentionally preserve unknown values so callers can decide whether to
      # validate strictly or fail open.
      echo "$1"
      ;;
  esac
}

if [ "${1:-}" = "--value" ]; then
  shift
  normalize_workflows_mode "${1:-auto}"
  exit 0
fi

normalize_workflows_mode "$(read_raw_value "${1:-.vbw-planning/config.json}")"
