#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
  rm -f /tmp/vbw-model-* 2>/dev/null
}

@test "resolve-agent-settings emits shell-safe assignments for model and max turns" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_AGENT='dev'"* ]]
  [[ "$output" == *"RESOLVED_MODEL='opus'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT='turbo'"* ]]

  eval "$output"
  [ "$RESOLVED_AGENT" = "dev" ]
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "45" ]
  [ "$RESOLVED_EFFORT" = "turbo" ]
}

@test "resolve-agent-settings falls back to config effort when explicit effort omitted" {
  jq '.effort = "thorough"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" qa "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "sonnet" ]
  [ "$RESOLVED_MAX_TURNS" = "38" ]
  [ "$RESOLVED_EFFORT" = "thorough" ]
}

@test "resolve-agent-settings normalizes legacy effort aliases" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" debugger "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" high
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "120" ]
  [ "$RESOLVED_EFFORT" = "thorough" ]
}

@test "resolve-agent-settings preserves disabled max-turn budgets as empty output" {
  jq '.agent_max_turns.dev = false' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" turbo
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "opus" ]
  [ "$RESOLVED_MAX_TURNS" = "" ]
}

@test "resolve-agent-settings rejects invalid agent names" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced
  [ "$status" -eq 1 ]
}

@test "resolve-agent-settings surfaces model resolver errors" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/missing.json" "$CONFIG_DIR/model-profiles.json" balanced
  [ "$status" -eq 1 ]
  [[ "$output" == *"Config not found at $TEST_TEMP_DIR/.vbw-planning/missing.json"* ]]
}

@test "resolve-agent-settings passes the phase-model override through to the model" {
  # quality profile resolves dev -> opus; phase override asks for fable
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced fable
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "fable" ]
  [ "$RESOLVED_EFFORT" = "balanced" ]
}

@test "resolve-agent-settings with an empty phase-model preserves base resolution" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced ""
  [ "$status" -eq 0 ]

  eval "$output"
  [ "$RESOLVED_MODEL" = "opus" ]
}

@test "resolve-agent-settings surfaces an invalid phase-model as an error" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced gpt5
  [ "$status" -eq 1 ]
}

@test "resolve-agent-settings rejects a 6th positional argument" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json" balanced opus extra
  [ "$status" -eq 1 ]
}
