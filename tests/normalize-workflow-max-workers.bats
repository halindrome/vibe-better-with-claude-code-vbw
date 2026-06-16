#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

run_normalizer() {
  bash "$SCRIPTS_DIR/normalize-workflow-max-workers.sh" "$@"
}

@test "defaults missing config to 4" {
  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/missing.json"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "reads workflow_max_workers value from config" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "workflow_max_workers": 8
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "8" ]
}

@test "config without the key defaults to 4" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "zero is preserved (no VBW cap)" {
  run run_normalizer --value 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "--value reads an explicit positive integer" {
  run run_normalizer --value 12
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "non-integer value falls back to 4" {
  run run_normalizer --value abc
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "negative value falls back to 4" {
  run run_normalizer --value -3
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "null value falls back to 4" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "workflow_max_workers": null
}
EOF

  run run_normalizer "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}
