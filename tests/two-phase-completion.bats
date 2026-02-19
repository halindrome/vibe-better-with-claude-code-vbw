#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.artifacts"
  # Enable flags
  jq '.v2_two_phase_completion = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
}

teardown() {
  teardown_temp_dir
}

create_passing_contract() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.contracts/1-1.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"1-1","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/a.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Feature works"],"verification_checks":["true"],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc"}
CONTRACT
}

create_failing_contract() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.contracts/1-1.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"1-1","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/a.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Feature works"],"verification_checks":["false"],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc"}
CONTRACT
}

# --- Two-phase completion ---

@test "two-phase: confirmed when all checks pass" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "all tests pass"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "confirmed"'
  echo "$output" | jq -e '.checks_passed > 0'
}

@test "two-phase: rejected when verification check fails" {
  cd "$TEST_TEMP_DIR"
  create_failing_contract
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "incomplete"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
  echo "$output" | jq -e '.errors | length > 0'
}

@test "two-phase: emits candidate and confirmed events" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "evidence" >/dev/null
  # Check event log
  run cat ".vbw-planning/.events/event-log.jsonl"
  [[ "$output" == *"task_completed_candidate"* ]]
  [[ "$output" == *"task_completed_confirmed"* ]]
}

@test "two-phase: emits rejection event on failure" {
  cd "$TEST_TEMP_DIR"
  create_failing_contract
  bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "bad" 2>/dev/null || true
  run cat ".vbw-planning/.events/event-log.jsonl"
  [[ "$output" == *"task_completed_candidate"* ]]
  [[ "$output" == *"task_completion_rejected"* ]]
}

@test "two-phase: always active (v2_two_phase_completion graduated)" {
  cd "$TEST_TEMP_DIR"
  # v2_two_phase_completion flag graduated - two-phase completion is now always active
  # Missing contract should now return error (not skip)
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 "nonexistent.json" "evidence"
  [ "$status" -eq 2 ]
}

@test "two-phase: missing contract returns error" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 "nonexistent.json" "evidence"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
  echo "$output" | jq -e '.errors[0]' | grep -q "contract file not found"
}

@test "two-phase: rejects when no evidence provided" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
  echo "$output" | jq -e '.errors[] | select(contains("no evidence"))'
}

@test "two-phase: rejects when files_modified outside allowed_paths" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "files_modified=bad/path.js" "some evidence"
  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.result == "rejected"'
  echo "$output" | jq -e '.errors[] | select(contains("outside allowed_paths"))'
}

@test "two-phase: passes when files_modified within allowed_paths" {
  cd "$TEST_TEMP_DIR"
  create_passing_contract
  run bash "$SCRIPTS_DIR/two-phase-complete.sh" "1-1-T1" 1 1 ".vbw-planning/.contracts/1-1.json" "files_modified=src/a.js" "feature works"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "confirmed"'
}

# --- Artifact registry ---

@test "artifact-registry: register creates entry" {
  cd "$TEST_TEMP_DIR"
  echo "test content" > "$TEST_TEMP_DIR/test-artifact.txt"
  run bash "$SCRIPTS_DIR/artifact-registry.sh" register "test-artifact.txt" "evt-001" 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "registered"'
  echo "$output" | jq -e '.checksum != ""'
  # Registry file should exist
  [ -f ".vbw-planning/.artifacts/registry.jsonl" ]
}

@test "artifact-registry: query finds registered artifact" {
  cd "$TEST_TEMP_DIR"
  echo "content" > "$TEST_TEMP_DIR/found.txt"
  bash "$SCRIPTS_DIR/artifact-registry.sh" register "found.txt" "evt-002" 1 1 >/dev/null
  run bash "$SCRIPTS_DIR/artifact-registry.sh" query "found.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "found"'
  echo "$output" | jq -e '.count == 1'
}

@test "artifact-registry: query not found returns empty" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/artifact-registry.sh" query "missing.txt"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "not_found"'
}

@test "artifact-registry: list returns all artifacts" {
  cd "$TEST_TEMP_DIR"
  echo "a" > "$TEST_TEMP_DIR/a.txt"
  echo "b" > "$TEST_TEMP_DIR/b.txt"
  bash "$SCRIPTS_DIR/artifact-registry.sh" register "a.txt" "evt-003" 1 1 >/dev/null
  bash "$SCRIPTS_DIR/artifact-registry.sh" register "b.txt" "evt-004" 1 1 >/dev/null
  run bash "$SCRIPTS_DIR/artifact-registry.sh" list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 2'
}

@test "artifact-registry: list filters by phase" {
  cd "$TEST_TEMP_DIR"
  echo "a" > "$TEST_TEMP_DIR/a.txt"
  echo "b" > "$TEST_TEMP_DIR/b.txt"
  bash "$SCRIPTS_DIR/artifact-registry.sh" register "a.txt" "evt-005" 1 1 >/dev/null
  bash "$SCRIPTS_DIR/artifact-registry.sh" register "b.txt" "evt-006" 2 1 >/dev/null
  run bash "$SCRIPTS_DIR/artifact-registry.sh" list 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.count == 1'
}

@test "artifact-registry: skips when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_two_phase_completion = false' ".vbw-planning/config.json" > ".vbw-planning/config.json.tmp" \
    && mv ".vbw-planning/config.json.tmp" ".vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/artifact-registry.sh" register "any" "evt-000"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2_two_phase_completion=false"* ]]
}

# --- Config flag ---

@test "defaults.json: v2_two_phase_completion flag graduated (removed from defaults)" {
  run jq '.v2_two_phase_completion // "removed"' "$CONFIG_DIR/defaults.json"
  [ "$output" = '"removed"' ]
}

# --- Execute protocol integration ---

@test "execute-protocol references two-phase completion" {
  run grep -c "two-phase-complete.sh" "$PROJECT_ROOT/references/execute-protocol.md"
  [ "$output" -ge 1 ]
}

@test "execute-protocol references all 13 V2 event types" {
  run bash -c "grep -oE 'phase_planned|task_created|task_claimed|task_started|artifact_written|gate_passed|gate_failed|task_completed_candidate|task_completed_confirmed|task_blocked|task_reassigned|shutdown_sent|shutdown_received' '$PROJECT_ROOT/references/execute-protocol.md' | sort -u | wc -l | tr -d ' '"
  [ "$output" -ge 13 ]
}
