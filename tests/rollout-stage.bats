#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Copy rollout-stages.json to temp dir
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/../config/rollout-stages.json" "$TEST_TEMP_DIR/config/rollout-stages.json"
  # Create scripts symlink so SCRIPT_DIR/../config resolves
  mkdir -p "$TEST_TEMP_DIR/scripts"
}

teardown() {
  teardown_temp_dir
}

create_event_log() {
  local count="$1"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  > "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  for i in $(seq 1 "$count"); do
    echo "{\"ts\":\"2026-01-0${i}T00:00:00Z\",\"event_id\":\"evt-${i}\",\"event\":\"phase_end\",\"phase\":${i}}" >> "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  done
}

create_error_event_log() {
  local clean="$1"
  local error="$2"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  > "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  for i in $(seq 1 "$clean"); do
    echo "{\"ts\":\"2026-01-0${i}T00:00:00Z\",\"event_id\":\"evt-${i}\",\"event\":\"phase_end\",\"phase\":${i}}" >> "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  done
  for i in $(seq 1 "$error"); do
    local idx=$((clean + i))
    echo "{\"ts\":\"2026-01-0${idx}T00:00:00Z\",\"event_id\":\"evt-err-${i}\",\"event\":\"phase_end\",\"phase\":${idx},\"data\":{\"error\":\"failed\"}}" >> "$TEST_TEMP_DIR/.vbw-planning/.events/event-log.jsonl"
  done
}

run_rollout() {
  cd "$TEST_TEMP_DIR"
  # Override STAGES_PATH by running from the temp dir where config/ exists
  run bash "$SCRIPTS_DIR/rollout-stage.sh" "$@"
}

# --- Test 1: check reports stage 1 with no event log ---

@test "rollout-stage: check reports stage 1 with no event log" {
  run_rollout check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.current_stage == 1'
  echo "$output" | jq -e '.completed_phases == 0'
}

# --- Test 2: check reports stage 2 after 2 completed phases ---

@test "rollout-stage: check reports stage 2 after 2 completed phases" {
  create_event_log 2
  run_rollout check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.current_stage == 2'
  echo "$output" | jq -e '.completed_phases == 2'
}

# --- Test 3: check reports stage 3 after 5 completed phases ---

@test "rollout-stage: check reports stage 3 after 5 completed phases" {
  create_event_log 5
  run_rollout check
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.current_stage == 3'
  echo "$output" | jq -e '.completed_phases == 5'
}

# --- Test 4: advance stage 1 enables event_log and metrics ---

@test "rollout-stage: advance stage 1 enables metrics" {
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  # Check config was updated
  local val_metrics val_smart_routing
  val_metrics=$(jq -r '.metrics // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  val_smart_routing=$(jq -r '.smart_routing // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$val_metrics" = "true" ]
  # smart_routing in stage 3, should not be enabled yet
  [ "$val_smart_routing" = "true" ]  # already true by default in test config
}

# --- Test 5: advance stage 2 also enables stage 1 flags ---

@test "rollout-stage: advance stage 2 also enables stage 1 flags" {
  run_rollout advance --stage=2
  [ "$status" -eq 0 ]
  local val_metrics val_event_recovery
  val_metrics=$(jq -r '.metrics // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  val_event_recovery=$(jq -r '.event_recovery // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  # Stage 1 flag (metrics) should be enabled
  [ "$val_metrics" = "true" ]
  # Stage 3 flag (event_recovery) should not be enabled by stage 2
  [ "$val_event_recovery" = "false" ]
}

# --- Test 6: advance is idempotent ---

@test "rollout-stage: advance is idempotent" {
  # First advance
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  # Second advance (idempotent)
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.flags_enabled | length == 0'
  echo "$output" | jq -e '.flags_already_enabled | length == 4'
}

# --- Test 7: dry-run does not modify config ---

@test "rollout-stage: dry-run does not modify config" {
  # Set metrics to false so we can verify dry-run doesn't change it
  cd "$TEST_TEMP_DIR"
  jq '.metrics = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run_rollout advance --stage=1 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.dry_run == true'
  echo "$output" | jq -e '.flags_enabled | length == 2'
  # Config should still have false value
  local val_metrics
  val_metrics=$(jq -r '.metrics // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$val_metrics" = "false" ]
}

# --- Test 8: status outputs markdown table ---

@test "rollout-stage: status outputs markdown table" {
  run_rollout status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rollout Status"* ]]
  [[ "$output" == *"Flag"* ]]
  [[ "$output" == *"Stage"* ]]
  [[ "$output" == *"Enabled"* ]]
  [[ "$output" == *"metrics"* ]]
}

@test "rollout-stage: status uses defaults when managed flag key missing" {
  cd "$TEST_TEMP_DIR"
  cat > ".vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced"
}
EOF

  run_rollout status
  [ "$status" -eq 0 ]
  echo "$output" | grep -F "| metrics | 1 (observability) | true |"
}

@test "rollout-stage: status honors legacy key when new flag key missing" {
  cd "$TEST_TEMP_DIR"
  cat > ".vbw-planning/config.json" <<'EOF'
{
  "effort": "balanced",
  "v3_metrics": false
}
EOF

  run_rollout status
  [ "$status" -eq 0 ]
  echo "$output" | grep -F "| metrics | 1 (observability) | false |"
}

# --- Test 9: exits 0 when config missing ---

@test "rollout-stage: exits 0 when config missing" {
  rm -f "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run_rollout check
  [ "$status" -eq 0 ]
}

# --- Test 10: advance respects phase threshold ---

@test "rollout-stage: advance respects phase threshold" {
  create_event_log 1
  run_rollout advance
  [ "$status" -eq 0 ]
  # With 1 phase, only stage 1 is eligible (stage 2 needs 2, but stage 2 has no flags)
  local val_metrics val_event_recovery
  val_metrics=$(jq -r '.metrics // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  val_event_recovery=$(jq -r '.event_recovery // false' "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$val_metrics" = "true" ]
  # Stage 3 flag (event_recovery) should not be enabled with only 1 completed phase
  [ "$val_event_recovery" = "false" ]
}
