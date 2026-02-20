#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  # Enable configurable flags for advanced/scale features
  cd "$TEST_TEMP_DIR"
  jq '.lease_locks = true | .event_recovery = true | .monorepo_routing = true' \
    .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
}

teardown() {
  teardown_temp_dir
}

# --- lease-lock.sh tests ---

@test "lease-lock: acquire creates lock with TTL" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire test-task --ttl=60 file1.sh file2.sh
  [ "$status" -eq 0 ]
  [ "$output" = "acquired" ]
  [ -f ".vbw-planning/.locks/test-task.lock" ]
  # Verify TTL fields
  jq -e '.ttl == 60' .vbw-planning/.locks/test-task.lock
  jq -e '.expires_at > 0' .vbw-planning/.locks/test-task.lock
  jq -e '.files | length == 2' .vbw-planning/.locks/test-task.lock
}

@test "lease-lock: renew extends lease" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/lease-lock.sh" acquire test-task --ttl=60 file1.sh
  OLD_EXPIRES=$(jq '.expires_at' .vbw-planning/.locks/test-task.lock)
  sleep 1
  run bash "$SCRIPTS_DIR/lease-lock.sh" renew test-task
  [ "$status" -eq 0 ]
  [ "$output" = "renewed" ]
  NEW_EXPIRES=$(jq '.expires_at' .vbw-planning/.locks/test-task.lock)
  [ "$NEW_EXPIRES" -ge "$OLD_EXPIRES" ]
}

@test "lease-lock: check detects expired locks" {
  cd "$TEST_TEMP_DIR"
  # Create a lock that's already expired
  mkdir -p .vbw-planning/.locks
  PAST_EPOCH=$(($(date -u +%s) - 100))
  jq -n --argjson exp "$PAST_EPOCH" \
    '{"task_id":"old-task","pid":"1","timestamp":"2026-01-01T00:00:00Z","files":["shared.sh"],"ttl":60,"expires_at":$exp}' \
    > .vbw-planning/.locks/old-task.lock

  run bash "$SCRIPTS_DIR/lease-lock.sh" check new-task shared.sh
  [ "$status" -eq 0 ]
  # Expired lock should have been cleaned up, so no conflict
  [[ "$output" == *"clear"* ]]
  [[ "$output" == *"expired"* ]]
  # Expired lock file should be removed
  [ ! -f ".vbw-planning/.locks/old-task.lock" ]
}

@test "lease-lock: release removes lock" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/lease-lock.sh" acquire test-task file1.sh
  run bash "$SCRIPTS_DIR/lease-lock.sh" release test-task
  [ "$status" -eq 0 ]
  [ "$output" = "released" ]
  [ ! -f ".vbw-planning/.locks/test-task.lock" ]
}

@test "lease-lock: exits 0 when lease_locks disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.lease_locks = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire test-task file1.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "lease-lock: exits non-zero on conflict (hard_gates graduated, always-on)" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/lease-lock.sh" acquire other-task file1.sh >/dev/null 2>&1
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire new-task file1.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"conflict_blocked"* ]]
}

@test "lease-lock: conflict always blocks (hard_gates graduated)" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/lease-lock.sh" acquire other-task file1.sh >/dev/null 2>&1
  run bash "$SCRIPTS_DIR/lease-lock.sh" acquire new-task file1.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"conflict_blocked"* ]]
}

@test "lease-lock: query returns lock info" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/lease-lock.sh" acquire test-task file1.sh >/dev/null
  run bash "$SCRIPTS_DIR/lease-lock.sh" query test-task
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task_id == "test-task"'
  echo "$output" | jq -e '.files | length == 1'
}

@test "lease-lock: query returns no_lock when absent" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/lease-lock.sh" query nonexistent
  [ "$status" -eq 0 ]
  [ "$output" = "no_lock" ]
}

# --- recover-state.sh tests ---

@test "recover-state: reconstructs state from event log and summaries" {
  cd "$TEST_TEMP_DIR"
  # Create phase directory with plans and a summary
  mkdir -p .vbw-planning/phases/05-test-phase
  cat > .vbw-planning/phases/05-test-phase/05-01-PLAN.md <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
wave: 1
depends_on: []
must_haves: []
---
# Plan 05-01
EOF
  cat > .vbw-planning/phases/05-test-phase/05-02-PLAN.md <<'EOF'
---
phase: 5
plan: 2
title: "Test Plan 2"
wave: 2
depends_on: [1]
must_haves: []
---
# Plan 05-02
EOF
  # Only first plan has a summary
  cat > .vbw-planning/phases/05-test-phase/05-01-SUMMARY.md <<'EOF'
---
phase: 5
plan: 1
title: "Test Plan"
status: complete
tasks_completed: 3
tasks_total: 3
---
# Summary
EOF

  # Create event log
  mkdir -p .vbw-planning/.events
  echo '{"ts":"2026-01-01T00:00:00Z","event":"phase_start","phase":5}' > .vbw-planning/.events/event-log.jsonl
  echo '{"ts":"2026-01-01T00:01:00Z","event":"plan_end","phase":5,"plan":1,"data":{"status":"complete"}}' >> .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/recover-state.sh" 5 .vbw-planning/phases
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.phase == 5'
  echo "$output" | jq -e '.status == "running"'
  echo "$output" | jq -e '.plans | length == 2'
  echo "$output" | jq -e '.plans[0].status == "complete"'
  echo "$output" | jq -e '.plans[1].status == "pending"'
}

@test "recover-state: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.event_recovery = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/recover-state.sh" 5
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# --- route-monorepo.sh tests ---

@test "route-monorepo: detects package roots from plan files" {
  cd "$TEST_TEMP_DIR"
  # Create monorepo structure
  mkdir -p packages/core packages/utils apps/web
  echo '{}' > packages/core/package.json
  echo '{}' > packages/utils/package.json
  echo '{}' > apps/web/package.json

  # Create a plan referencing files in packages/core
  mkdir -p .vbw-planning/phases/01-test
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: []
---
# Plan
## Tasks
### Task 1: Update core
- **Files:** `packages/core/index.js`, `packages/core/utils.js`
### Task 2: Update web
- **Files:** `apps/web/app.js`
EOF

  run bash "$SCRIPTS_DIR/route-monorepo.sh" .vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq -e 'any(. == "packages/core")'
  echo "$output" | jq -e 'any(. == "apps/web")'
}

@test "route-monorepo: returns empty for non-monorepo" {
  cd "$TEST_TEMP_DIR"
  # No sub-package markers
  mkdir -p .vbw-planning/phases/01-test
  cat > .vbw-planning/phases/01-test/01-01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
title: "Test"
wave: 1
depends_on: []
must_haves: []
---
# Plan
## Tasks
### Task 1: Do something
- **Files:** `src/main.js`
EOF

  run bash "$SCRIPTS_DIR/route-monorepo.sh" .vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "route-monorepo: exits 0 when flag disabled" {
  cd "$TEST_TEMP_DIR"
  jq '.monorepo_routing = false' .vbw-planning/config.json > .vbw-planning/config.json.tmp && \
    mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/route-monorepo.sh" .vbw-planning/phases/01-test
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}
