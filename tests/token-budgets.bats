#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  # Enable flags
  jq '.v2_token_budgets = true | .v3_metrics = true | .v3_event_log = true' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" \
    && mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  # Copy token budgets config
  mkdir -p "$TEST_TEMP_DIR/config"
  cp "$CONFIG_DIR/token-budgets.json" "$TEST_TEMP_DIR/config/"
}

teardown() {
  teardown_temp_dir
}

generate_chars() {
  # Generate a string of approximately $1 characters (repeating lines of ~55 chars each)
  local target=$1
  local line="Line of content for testing token budget enforcement.\n"
  local line_len=54
  local lines_needed=$(( (target / line_len) + 1 ))
  for i in $(seq 1 "$lines_needed"); do
    printf "Line %04d of content for testing token budget enforce\n" "$i"
  done | head -c "$target"
}

# --- Token budget enforcement ---

@test "token-budget: passes through when within budget" {
  cd "$TEST_TEMP_DIR"
  # Scout budget is 8000 chars — generate 4000
  CONTENT=$(generate_chars 4000)
  run bash -c "echo '$CONTENT' | bash '$SCRIPTS_DIR/token-budget.sh' scout"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  [ "$CHAR_COUNT" -ge 3900 ]
  [ "$CHAR_COUNT" -le 4100 ]
}

@test "token-budget: truncates when over budget" {
  cd "$TEST_TEMP_DIR"
  # Scout has 8000 char budget — generate 12000
  generate_chars 12000 > "$TEST_TEMP_DIR/big-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' scout '$TEST_TEMP_DIR/big-context.txt' 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  # Should be truncated to ~8000 chars (allow small margin for trailing newline)
  [ "$CHAR_COUNT" -le 8100 ]
}

