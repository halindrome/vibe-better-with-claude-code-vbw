#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  # Isolate user-level settings into the temp dir so host config never leaks in.
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  mkdir -p "$PROJECT_DIR/.claude"
  unset CLAUDE_CODE_DISABLE_WORKFLOWS
}

teardown() {
  unset CLAUDE_CODE_DISABLE_WORKFLOWS
  unset CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

run_detect() {
  bash "$SCRIPTS_DIR/detect-workflows-support.sh" "$@"
}

@test "supported when no disable signal present" {
  run run_detect "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflows_supported=true"* ]]
}

@test "--status prints supported with no disable signal" {
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "supported" ]
}

@test "env kill switch disables (CLAUDE_CODE_DISABLE_WORKFLOWS=1)" {
  export CLAUDE_CODE_DISABLE_WORKFLOWS=1
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "unsupported" ]
}

@test "env kill switch accepts truthy strings" {
  export CLAUDE_CODE_DISABLE_WORKFLOWS=true
  run run_detect "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflows_supported=false"* ]]
  [[ "$output" == *"CLAUDE_CODE_DISABLE_WORKFLOWS"* ]]
}

@test "env value 0 does not disable" {
  export CLAUDE_CODE_DISABLE_WORKFLOWS=0
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "supported" ]
}

@test "project settings disableWorkflows true disables" {
  echo '{ "disableWorkflows": true }' > "$PROJECT_DIR/.claude/settings.json"
  run run_detect "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workflows_supported=false"* ]]
  [[ "$output" == *"settings.json"* ]]
}

@test "user settings disableWorkflows true disables" {
  echo '{ "disableWorkflows": true }' > "$CLAUDE_CONFIG_DIR/settings.json"
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "unsupported" ]
}

@test "project-local settings re-enables over project disable" {
  echo '{ "disableWorkflows": true }'  > "$PROJECT_DIR/.claude/settings.json"
  echo '{ "disableWorkflows": false }' > "$PROJECT_DIR/.claude/settings.local.json"
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "supported" ]
}

@test "detection always exits 0 even with malformed settings" {
  echo '{ this is not json' > "$PROJECT_DIR/.claude/settings.json"
  run run_detect --status "$PROJECT_DIR"
  [ "$status" -eq 0 ]
}
