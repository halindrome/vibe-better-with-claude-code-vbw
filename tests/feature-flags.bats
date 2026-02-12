#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "defaults.json includes all 4 V3 feature flags" {
  run jq -r '.v3_delta_context, .v3_context_cache, .v3_plan_research_persist, .v3_metrics' "$CONFIG_DIR/defaults.json"
  [ "$status" -eq 0 ]
  # All should be false by default
  echo "$output" | grep -c "false" | grep -q "4"
}

@test "V3 flags default to false in test config" {
  run jq -r '.v3_context_cache' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "V3 flags can be toggled to true" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run jq -r '.v3_context_cache' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
