#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

run_normalizer() {
  bash "$SCRIPTS_DIR/normalize-workflows-mode.sh" "$@"
}

@test "normalizer defaults missing config to auto" {
  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/missing.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "normalizer reads workflows value from config" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "workflows": "always"
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]
}

@test "normalizer defaults config without workflows key to auto" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "normalizer preserves canonical values" {
  local value
  for value in always auto never; do
    run run_normalizer --value "$value"
    [ "$status" -eq 0 ]
    [ "$output" = "$value" ]
  done
}

@test "normalizer maps boolean-like and on/off legacy values" {
  run run_normalizer --value true
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]

  run run_normalizer --value false
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]

  run run_normalizer --value on
  [ "$status" -eq 0 ]
  [ "$output" = "always" ]

  run run_normalizer --value off
  [ "$status" -eq 0 ]
  [ "$output" = "never" ]
}

@test "normalizer preserves unknown values for caller validation" {
  run run_normalizer --value bogus
  [ "$status" -eq 0 ]
  [ "$output" = "bogus" ]
}
