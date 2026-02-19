#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
}

teardown() {
  teardown_temp_dir
}

@test "set creates JSON file for agent" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/my-worktree
  [ "$status" -eq 0 ]
  [ -f ".vbw-planning/.agent-worktrees/myagent.json" ]
}

@test "set JSON contains correct fields" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/my-worktree
  [ "$status" -eq 0 ]
  local json_file=".vbw-planning/.agent-worktrees/myagent.json"
  jq -e '.agent == "myagent"' "$json_file"
  jq -e '.worktree_path == "/tmp/my-worktree"' "$json_file"
  jq -e '.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$json_file"
}

@test "set creates storage dir if missing" {
  cd "$TEST_TEMP_DIR"
  rm -rf ".vbw-planning/.agent-worktrees"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set newagent /some/path
  [ "$status" -eq 0 ]
  [ -d ".vbw-planning/.agent-worktrees" ]
}

@test "get returns worktree path" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/my-worktree
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" get myagent
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/my-worktree" ]
}

@test "get exits 0 when agent not found" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" get nonexistent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clear removes mapping" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/my-worktree
  [ -f ".vbw-planning/.agent-worktrees/myagent.json" ]
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" clear myagent
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-worktrees/myagent.json" ]
}

@test "clear exits 0 when agent not found" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" clear nonexistent
  [ "$status" -eq 0 ]
}

@test "exits 0 with no arguments" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh"
  [ "$status" -eq 0 ]
}

@test "exits 0 with unknown subcommand" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" bogus myagent
  [ "$status" -eq 0 ]
}

@test "set overwrites existing mapping" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/old-path
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set myagent /tmp/new-path
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" get myagent
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/new-path" ]
}
