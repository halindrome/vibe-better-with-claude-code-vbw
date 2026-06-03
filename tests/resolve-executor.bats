#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  mkdir -p "$PROJECT_DIR/.vbw-planning"
  CONFIG="$PROJECT_DIR/.vbw-planning/config.json"
}

teardown() {
  teardown_temp_dir
}

resolve() {
  bash "$SCRIPTS_DIR/resolve-executor.sh" "$@"
}

@test "never mode always falls back regardless of fanout/support" {
  run resolve --mode --fanout 500 --workflows-mode never --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "unsupported runtime falls back even when always" {
  run resolve --mode --fanout 500 --workflows-mode always --supported false
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "always + supported + wide fanout selects workflow" {
  run resolve --mode --fanout 4 --workflows-mode always --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "workflow" ]
}

@test "always + supported but fanout below minimum falls back" {
  run resolve --mode --fanout 1 --workflows-mode always --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "auto selects workflow only at or above threshold" {
  run resolve --mode --fanout 25 --threshold 25 --workflows-mode auto --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "workflow" ]

  run resolve --mode --fanout 24 --threshold 25 --workflows-mode auto --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "non-integer fanout falls back" {
  run resolve --mode --fanout abc --workflows-mode always --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "reads workflows mode from config when not overridden" {
  echo '{ "workflows": "always" }' > "$CONFIG"
  run resolve --mode --fanout 5 --config "$CONFIG" --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "workflow" ]
}

@test "missing config defaults to auto (below threshold -> fallback)" {
  run resolve --mode --fanout 3 --config "$PROJECT_DIR/.vbw-planning/none.json" --threshold 25 --supported true
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}

@test "default output emits executor and reason keys" {
  run resolve --fanout 50 --workflows-mode auto --threshold 25 --supported true
  [ "$status" -eq 0 ]
  [[ "$output" == *"executor=workflow"* ]]
  [[ "$output" == *"reason=auto_fanout_meets_threshold"* ]]
}

@test "detection override absent: real probe with env kill switch forces fallback" {
  export CLAUDE_CODE_DISABLE_WORKFLOWS=1
  run resolve --mode --fanout 50 --workflows-mode always --project "$PROJECT_DIR"
  unset CLAUDE_CODE_DISABLE_WORKFLOWS
  [ "$status" -eq 0 ]
  [ "$output" = "fallback" ]
}
