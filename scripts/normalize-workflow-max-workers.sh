#!/usr/bin/env bash
set -u

# normalize-workflow-max-workers.sh — emit the VBW worker-count cap for dispatched
# Claude Dynamic Workflows.
#
# VBW authors the workflow scripts it dispatches, so it can hold a workflow's
# fan-out below the platform ceiling. The runtime caps concurrency at 16 and total
# agents at 1000 per run and exposes NO setting to lower those (see
# https://code.claude.com/docs/en/workflows "Behavior and limits"). This value is
# the VBW-side bound the orchestrator applies when it writes a workflow script: cap
# the parallel() / pipeline() fan-out width (and batch wider work) to at most this
# many concurrent workers. It can only lower, never raise, the platform ceiling.
#
# Usage:
#   bash scripts/normalize-workflow-max-workers.sh [path/to/config.json]
#   bash scripts/normalize-workflow-max-workers.sh --value <raw-value>
#
# Output: a single non-negative integer.
#   N > 0  — cap concurrent workers to N (the runtime still caps at 16 / 1000).
#   0      — no VBW cap; the platform ceiling applies.
#
# Default 4 (matches the /vbw:map quad scan's four domains). Any missing, invalid,
# or negative value falls back to the default so this predicate never breaks a
# caller.

DEFAULT_MAX_WORKERS=4

read_raw_value() {
  local config_path="$1"

  if [ ! -f "$config_path" ] || ! command -v jq >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  jq -r '.workflow_max_workers // empty' "$config_path" 2>/dev/null || echo ""
}

normalize_max_workers() {
  case "${1:-}" in
    ''|null)
      # Absent / null -> default.
      echo "$DEFAULT_MAX_WORKERS"
      ;;
    *[!0-9]*)
      # Anything that is not a run of digits (non-integer, or negative because of
      # the leading '-') -> fall back to the default.
      echo "$DEFAULT_MAX_WORKERS"
      ;;
    *)
      # A non-negative integer (0 means "no VBW cap").
      echo "$1"
      ;;
  esac
}

if [ "${1:-}" = "--value" ]; then
  shift
  normalize_max_workers "${1:-}"
  exit 0
fi

normalize_max_workers "$(read_raw_value "${1:-.vbw-planning/config.json}")"
