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

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found; cannot migrate config." >&2
  exit 1
fi

CONFIG_FILE="${1:-.vbw-planning/config.json}"

# No project initialized yet — nothing to migrate.
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

# Fail-fast on malformed JSON.
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ERROR: Config migration failed (malformed JSON): $CONFIG_FILE" >&2
  exit 1
fi

# Version marker: number of expected migrated keys.
EXPECTED_FLAG_COUNT=23

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
  if ! apply_update '. + {prefer_teams: (if (.agent_teams // true) == true then "always" else "auto" end)} | del(.agent_teams)'; then
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

# Check if migration is needed: count how many expected keys already exist.
CURRENT_FLAG_COUNT=$(jq '[
  has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
  has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
  has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
  has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
  has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
  has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
  has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
  has("model_overrides"), has("prefer_teams")
] | map(select(.)) | length' "$CONFIG_FILE" 2>/dev/null)

if [ "${CURRENT_FLAG_COUNT:-0}" -lt "$EXPECTED_FLAG_COUNT" ]; then
  if ! apply_update '
    . +
    (if has("context_compiler") then {} else {context_compiler: true} end) +
    (if has("v3_delta_context") then {} else {v3_delta_context: false} end) +
    (if has("v3_context_cache") then {} else {v3_context_cache: false} end) +
    (if has("v3_plan_research_persist") then {} else {v3_plan_research_persist: false} end) +
    (if has("v3_metrics") then {} else {v3_metrics: false} end) +
    (if has("v3_contract_lite") then {} else {v3_contract_lite: false} end) +
    (if has("v3_lock_lite") then {} else {v3_lock_lite: false} end) +
    (if has("v3_validation_gates") then {} else {v3_validation_gates: false} end) +
    (if has("v3_smart_routing") then {} else {v3_smart_routing: false} end) +
    (if has("v3_event_log") then {} else {v3_event_log: false} end) +
    (if has("v3_schema_validation") then {} else {v3_schema_validation: false} end) +
    (if has("v3_snapshot_resume") then {} else {v3_snapshot_resume: false} end) +
    (if has("v3_lease_locks") then {} else {v3_lease_locks: false} end) +
    (if has("v3_event_recovery") then {} else {v3_event_recovery: false} end) +
    (if has("v3_monorepo_routing") then {} else {v3_monorepo_routing: false} end) +
    (if has("v2_hard_contracts") then {} else {v2_hard_contracts: false} end) +
    (if has("v2_hard_gates") then {} else {v2_hard_gates: false} end) +
    (if has("v2_typed_protocol") then {} else {v2_typed_protocol: false} end) +
    (if has("v2_role_isolation") then {} else {v2_role_isolation: false} end) +
    (if has("v2_two_phase_completion") then {} else {v2_two_phase_completion: false} end) +
    (if has("v2_token_budgets") then {} else {v2_token_budgets: false} end) +
    (if has("model_overrides") then {} else {model_overrides: {}} end) +
    (if has("prefer_teams") then {} else {prefer_teams: "always"} end)
  '; then
    echo "ERROR: Config migration failed while backfilling feature flags." >&2
    exit 1
  fi
fi

exit 0