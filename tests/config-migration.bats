#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# Helper: Run the migration logic extracted from session-start.sh
run_migration() {
  local config_file="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local EXPECTED_FLAG_COUNT=22

  # Check if migration is needed
  CURRENT_FLAG_COUNT=$(jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides")
  ] | map(select(.)) | length' "$config_file" 2>/dev/null)

  if [ "${CURRENT_FLAG_COUNT:-0}" -lt "$EXPECTED_FLAG_COUNT" ]; then
    TMP=$(mktemp)
    if jq '
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
      (if has("v2_token_budgets") then {} else {v2_token_budgets: false} end)
    ' "$config_file" > "$TMP" 2>/dev/null; then
      mv "$TMP" "$config_file"
      return 0
    else
      rm -f "$TMP"
      return 1
    fi
  fi
  return 0
}

@test "migration handles empty config" {
  # Create config with only non-flag keys
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF

  run_migration

  # Verify all 22 flags were added
  run jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "22" ]

  # Verify context_compiler defaults to true
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  # Verify v3 flags default to false
  run jq -r '.v3_delta_context' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "migration handles partial config" {
  # Create config with some flags present
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "context_compiler": false,
  "v3_delta_context": true,
  "v2_hard_contracts": true
}
EOF

  run_migration

  # Verify all 22 flags exist
  run jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "22" ]

  # Verify existing values were preserved
  run jq -r '.context_compiler' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]

  run jq -r '.v3_delta_context' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -r '.v2_hard_contracts' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "migration handles full config" {
  # Create config with all flags present
  create_test_config

  # Record original content
  BEFORE=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")

  run_migration

  # Verify no changes (idempotent when all flags present)
  AFTER=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$BEFORE" = "$AFTER" ]
}

@test "migration is idempotent" {
  # Start with empty config
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  # Run migration once
  run_migration
  AFTER_FIRST=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")

  # Run migration again
  run_migration
  AFTER_SECOND=$(cat "$TEST_TEMP_DIR/.vbw-planning/config.json")

  # Both runs should produce identical result
  [ "$AFTER_FIRST" = "$AFTER_SECOND" ]

  # Verify flag count is correct
  run jq '[
    has("context_compiler"), has("v3_delta_context"), has("v3_context_cache"),
    has("v3_plan_research_persist"), has("v3_metrics"), has("v3_contract_lite"),
    has("v3_lock_lite"), has("v3_validation_gates"), has("v3_smart_routing"),
    has("v3_event_log"), has("v3_schema_validation"), has("v3_snapshot_resume"),
    has("v3_lease_locks"), has("v3_event_recovery"), has("v3_monorepo_routing"),
    has("v2_hard_contracts"), has("v2_hard_gates"), has("v2_typed_protocol"),
    has("v2_role_isolation"), has("v2_two_phase_completion"), has("v2_token_budgets"),
    has("model_overrides")
  ] | map(select(.)) | length' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "22" ]
}

@test "migration detects malformed JSON" {
  # Create malformed JSON
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  invalid json here
}
EOF

  # Migration should fail gracefully
  run run_migration
  [ "$status" -ne 0 ]

  # Temp file should be cleaned up (tested implicitly by not checking for it)
}
