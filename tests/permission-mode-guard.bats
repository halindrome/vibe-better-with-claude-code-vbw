#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "permission_mode_guard defaults to false" {
  create_test_config
  run jq -r '.permission_mode_guard // "false"' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "permission_mode_guard reads as true when enabled" {
  create_test_config
  local tmp
  tmp=$(mktemp)
  jq '.permission_mode_guard = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$tmp"
  mv "$tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run jq -r '.permission_mode_guard' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "migration backfills permission_mode_guard for brownfield config" {
  cat > "$TEST_TEMP_DIR/.vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "autonomy": "standard"
}
EOF
  bash "$SCRIPTS_DIR/migrate-config.sh" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run jq -r '.permission_mode_guard' "$TEST_TEMP_DIR/.vbw-planning/config.json"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
