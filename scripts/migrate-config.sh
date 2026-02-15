#!/usr/bin/env bash
set -u

# migrate-config.sh — Backfill/rename VBW config keys for brownfield installs.
#
# Usage:
#   bash scripts/migrate-config.sh [path/to/config.json]
#
# Exit codes:
#   0 = success (including no-op when config file missing)
#   1 = malformed config or migration failure

PRINT_ADDED=false
if [ "${1:-}" = "--print-added" ]; then
  PRINT_ADDED=true
  shift
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found; cannot migrate config." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="$SCRIPT_DIR/../config/defaults.json"
CONFIG_FILE="${1:-.vbw-planning/config.json}"

if [ ! -f "$DEFAULTS_FILE" ]; then
  echo "ERROR: defaults.json not found: $DEFAULTS_FILE" >&2
  exit 1
fi

if ! jq empty "$DEFAULTS_FILE" >/dev/null 2>&1; then
  echo "ERROR: defaults.json is malformed: $DEFAULTS_FILE" >&2
  exit 1
fi

# No project initialized yet — nothing to migrate.
if [ ! -f "$CONFIG_FILE" ]; then
  if [ "$PRINT_ADDED" = true ]; then
    echo "0"
  fi
  exit 0
fi

# Fail-fast on malformed JSON.
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ERROR: Config migration failed (malformed JSON): $CONFIG_FILE" >&2
  exit 1
fi

missing_defaults_count() {
  jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$DEFAULTS_FILE" "$CONFIG_FILE" 2>/dev/null
}

MISSING_BEFORE=$(missing_defaults_count)

apply_update() {
  local filter="$1"
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$CONFIG_FILE" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$CONFIG_FILE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Rename legacy key: agent_teams -> prefer_teams
# Mapping:
#   true  -> "always"
#   false -> "auto"
if jq -e 'has("agent_teams") and (has("prefer_teams") | not)' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: (if .agent_teams == true then "always" else "auto" end)} | del(.agent_teams)'; then
    echo "ERROR: Config migration failed while renaming agent_teams." >&2
    exit 1
  fi
elif jq -e 'has("agent_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  # prefer_teams already exists — drop stale key only.
  if ! apply_update 'del(.agent_teams)'; then
    echo "ERROR: Config migration failed while removing stale agent_teams." >&2
    exit 1
  fi
fi

# Ensure required top-level keys exist.
if ! jq -e 'has("model_profile")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_profile: "quality"}'; then
    echo "ERROR: Config migration failed while adding model_profile." >&2
    exit 1
  fi
fi

if ! jq -e 'has("model_overrides")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_overrides: {}}'; then
    echo "ERROR: Config migration failed while adding model_overrides." >&2
    exit 1
  fi
fi

if ! jq -e 'has("prefer_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: "always"}'; then
    echo "ERROR: Config migration failed while adding prefer_teams." >&2
    exit 1
  fi
fi


# Generic brownfield merge: add any keys missing from defaults.json.
# Existing project values always win.
TMP=$(mktemp)
if jq --slurpfile defaults "$DEFAULTS_FILE" '$defaults[0] + .' "$CONFIG_FILE" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$CONFIG_FILE"
else
  rm -f "$TMP"
  echo "ERROR: Config migration failed while merging defaults.json." >&2
  exit 1
fi

MISSING_AFTER=$(missing_defaults_count)
ADDED_COUNT=$((MISSING_BEFORE - MISSING_AFTER))
if [ "$ADDED_COUNT" -lt 0 ]; then
  ADDED_COUNT=0
fi

if [ "$PRINT_ADDED" = true ]; then
  echo "$ADDED_COUNT"
fi

exit 0