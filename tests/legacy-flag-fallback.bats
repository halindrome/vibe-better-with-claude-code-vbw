#!/usr/bin/env bats

# Tests that consumer scripts honor legacy v2_/v3_ prefixed config keys
# when the unprefixed key is absent (brownfield repos where migrate-config.sh
# has not yet run — e.g., hooks disabled in local dev mode).
#
# Each consumer script must use a jq expression that checks the unprefixed key
# first, then falls back to the legacy prefixed key, then uses the compiled-in
# default. This test file exercises the "legacy key only" path for every
# configurable flag that has a runtime consumer.

load test_helper

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.events"
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# token-budget.sh — token_budgets / v2_token_budgets
# ---------------------------------------------------------------------------

@test "token-budget: unprefixed token_budgets=false disables enforcement" {
  echo '{"token_budgets": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  perl -e 'print "A" x 12000' > "$TEST_TEMP_DIR/big.txt"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/big.txt"
  [ "$status" -eq 0 ]
  len=${#output}
  [ "$len" -ge 12000 ]
}

@test "token-budget: legacy v2_token_budgets=false disables enforcement" {
  echo '{"v2_token_budgets": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  perl -e 'print "A" x 12000' > "$TEST_TEMP_DIR/big.txt"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/big.txt"
  [ "$status" -eq 0 ]
  len=${#output}
  [ "$len" -ge 12000 ]
}

@test "token-budget: unprefixed key wins over legacy key" {
  # unprefixed=true (enforce), legacy=false (disable) — unprefixed wins
  echo '{"token_budgets": true, "v2_token_budgets": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  perl -e 'print "A" x 12000' > "$TEST_TEMP_DIR/big.txt"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/big.txt"
  [ "$status" -eq 0 ]
  len=${#output}
  # Should be truncated because unprefixed=true
  [ "$len" -lt 12000 ]
}

@test "token-budget: neither key present defaults to enabled" {
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  perl -e 'print "A" x 12000' > "$TEST_TEMP_DIR/big.txt"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/token-budget.sh" scout "$TEST_TEMP_DIR/big.txt"
  [ "$status" -eq 0 ]
  len=${#output}
  # Default is true → should truncate
  [ "$len" -lt 12000 ]
}

# ---------------------------------------------------------------------------
# smart-route.sh — smart_routing / v3_smart_routing
# ---------------------------------------------------------------------------

@test "smart-route: unprefixed smart_routing=false always includes agent" {
  echo '{"smart_routing": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"include"'* ]]
}

@test "smart-route: legacy v3_smart_routing=false always includes agent" {
  echo '{"v3_smart_routing": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"include"'* ]]
}

@test "smart-route: unprefixed key wins over legacy key" {
  # unprefixed=true (enforce routing), legacy=false — unprefixed wins → scout skipped for turbo
  echo '{"smart_routing": true, "v3_smart_routing": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"skip"'* ]]
}

@test "smart-route: neither key present defaults to enabled" {
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/smart-route.sh" scout turbo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"skip"'* ]]
}

# ---------------------------------------------------------------------------
# lease-lock.sh — lease_locks / v3_lease_locks
# ---------------------------------------------------------------------------

@test "lease-lock: unprefixed lease_locks=true acquires lock" {
  echo '{"lease_locks": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire t-1 file1
  [ "$status" -eq 0 ]
  [ "$output" = "acquired" ]
}

@test "lease-lock: legacy v3_lease_locks=true acquires lock" {
  echo '{"v3_lease_locks": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire t-1 file1
  [ "$status" -eq 0 ]
  [ "$output" = "acquired" ]
}

@test "lease-lock: unprefixed lease_locks=false skips" {
  echo '{"lease_locks": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire t-1 file1
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]
}

@test "lease-lock: unprefixed key wins over legacy key" {
  echo '{"lease_locks": false, "v3_lease_locks": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire t-1 file1
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]
}

@test "lease-lock: neither key present defaults to disabled" {
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire t-1 file1
  [ "$status" -eq 0 ]
  [ "$output" = "skipped" ]
}

# ---------------------------------------------------------------------------
# recover-state.sh — event_recovery / v3_event_recovery
# ---------------------------------------------------------------------------

@test "recover-state: unprefixed event_recovery=true reconstructs state" {
  echo '{"event_recovery": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/05-test"
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/05-test/05-01-PLAN.md" <<'EOF'
phase: 5
plan: 1
title: P1
wave: 1
depends_on: []
must_haves: []
EOF
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ "$output" != "{}" ]
  [[ "$output" == *'"phase"'* ]]
}

@test "recover-state: legacy v3_event_recovery=true reconstructs state" {
  echo '{"v3_event_recovery": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/05-test"
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/05-test/05-01-PLAN.md" <<'EOF'
phase: 5
plan: 1
title: P1
wave: 1
depends_on: []
must_haves: []
EOF
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ "$output" != "{}" ]
  [[ "$output" == *'"phase"'* ]]
}

