#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Bug #2: No destructive git commands in session-start.sh
# =============================================================================

@test "session-start.sh contains no destructive git commands" {
  # Destructive patterns: git reset --hard, git checkout ., git restore ., git clean -f/-fd
  run grep -E 'git (reset --hard|checkout \.|restore \.|clean -f)' "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 1 ]  # grep returns 1 = no matches found
}

@test "session-start.sh marketplace sync uses safe merge" {
  # Must use --ff-only (safe merge) and git diff --quiet (dirty-check guard)
  grep -q '\-\-ff-only' "$SCRIPTS_DIR/session-start.sh"
  grep -q 'git diff --quiet' "$SCRIPTS_DIR/session-start.sh"
}

# =============================================================================
# Bug #3: Atomic writes and locking in update-state.sh
# =============================================================================

@test "update-state.sh uses mkdir-based locking" {
  grep -q 'mkdir' "$SCRIPTS_DIR/update-state.sh"
  grep -q 'LOCK_DIR' "$SCRIPTS_DIR/update-state.sh"
}

@test "update-state.sh uses atomic write pattern (mktemp + mv)" {
  grep -q 'mktemp' "$SCRIPTS_DIR/update-state.sh"
  grep -q 'mv "$TMP"' "$SCRIPTS_DIR/update-state.sh"
}

@test "update-state.sh replace operation is atomic" {
  echo "old_value" > "$TEST_TEMP_DIR/state.txt"
  run bash "$SCRIPTS_DIR/update-state.sh" "$TEST_TEMP_DIR/state.txt" replace "old_value" "new_value"
  [ "$status" -eq 0 ]
  grep -q "new_value" "$TEST_TEMP_DIR/state.txt"
  # Lock directory should be cleaned up after operation
  [ ! -d "$TEST_TEMP_DIR/state.txt.lock" ]
}