@test "token-budget: dev has higher budget than scout" {
  cd "$TEST_TEMP_DIR"
  # Dev=32000, Scout=8000 — generate 10000 chars
  generate_chars 10000 > "$TEST_TEMP_DIR/dev-context.txt"
  # Dev should pass through (10000 < 32000)
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/dev-context.txt' 2>/dev/null"
  [ "$status" -eq 0 ]
  DEV_CHARS=${#output}
  [ "$DEV_CHARS" -ge 9900 ]
  # Scout should truncate (10000 > 8000)
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' scout '$TEST_TEMP_DIR/dev-context.txt' 2>/dev/null"
  SCOUT_CHARS=${#output}
  [ "$SCOUT_CHARS" -le 8100 ]
}

@test "token-budget: skips when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.v2_token_budgets = false' ".vbw-planning/config.json" > ".vbw-planning/config.json.tmp" \
    && mv ".vbw-planning/config.json.tmp" ".vbw-planning/config.json"
  generate_chars 12000 > "$TEST_TEMP_DIR/no-truncate.txt"
  run bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/no-truncate.txt"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  [ "$CHAR_COUNT" -ge 11900 ]
}

@test "token-budget: logs overage to metrics" {
  cd "$TEST_TEMP_DIR"
  generate_chars 12000 > "$TEST_TEMP_DIR/overage.txt"
  bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/overage.txt" >/dev/null 2>&1
  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  run cat ".vbw-planning/.metrics/run-metrics.jsonl"
  [[ "$output" == *"token_overage"* ]]
  [[ "$output" == *"scout"* ]]
}

# --- Per-task budget tests (REQ-02) ---

@test "token-budget: computes per-task budget from contract metadata" {
  cd "$TEST_TEMP_DIR"
  # Contract: 3 must_haves, 4 allowed_paths, 0 depends_on
  # Score: 3*1 + 4*2 + 0*3 = 11 -> standard tier -> multiplier 1.0
  # Dev base 32000 * 1.0 = 32000
  jq -n '{phase:2, plan:1, task_count:3, must_haves:["a","b","c"], allowed_paths:["f1","f2","f3","f4"], depends_on:[]}' \
    > "$TEST_TEMP_DIR/contract.json"
  generate_chars 30000 > "$TEST_TEMP_DIR/task-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/task-context.txt' '$TEST_TEMP_DIR/contract.json' 1 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  # 30000 < 32000 budget, so all pass through
  [ "$CHAR_COUNT" -ge 29900 ]
}

@test "token-budget: applies higher multiplier for complex tasks" {
  cd "$TEST_TEMP_DIR"
  # Contract: 8 must_haves, 6 files, 1 dep
  # Score: 8*1 + 6*2 + 1*3 = 23 -> heavy tier -> multiplier 1.6
  # Dev base 32000 * 1.6 = 51200
  jq -n '{phase:2, plan:1, task_count:3, must_haves:["a","b","c","d","e","f","g","h"], allowed_paths:["f1","f2","f3","f4","f5","f6"], depends_on:["dep1"]}' \
    > "$TEST_TEMP_DIR/contract.json"
  generate_chars 48000 > "$TEST_TEMP_DIR/task-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/task-context.txt' '$TEST_TEMP_DIR/contract.json' 1 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  # 48000 < 51200 budget, so all pass through
  [ "$CHAR_COUNT" -ge 47900 ]
}

@test "token-budget: applies lower multiplier for simple tasks" {
  cd "$TEST_TEMP_DIR"
  # Contract: 1 must_have, 1 file, 0 deps
  # Score: 1*1 + 1*2 + 0*3 = 3 -> simple tier -> multiplier 0.6
  # Dev base 32000 * 0.6 = 19200
  jq -n '{phase:2, plan:1, task_count:1, must_haves:["a"], allowed_paths:["f1"], depends_on:[]}' \
    > "$TEST_TEMP_DIR/contract.json"
  generate_chars 25000 > "$TEST_TEMP_DIR/task-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/task-context.txt' '$TEST_TEMP_DIR/contract.json' 1 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  # 25000 > 19200 budget, should be truncated
  [ "$CHAR_COUNT" -le 19300 ]
}

@test "token-budget: falls back to per-role when no contract" {
  cd "$TEST_TEMP_DIR"
  # No contract args -> per-role fallback -> dev = 32000
  generate_chars 40000 > "$TEST_TEMP_DIR/fallback-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/fallback-context.txt' 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  [ "$CHAR_COUNT" -le 32100 ]
}

@test "token-budget: falls back to per-role when contract file missing" {
  cd "$TEST_TEMP_DIR"
  # Pass nonexistent contract path -> fallback -> dev = 32000
  generate_chars 40000 > "$TEST_TEMP_DIR/fallback-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/fallback-context.txt' '$TEST_TEMP_DIR/nonexistent.json' 1 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  [ "$CHAR_COUNT" -le 32100 ]
}

@test "token-budget: includes budget_source in metrics" {
  cd "$TEST_TEMP_DIR"
  # Create contract to trigger per-task budget
  jq -n '{phase:2, plan:1, task_count:1, must_haves:["a"], allowed_paths:["f1"], depends_on:[]}' \
    > "$TEST_TEMP_DIR/contract.json"
  generate_chars 25000 > "$TEST_TEMP_DIR/source-context.txt"
  bash "$SCRIPTS_DIR/token-budget.sh" dev "$TEST_TEMP_DIR/source-context.txt" "$TEST_TEMP_DIR/contract.json" 1 >/dev/null 2>&1
  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  run cat ".vbw-planning/.metrics/run-metrics.jsonl"
  [[ "$output" == *"budget_source"* ]]
  [[ "$output" == *"task"* ]]
}

# --- Truncation strategy tests ---

@test "token-budget: head strategy preserves beginning of content" {
  cd "$TEST_TEMP_DIR"
  # Create content with a known marker at the start
  printf 'GOAL_MARKER_START\n' > "$TEST_TEMP_DIR/strategy-context.txt"
  generate_chars 12000 >> "$TEST_TEMP_DIR/strategy-context.txt"
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' scout '$TEST_TEMP_DIR/strategy-context.txt' 2>/dev/null"
  [ "$status" -eq 0 ]
  # Head strategy (default) should preserve the start
  [[ "$output" == *"GOAL_MARKER_START"* ]]
}

# --- No escalation ---

@test "token-budget: no cross-task escalation on overage" {
  cd "$TEST_TEMP_DIR"
  jq -n '{phase:2, plan:1, task_count:3, must_haves:["a","b","c"], allowed_paths:["f1","f2","f3","f4"], depends_on:[]}' \
    > "$TEST_TEMP_DIR/2-1.json"
  generate_chars 40000 > "$TEST_TEMP_DIR/overage-context.txt"
  # First call triggers truncation
  bash "$SCRIPTS_DIR/token-budget.sh" dev "$TEST_TEMP_DIR/overage-context.txt" "$TEST_TEMP_DIR/2-1.json" 1 >/dev/null 2>&1
  # Second call should get the same full budget (no reduction)
  run bash -c "bash '$SCRIPTS_DIR/token-budget.sh' dev '$TEST_TEMP_DIR/overage-context.txt' '$TEST_TEMP_DIR/2-1.json' 2 2>/dev/null"
  [ "$status" -eq 0 ]
  CHAR_COUNT=${#output}
  # Should still get full 32000 budget, not a reduced one
  [ "$CHAR_COUNT" -ge 31900 ]
  [ "$CHAR_COUNT" -le 32100 ]
}

# --- Metrics report ---

@test "metrics-report: produces markdown with no data" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/metrics-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Metrics Report"* ]] || [[ "$output" == *"Observability Report"* ]]
}

@test "metrics-report: produces summary table with event data" {
  cd "$TEST_TEMP_DIR"
  # Create some event data
  echo '{"ts":"2026-01-01","event":"task_started","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"task_completed_confirmed","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  run bash "$SCRIPTS_DIR/metrics-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary"* ]]
  [[ "$output" == *"Tasks started"* ]]
  [[ "$output" == *"Tasks confirmed"* ]]
}

@test "metrics-report: includes gate failure rate" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_passed","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01","event":"gate_failed","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  run bash "$SCRIPTS_DIR/metrics-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gate Failure Rate"* ]]
  [[ "$output" == *"33%"* ]]
}

