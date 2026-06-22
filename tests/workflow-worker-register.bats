#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PLANNING="$TEST_TEMP_DIR/.vbw-planning"
  export VBW_PLANNING_DIR="$PLANNING"
  SID="testsess-abc123"
  COUNT_FILE="$PLANNING/.active-agents/$SID/active-agent-count"
  # Ensure no ambient session id leaks into the explicit-arg tests.
  unset CLAUDE_SESSION_ID || true
}

teardown() {
  teardown_temp_dir
}

# Helper: read the per-session count via the shared lib, exactly as file-guard does.
session_count() {
  bash -c '
    . "'"$SCRIPTS_DIR"'/lib/active-agent-state.sh"
    vbw_active_agent_current_count "'"$PLANNING"'" "{\"session_id\":\"'"$SID"'\"}"
  '
}

@test "workflow-worker-register: register increments the per-session active-agent count" {
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-05
  [ "$status" -eq 0 ]
  [ -f "$COUNT_FILE" ]
  [ "$(cat "$COUNT_FILE")" = "1" ]
}

@test "workflow-worker-register: registered worker is visible to file-guard's count check" {
  bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-05
  run session_count
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "workflow-worker-register: release decrements back to zero (state dir removed)" {
  bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-05
  [ -f "$COUNT_FILE" ]
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" release "$SID" dev 23-05
  [ "$status" -eq 0 ]
  # Decrement to zero tears the per-session bucket down.
  run session_count
  [ "$status" -eq 0 ]
  [ "${output:-0}" -eq 0 ]
}

@test "workflow-worker-register: two concurrent workers ref-count to 2" {
  bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-03
  bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-04
  [ "$(cat "$COUNT_FILE")" = "2" ]
}

@test "workflow-worker-register: falls back to CLAUDE_SESSION_ID when session arg is empty" {
  export CLAUDE_SESSION_ID="$SID"
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "" dev 23-05
  [ "$status" -eq 0 ]
  [ -f "$COUNT_FILE" ]
  [ "$(cat "$COUNT_FILE")" = "1" ]
}

@test "workflow-worker-register: defaults role to dev when omitted" {
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID"
  [ "$status" -eq 0 ]
  [ "$(cat "$COUNT_FILE")" = "1" ]
}

@test "workflow-worker-register: unknown verb is a no-op and exits 0" {
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" bogus "$SID" dev 23-05
  [ "$status" -eq 0 ]
  [ ! -f "$COUNT_FILE" ]
}

@test "workflow-worker-register: fail-open when no .vbw-planning exists" {
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/nonexistent-planning"
  run bash "$SCRIPTS_DIR/workflow-worker-register.sh" register "$SID" dev 23-05
  [ "$status" -eq 0 ]
}
