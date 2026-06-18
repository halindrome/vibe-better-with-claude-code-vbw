#!/usr/bin/env bash
set -u

# normalize-workflows-mode.sh — emit canonical `prefer_workflows` values.
#
# Reads the `prefer_workflows` config key (the workflows-vs-teams backend
# preference). Mirrors `prefer_teams`: always | auto | never.
#
# `prefer_workflows` may be EITHER a scalar OR a per-agent object:
#
#   "prefer_workflows": "auto"                  # scalar — applies to every agent
#
#   "prefer_workflows": {                       # object — per-agent override + default
#     "default": "auto",
#     "qa": "auto",
#     "dev": "never"
#   }
#
# Per-agent resolution (most specific wins), mirroring resolve-agent-model.sh:
#   object[role]  ->  object.default  ->  "auto"
# A scalar is treated as the value for every role. When no role is given, the
# object's `default` (else "auto") is returned, preserving today's global behavior.
#
# Usage:
#   bash scripts/normalize-workflows-mode.sh [path/to/config.json] [role]
#   bash scripts/normalize-workflows-mode.sh --value <raw-value>
#
# Canonical values:
#   always | auto | never
#
#   always — prefer the Claude Workflows executor for qualifying (parallel, width
#            >= 2) steps whenever the runtime supports it; bypasses any future
#            "worth-it" heuristic.
#   auto   — prefer the Workflows executor when the runtime supports it AND the
#            step has real parallel work (fan-out >= 2); otherwise fall back to the
#            caller's native team/subagent/solo path.
#   never  — never route through Workflows; always use the existing delegation modes.
#
# Legacy/loose normalization:
#   true       -> always
#   false/null -> auto
#   on         -> always
#   off        -> never

read_raw_value() {
  local config_path="$1"
  local role="${2:-}"

  if [ ! -f "$config_path" ] || ! command -v jq >/dev/null 2>&1; then
    echo "auto"
    return 0
  fi

  # Scalar `prefer_workflows` is returned as-is (applies to all roles). An object
  # resolves role -> default -> "auto". `$pw[$role]` with an empty role is null,
  # so the empty-role case naturally falls through to `default`.
  jq -r --arg role "$role" '
    (.prefer_workflows // "auto") as $pw
    | if ($pw | type) == "object"
      then ($pw[$role] // $pw.default // "auto")
      else $pw
      end
  ' "$config_path" 2>/dev/null || echo "auto"
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

normalize_workflows_mode "$(read_raw_value "${1:-.vbw-planning/config.json}" "${2:-}")"
