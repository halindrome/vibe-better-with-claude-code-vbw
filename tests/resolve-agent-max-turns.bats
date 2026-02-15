#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

@test "legacy 2-arg invocation resolves using config/default effort" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "80" ]
}

@test "uses config effort when 3rd argument is omitted" {
  jq '.effort = "thorough"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "120" ]
}

@test "accepts high/medium/low aliases" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" high
  [ "$status" -eq 0 ]
  [ "$output" = "113" ]

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" low
  [ "$status" -eq 0 ]
  [ "$output" = "45" ]
}

@test "supports explicit per-effort object values without multiplier" {
  jq '.agent_max_turns.debugger = {"thorough": 140, "balanced": 90, "fast": 70, "turbo": 50}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" fast
  [ "$status" -eq 0 ]
  [ "$output" = "70" ]
}

@test "returns zero when agent turn budget disabled via false" {
  jq '.agent_max_turns.debugger = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" thorough
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "falls back to defaults when config is missing" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" dev "$TEST_TEMP_DIR/.vbw-planning/does-not-exist.json" turbo
  [ "$status" -eq 0 ]
  [ "$output" = "45" ]
}

@test "falls back to defaults when config is malformed" {
  echo '{ invalid json' > "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" qa "$TEST_TEMP_DIR/.vbw-planning/config.json" balanced
  [ "$status" -eq 0 ]
  [ "$output" = "25" ]
}

@test "rejects invalid agent name" {
  run bash "$SCRIPTS_DIR/resolve-agent-max-turns.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" balanced
  [ "$status" -eq 1 ]
}
