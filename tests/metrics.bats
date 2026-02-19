#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase"
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
EOF
}

teardown() {
  teardown_temp_dir
}

@test "collect-metrics.sh creates .metrics dir" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/collect-metrics.sh" cache_hit 2 1 role=dev
  [ "$status" -eq 0 ]
  [ -d ".vbw-planning/.metrics" ]
}

@test "collect-metrics.sh appends valid JSONL" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/collect-metrics.sh" cache_hit 2 1 role=dev
  bash "$SCRIPTS_DIR/collect-metrics.sh" compile_context 2 role=lead duration_ms=100

  # Should have 2 lines
  LINE_COUNT=$(wc -l < ".vbw-planning/.metrics/run-metrics.jsonl" | tr -d ' ')
  [ "$LINE_COUNT" -eq 2 ]

  # Each line should be valid JSON
  while IFS= read -r line; do
    echo "$line" | jq -e '.' >/dev/null 2>&1
  done < ".vbw-planning/.metrics/run-metrics.jsonl"
}

@test "collect-metrics.sh includes key=value data pairs" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/collect-metrics.sh" compile_context 2 role=dev duration_ms=50 delta_files=3
  run jq -r '.data.role' ".vbw-planning/.metrics/run-metrics.jsonl"
  [ "$output" = "dev" ]
  run jq -r '.data.delta_files' ".vbw-planning/.metrics/run-metrics.jsonl"
  [ "$output" = "3" ]
}

@test "compile-context.sh emits metrics when v3_metrics=true" {
  cd "$TEST_TEMP_DIR"

  cat > ".vbw-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test
EOF

  bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ -f ".vbw-planning/.metrics/run-metrics.jsonl" ]
  grep -q "compile_context" ".vbw-planning/.metrics/run-metrics.jsonl"
}