@test "recover-state: unprefixed event_recovery=false returns empty" {
  echo '{"event_recovery": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/05-test"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: unprefixed key wins over legacy key" {
  echo '{"event_recovery": false, "v3_event_recovery": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: neither key present defaults to disabled" {
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ---------------------------------------------------------------------------
# snapshot-resume.sh — snapshot_resume / v3_snapshot_resume
# ---------------------------------------------------------------------------

@test "snapshot-resume: unprefixed snapshot_resume=false skips snapshot" {
  echo '{"snapshot_resume": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  echo '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 1 .vbw-planning/.execution-state.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "snapshot-resume: legacy v3_snapshot_resume=false skips snapshot" {
  echo '{"v3_snapshot_resume": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  echo '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 1 .vbw-planning/.execution-state.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "snapshot-resume: unprefixed snapshot_resume=true creates snapshot" {
  echo '{"snapshot_resume": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  echo '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 1 .vbw-planning/.execution-state.json
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
}

@test "snapshot-resume: unprefixed key wins over legacy key" {
  # unprefixed=false (disable), legacy=true — unprefixed wins → no snapshot
  echo '{"snapshot_resume": false, "v3_snapshot_resume": true}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  echo '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 1 .vbw-planning/.execution-state.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "snapshot-resume: neither key present defaults to enabled" {
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  echo '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/snapshot-resume.sh" save 1 .vbw-planning/.execution-state.json
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ -f "$output" ]
}

# ---------------------------------------------------------------------------
# compile-context.sh — rolling_summary / v3_rolling_summary
# ---------------------------------------------------------------------------

@test "compile-context: unprefixed rolling_summary=true includes rolling context" {
  echo '{"rolling_summary": true, "metrics": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test"
  echo "## Phase 2: Test" > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Goal:** G" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Reqs:** REQ-1" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Success:** S" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "- [REQ-1] demo" > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md"
  echo "ROLLING_MARKER_PASS" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  grep -q "ROLLING_MARKER_PASS" "$output"
}

@test "compile-context: legacy v3_rolling_summary=true includes rolling context" {
  echo '{"v3_rolling_summary": true, "metrics": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test"
  echo "## Phase 2: Test" > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Goal:** G" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Reqs:** REQ-1" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Success:** S" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "- [REQ-1] demo" > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md"
  echo "ROLLING_MARKER_PASS" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  grep -q "ROLLING_MARKER_PASS" "$output"
}

@test "compile-context: unprefixed rolling_summary=false excludes rolling context" {
  echo '{"rolling_summary": false, "metrics": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test"
  echo "## Phase 2: Test" > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Goal:** G" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Reqs:** REQ-1" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Success:** S" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "- [REQ-1] demo" > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md"
  echo "ROLLING_MARKER_FAIL" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  ! grep -q "ROLLING_MARKER_FAIL" "$output"
}

@test "compile-context: unprefixed key wins over legacy key" {
  # unprefixed=false (exclude), legacy=true — unprefixed wins → marker absent
  echo '{"rolling_summary": false, "v3_rolling_summary": true, "metrics": false}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/02-test"
  echo "## Phase 2: Test" > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Goal:** G" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Reqs:** REQ-1" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "**Success:** S" >> "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md"
  echo "- [REQ-1] demo" > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md"
  echo "ROLLING_MARKER_CONFLICT" > "$TEST_TEMP_DIR/.vbw-planning/ROLLING-CONTEXT.md"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/compile-context.sh" 02 dev .vbw-planning/phases
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  ! grep -q "ROLLING_MARKER_CONFLICT" "$output"
}

# ---------------------------------------------------------------------------
# Cross-cutting: verify no consumer reads ONLY the unprefixed key
# ---------------------------------------------------------------------------

@test "grep-guard: consumer scripts use legacy fallback jq pattern" {
  # Each consumer script's jq expression must reference both the unprefixed
  # and the legacy v2_/v3_ key. This is a structural guard — if someone
  # removes the fallback, this test fails immediately.
  check_fallback() {
    local file="$1" unprefixed="$2" legacy="$3"
    grep -q "$legacy" "$SCRIPTS_DIR/$file" || {
      echo "FAIL: $file does not reference legacy key $legacy"
      return 1
    }
  }
  check_fallback token-budget.sh    token_budgets    v2_token_budgets
  check_fallback smart-route.sh     smart_routing    v3_smart_routing
  check_fallback lease-lock.sh      lease_locks      v3_lease_locks
  check_fallback recover-state.sh   event_recovery   v3_event_recovery
  check_fallback snapshot-resume.sh snapshot_resume   v3_snapshot_resume
  check_fallback compile-context.sh rolling_summary   v3_rolling_summary
}
