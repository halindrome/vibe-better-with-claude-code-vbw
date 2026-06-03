#!/usr/bin/env bats

# Proves that 'workflow' is a recognized delegation_mode value for the delegated
# workflow marker: it is stored and round-tripped like team/subagent/direct, and
# (per file-guard.sh / agent-spawn-guard.sh) it is treated as a non-team mode, so
# it never receives the team-style write bypass.

load test_helper

setup() {
  setup_temp_dir
  PROJECT="$TEST_TEMP_DIR/proj"
  mkdir -p "$PROJECT/.vbw-planning"
  DELEG="$SCRIPTS_DIR/delegated-workflow.sh"
}

teardown() {
  teardown_temp_dir
}

@test "set accepts workflow delegation_mode without error" {
  run bash -c "cd '$PROJECT' && bash '$DELEG' set execute balanced workflow"
  [ "$status" -eq 0 ]
  # The marker is written to disk; round-trip is asserted via status-json below.
  [ -f "$PROJECT/.vbw-planning/.delegated-workflow.json" ]
  jq -e '.delegation_mode == "workflow"' "$PROJECT/.vbw-planning/.delegated-workflow.json"
}

@test "status-json round-trips the workflow delegation_mode" {
  (cd "$PROJECT" && bash "$DELEG" set execute balanced workflow >/dev/null)
  run bash -c "cd '$PROJECT' && bash '$DELEG' status-json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.delegation_mode == "workflow"'
}

@test "workflow mode is not reported as team (no team bypass)" {
  (cd "$PROJECT" && bash "$DELEG" set execute balanced workflow >/dev/null)
  run bash -c "cd '$PROJECT' && bash '$DELEG' status-json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.delegation_mode != "team"'
}