@test "metrics-report: computes median task latency" {
  cd "$TEST_TEMP_DIR"
  # Create matched start/confirm events with real timestamps and task_id data
  echo '{"ts":"2026-01-01T10:00:00Z","event":"task_started","phase":1,"data":{"task_id":"t1"}}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:05:00Z","event":"task_completed_confirmed","phase":1,"data":{"task_id":"t1"}}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:10:00Z","event":"task_started","phase":1,"data":{"task_id":"t2"}}' >> ".vbw-planning/.events/event-log.jsonl"
  echo '{"ts":"2026-01-01T10:20:00Z","event":"task_completed_confirmed","phase":1,"data":{"task_id":"t2"}}' >> ".vbw-planning/.events/event-log.jsonl"
  run bash "$SCRIPTS_DIR/metrics-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Median latency"* ]]
  # Should not be N/A since we have matched pairs
  [[ "$output" != *"Median latency: N/A"* ]]
}

@test "metrics-report: shows profile info in summary" {
  cd "$TEST_TEMP_DIR"
  echo '{"ts":"2026-01-01","event":"task_started","phase":1}' >> ".vbw-planning/.events/event-log.jsonl"
  run bash "$SCRIPTS_DIR/metrics-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"effort=balanced"* ]]
  [[ "$output" == *"autonomy=standard"* ]]
}

# --- Config flag ---

@test "defaults.json includes v2_token_budgets flag" {
  run jq '.v2_token_budgets' "$CONFIG_DIR/defaults.json"
  [ "$output" = "false" ]
}

# --- Token budgets config ---

@test "token-budgets.json has all 6 roles" {
  run jq '.budgets | keys | length' "$CONFIG_DIR/token-budgets.json"
  [ "$output" = "6" ]
}

@test "token-budgets.json scout cap is lowest" {
  SCOUT=$(jq '.budgets.scout.max_chars' "$CONFIG_DIR/token-budgets.json")
  DEV=$(jq '.budgets.dev.max_chars' "$CONFIG_DIR/token-budgets.json")
  [ "$SCOUT" -lt "$DEV" ]
}

# --- Protocol integration ---

@test "execute-protocol references token budgets" {
  run grep -c "token_budget" "$PROJECT_ROOT/references/execute-protocol.md"
  [ "$output" -ge 1 ]
}

@test "execute-protocol references metrics report" {
  run grep -c "metrics-report.sh" "$PROJECT_ROOT/references/execute-protocol.md"
  [ "$output" -ge 1 ]
}
