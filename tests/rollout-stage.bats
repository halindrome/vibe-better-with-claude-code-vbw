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

set_all_managed_flags_false() {
  local config_path="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local tmp
  tmp=$(mktemp)
  if jq --slurpfile stages "$TEST_TEMP_DIR/config/rollout-stages.json" '
    reduce ($stages[0].stages[].flags[]?) as $f (. ; .[$f] = false)
  ' "$config_path" > "$tmp"; then
    mv "$tmp" "$config_path"
  else
    rm -f "$tmp"
    return 1
  fi
}

stage_flag_count() {
  local stage="$1"
  jq -r --argjson stage "$stage" '[.stages[] | select(.stage <= $stage) | .flags[]] | length' "$TEST_TEMP_DIR/config/rollout-stages.json"
}

assert_flags_true_upto_stage() {
  local stage="$1"
  local config_path="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local flag val

  for flag in $(jq -r --argjson stage "$stage" '.stages[] | select(.stage <= $stage) | .flags[]' "$TEST_TEMP_DIR/config/rollout-stages.json"); do
    val=$(jq -r --arg f "$flag" '.[$f] // false' "$config_path")
    [ "$val" = "true" ]
  done
}

assert_flags_false_above_stage() {
  local stage="$1"
  local config_path="$TEST_TEMP_DIR/.vbw-planning/config.json"
  local flag val

  for flag in $(jq -r --argjson stage "$stage" '.stages[] | select(.stage > $stage) | .flags[]' "$TEST_TEMP_DIR/config/rollout-stages.json"); do
    val=$(jq -r --arg f "$flag" '.[$f] // false' "$config_path")
    [ "$val" = "false" ]
  done
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
  set_all_managed_flags_false
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  assert_flags_true_upto_stage 1
  assert_flags_false_above_stage 1
}

# --- Test 5: advance stage 2 also enables stage 1 flags ---

@test "rollout-stage: advance stage 2 also enables stage 1 flags" {
  set_all_managed_flags_false
  run_rollout advance --stage=2
  [ "$status" -eq 0 ]
  assert_flags_true_upto_stage 2
  assert_flags_false_above_stage 2
}

@test "rollout-stage: advance stage 3 newly enables only stage-3 flags" {
  set_all_managed_flags_false

  # Prime stage-1 flags first so stage-3 advance should only enable stage-3 flags.
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]

  local stage1_only_count stage3_only_count
  stage1_only_count=$(jq -r '[.stages[] | select(.stage == 1) | .flags[]] | length' "$TEST_TEMP_DIR/config/rollout-stages.json")
  stage3_only_count=$(jq -r '[.stages[] | select(.stage == 3) | .flags[]] | length' "$TEST_TEMP_DIR/config/rollout-stages.json")

  run_rollout advance --stage=3
  [ "$status" -eq 0 ]

  echo "$output" | jq -e ".flags_enabled | length == ${stage3_only_count}"
  echo "$output" | jq -e ".flags_already_enabled | length == ${stage1_only_count}"
  assert_flags_true_upto_stage 3
}

# --- Test 6: advance is idempotent ---

@test "rollout-stage: advance is idempotent" {
  set_all_managed_flags_false
  local stage1_count
  stage1_count=$(stage_flag_count 1)

  # First advance
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  # Second advance (idempotent)
  run_rollout advance --stage=1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.flags_enabled | length == 0'
  echo "$output" | jq -e ".flags_already_enabled | length == ${stage1_count}"
}

# --- Test 7: dry-run does not modify config ---

@test "rollout-stage: dry-run does not modify config" {
  set_all_managed_flags_false
  local before_config after_config stage1_count
  before_config=$(jq -S . "$TEST_TEMP_DIR/.vbw-planning/config.json")
  stage1_count=$(stage_flag_count 1)

  run_rollout advance --stage=1 --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.dry_run == true'
  echo "$output" | jq -e ".flags_enabled | length == ${stage1_count}"

  after_config=$(jq -S . "$TEST_TEMP_DIR/.vbw-planning/config.json")
  [ "$before_config" = "$after_config" ]
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
  set_all_managed_flags_false
  create_event_log 1
  run_rollout advance
  [ "$status" -eq 0 ]
  # With 1 phase, only stage 1 is eligible (stage 2 has no flags, stage 3 requires 5)
  assert_flags_true_upto_stage 1
  assert_flags_false_above_stage 1
}
