#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.locks"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.metrics"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
}

teardown() {
  teardown_temp_dir
}

create_test_plan() {
  cat > "$TEST_TEMP_DIR/test-plan.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
skills_used: []
must_haves:
  - "Feature A works"
---

# Plan

### Task 1: Do something
**Files:** `src/a.js`

### Task 2: Do another thing
**Files:** `src/b.js`
PLAN
}

create_roadmap() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" << 'ROAD'
## Phase 1: Test Phase
**Goal:** Test goal
**Reqs:** REQ-01
**Success:** Tests pass
ROAD
}

enable_flags() {
  local flags="$1"
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq "$flags" ".vbw-planning/config.json" > "$tmp" && mv "$tmp" ".vbw-planning/config.json"
}

# --- No-op tests ---

@test "control-plane: no-op when all flags OFF (pre-task)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].status == "skip"'
  echo "$output" | jq -e '.steps[0].name == "noop"'
}

@test "control-plane: no-op when all flags OFF (post-task)" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].name == "noop"'
}

@test "control-plane: no-op when all flags OFF (compile)" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.context_compiler = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].name == "noop"'
}

@test "control-plane: no-op when all flags OFF (full)" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.context_compiler = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[0].name == "noop"'
}

# --- pre-task tests ---

@test "control-plane: pre-task sequences contract then gate" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_contract_lite = true | .v2_hard_gates = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  echo "$output" | jq -e '.steps[] | select(.name == "gate_contract_compliance") | .status == "skip"'
}

@test "control-plane: pre-task uses lease-lock when v3_lease_locks=true" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lease_locks = true | .v3_lock_lite = true'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1 --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_acquire") | .status == "pass"'
  # Verify lock file created
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]
  # Verify it has TTL (lease-lock adds expires_at)
  jq -e '.expires_at' ".vbw-planning/.locks/1-1-T1.lock"
}

@test "control-plane: pre-task uses lock-lite when v3_lock_lite=true and v3_lease_locks=false" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lock_lite = true | .v3_lease_locks = false'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1 --claimed-files=src/a.js
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_acquire") | .status == "pass"'
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]
  # lock-lite does NOT have expires_at field
  ! jq -e '.expires_at' ".vbw-planning/.locks/1-1-T1.lock" 2>/dev/null || \
    [ "$(jq -r '.expires_at // "none"' .vbw-planning/.locks/1-1-T1.lock)" = "none" ]
}

# --- post-task tests ---

@test "control-plane: post-task releases lease" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_lock_lite = true'
  # Create a lock file first
  echo '{"task_id":"1-1-T1","pid":"999","timestamp":"2024-01-01T00:00:00Z","files":["a.js"]}' > ".vbw-planning/.locks/1-1-T1.lock"
  [ -f ".vbw-planning/.locks/1-1-T1.lock" ]
  run bash "$SCRIPTS_DIR/control-plane.sh" post-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "lease_release") | .status == "pass"'
  # Lock file should be removed
  [ ! -f ".vbw-planning/.locks/1-1-T1.lock" ]
}

# --- compile tests ---

@test "control-plane: compile produces context file" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  # context_compiler is already true in test config
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev --phase-dir=.vbw-planning/phases/01-test --plan-path=test-plan.md
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  [ -f ".vbw-planning/phases/01-test/.context-dev.md" ]
}

@test "control-plane: compile output includes context_path" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/control-plane.sh" compile 1 1 1 --role=dev --phase-dir=.vbw-planning/phases/01-test --plan-path=test-plan.md
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.context_path' | grep -q "context-dev.md"
}

# --- full action tests ---

@test "control-plane: full action runs contract then compile" {
  create_test_plan
  create_roadmap
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_contract_lite = true'
  run bash "$SCRIPTS_DIR/control-plane.sh" full 1 1 1 --plan-path=test-plan.md --role=dev --phase-dir=.vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  # Contract step should pass
  echo "$output" | jq -e '.steps[] | select(.name == "contract") | .status == "pass"'
  # Context step should pass
  echo "$output" | jq -e '.steps[] | select(.name == "context") | .status == "pass"'
  # Both artifacts exist
  [ -f ".vbw-planning/.contracts/1-1.json" ]
  [ -f ".vbw-planning/phases/01-test/.context-dev.md" ]
}

# --- gate failure tests ---

@test "control-plane: gate failure returns exit 1" {
  cd "$TEST_TEMP_DIR"
  enable_flags '.v2_hard_gates = true | .v2_hard_contracts = true | .v3_contract_lite = true'
  # No plan file and no contract -> gate should fail on missing contract
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --task-id=1-1-T1
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.steps[] | select(.name == "gate_contract_compliance") | .status == "fail"'
}

# --- individual scripts still callable ---

@test "control-plane: individual scripts still callable directly" {
  cd "$TEST_TEMP_DIR"
  # generate-contract.sh with no args -> usage, exit 0
  run bash "$SCRIPTS_DIR/generate-contract.sh"
  [ "$status" -eq 0 ]

  # lock-lite.sh with no args -> usage, exit 0
  run bash "$SCRIPTS_DIR/lock-lite.sh"
  [ "$status" -eq 0 ]

  # lease-lock.sh with no args -> usage, exit 0
  run bash "$SCRIPTS_DIR/lease-lock.sh"
  [ "$status" -eq 0 ]

  # hard-gate.sh with no args -> exit 0 (insufficient args output)
  run bash "$SCRIPTS_DIR/hard-gate.sh"
  [ "$status" -eq 0 ]

  # compile-context.sh with no args -> exit 1 (usage)
  run bash "$SCRIPTS_DIR/compile-context.sh"
  [ "$status" -eq 1 ]
}

# --- usage tests ---

@test "control-plane: no args prints usage and exits 0" {
  run bash "$SCRIPTS_DIR/control-plane.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "control-plane: JSON output format correct" {
  create_test_plan
  cd "$TEST_TEMP_DIR"
  enable_flags '.v3_contract_lite = true'
  run bash "$SCRIPTS_DIR/control-plane.sh" pre-task 1 1 1 --plan-path=test-plan.md --task-id=1-1-T1
  [ "$status" -eq 0 ]
  # Verify valid JSON with action and steps fields
  echo "$output" | jq -e '.action == "pre-task"'
  echo "$output" | jq -e '.steps | type == "array"'
  echo "$output" | jq -e '.steps | length > 0'
}
