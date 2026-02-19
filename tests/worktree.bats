#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# worktree-create.sh tests
# ---------------------------------------------------------------------------

@test "worktree-create: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-create.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-create: idempotent when worktree dir already exists" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-worktrees/01-01"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
  [[ "$output" == *".vbw-worktrees/01-01" ]]
}

@test "worktree-create: fail-open when not a git repo" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# worktree-merge.sh tests
# ---------------------------------------------------------------------------

@test "worktree-merge: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-merge.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-merge: outputs conflict when branch does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

@test "worktree-merge: outputs conflict when not in a git repo" {
  local subdir="$TEST_TEMP_DIR/sub"
  mkdir -p "$subdir"
  cd "$subdir"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

# ---------------------------------------------------------------------------
# worktree-cleanup.sh tests
# ---------------------------------------------------------------------------

@test "worktree-cleanup: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: exits 0 when worktree does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: clears agent-worktree JSON matching phase-plan" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/.agent-worktrees
  echo '{}' > .vbw-planning/.agent-worktrees/agent-01-01.json
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-worktrees/agent-01-01.json" ]
}
