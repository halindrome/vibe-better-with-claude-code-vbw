#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  # Create a minimal phase directory structure
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  # Create a minimal ROADMAP.md
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'EOF'
# Test Roadmap
## Phase 2: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  # Create a minimal plan
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/02-01-PLAN.md" <<'EOF'
---
phase: 2
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: ["test"]
---
# Test Plan
## Tasks
### Task 1: Test
- **Files:** test.sh
- **Action:** Test
EOF
}

teardown() {
  teardown_temp_dir
}

@test "context-index.json not created when v3_context_cache=false" {
  # OBSOLETE: v3_context_cache graduated (always on)
  # Test retained but now expects context-index to be created
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json" ]
}

@test "context-index.json created on cache miss when v3_context_cache=true" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json" ]

  # Verify the entry has correct role and phase
  ROLE=$(jq -r '.entries | to_entries[0].value.role' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  PHASE=$(jq -r '.entries | to_entries[0].value.phase' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  [ "$ROLE" = "dev" ]
  [ "$PHASE" = "02" ]
}

@test "context-index.json entry has correct structure" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  # Each entry must have path, role, phase, timestamp
  HAS_ALL=$(jq '.entries | to_entries[0].value | has("path") and has("role") and has("phase") and has("timestamp")' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  [ "$HAS_ALL" = "true" ]

  # Path should point to a real cached file
  CACHED_PATH=$(jq -r '.entries | to_entries[0].value.path' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  [ -f "$CACHED_PATH" ]

  # Timestamp should not be empty
  TS=$(jq -r '.entries | to_entries[0].value.timestamp' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  [ -n "$TS" ]
  [ "$TS" != "null" ]
}

@test "context-index.json updated on cache hit" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # First run: cache miss
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  TS1=$(jq -r '.entries | to_entries[0].value.timestamp' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")

  # Wait to ensure timestamp difference
  sleep 1

  # Second run: cache hit (same inputs)
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  TS2=$(jq -r '.entries | to_entries[0].value.timestamp' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")

  # Timestamp should be updated (different from first run)
  [ "$TS1" != "$TS2" ]
}

@test "context-index.json contains entries for multiple roles" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # Compile for three different roles
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 lead ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 qa ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  # Verify 3 distinct entries
  ENTRY_COUNT=$(jq '.entries | keys | length' "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json")
  [ "$ENTRY_COUNT" -eq 3 ]
}

@test "context-index.json survives malformed input" {
  jq '.v3_context_cache = true' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp" && mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  cd "$TEST_TEMP_DIR"
  # Create a corrupted index file
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.cache"
  echo "NOT VALID JSON{{{{" > "$TEST_TEMP_DIR/.vbw-planning/.cache/context-index.json"

  # Compilation should still succeed (index failure is non-fatal)
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev ".vbw-planning/phases" ".vbw-planning/phases/02-test-phase/02-01-PLAN.md"
  [ "$status" -eq 0 ]

  # Context file should still be produced
  [ -f "$TEST_TEMP_DIR/.vbw-planning/phases/02-test-phase/.context-dev.md" ]
}
