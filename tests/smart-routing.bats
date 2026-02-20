#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
}

teardown() {
  teardown_temp_dir
}

@test "smart-route: skips scout for turbo effort" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout turbo
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "skip"'
  echo "$output" | jq -e '.agent == "scout"'
}

@test "smart-route: skips scout for fast effort" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout fast
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "skip"'
}

@test "smart-route: includes scout for thorough effort" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout thorough
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "include"'
}

@test "smart-route: skips architect for non-thorough" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" architect balanced
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "skip"'
  echo "$output" | jq -e '.reason | test("architect only for thorough")'
}
