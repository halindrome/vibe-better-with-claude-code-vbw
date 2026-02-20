#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "worktree-target: outputs valid JSON for a given path" {
  run bash "$SCRIPTS_DIR/worktree-target.sh" /tmp/test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.'
}

@test "worktree-target: method is always prompt" {
  run bash "$SCRIPTS_DIR/worktree-target.sh" /tmp/test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.method == "prompt"'
}

@test "worktree-target: path field matches input" {
  run bash "$SCRIPTS_DIR/worktree-target.sh" /some/custom/path
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.path == "/some/custom/path"'
}

@test "worktree-target: instruction contains ALL file operations" {
  run bash "$SCRIPTS_DIR/worktree-target.sh" /tmp/test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.instruction | test("ALL file operations")'
}

@test "worktree-target: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-target.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-target: handles path with spaces" {
  run bash "$SCRIPTS_DIR/worktree-target.sh" "/tmp/my worktree"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.path == "/tmp/my worktree"'
}
