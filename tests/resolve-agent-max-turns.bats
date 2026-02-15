#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "resolves balanced default for debugger" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" balanced
  [ "$status" -eq 0 ]
  [ "$output" = "80" ]
}

@test "scales scalar turn budgets by effort" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" thorough
  [ "$status" -eq 0 ]
  [ "$output" = "113" ]

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" turbo
  [ "$status" -eq 0 ]
  [ "$output" = "45" ]
}

@test "returns zero when agent turn budget disabled via false" {
  jq '.agent_max_turns.debugger = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" thorough
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "returns zero when agent turn budget disabled via zero" {
  jq '.agent_max_turns.debugger = 0' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" balanced
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "supports explicit per-effort object values without multiplier" {
  jq '.agent_max_turns.debugger = {"thorough": 140, "balanced": 90, "fast": 70, "turbo": 50}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" fast
  [ "$status" -eq 0 ]
  [ "$output" = "70" ]
}

@test "rejects invalid agent name" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" balanced
  [ "$status" -eq 1 ]
}

@test "rejects invalid effort name" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" medium
  [ "$status" -eq 1 ]
}
