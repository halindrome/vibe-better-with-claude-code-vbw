#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

# Helper: create a realistic STATE.md with all sections
create_full_state() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# State

**Project:** Test Project

## Current Phase
Phase: 3 of 3 (Final cleanup)
Plans: 2/2
Progress: 100%
Status: complete

## Decisions
- Enabled VBW init scaffolding + codebase map
- Use SwiftUI for all new views

## Todos
- Fix auth module regression (added 2026-02-10)
- [HIGH] Migrate to new API (added 2026-02-11)
- [low] Update README (added 2026-02-12)

## Blockers
None

## Activity Log
- 2026-02-12: Phase 3 built
- 2026-02-11: Phase 2 built
- 2026-02-10: Phase 1 built

## Codebase Profile
- Brownfield: true
- Tracked files (approx): 137
- Primary languages: Swift
EOF
}

# Helper: create STATE.md with Skills section (real-world format)
create_state_with_skills() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# State

**Project:** Skills Project

## Current Phase
Phase: 2 of 2 (Polish)
Plans: 1/1
Progress: 100%
Status: complete

## Decisions
- Use Core Data

### Skills
**Installed:** swiftui-expert-skill, xcodebuildmcp-cli
**Suggested:** None
**Stack detected:** Swift (iOS)
**Registry available:** yes

## Todos
- Explore dark mode (added 2026-02-15)

## Blockers
None

## Activity Log
- 2026-02-15: Phase 2 built
EOF
}

# --- Unit tests for persist-state-after-ship.sh ---

@test "creates root STATE.md with project-level sections after ship" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  # Simulate what Ship mode does: move STATE.md to archive
  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  # Run the script — it should create a new root STATE.md from the archived one
  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  # Root STATE.md should exist
  [ -f .vbw-planning/STATE.md ]

  # Should contain project-level sections
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "Fix auth module regression" .vbw-planning/STATE.md
  grep -q "Migrate to new API" .vbw-planning/STATE.md
  grep -q "## Decisions" .vbw-planning/STATE.md
  grep -q "## Blockers" .vbw-planning/STATE.md
}

@test "excludes milestone-level sections from persisted STATE.md" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  # Should NOT contain milestone-specific data
  ! grep -q "## Current Phase" .vbw-planning/STATE.md
  ! grep -q "Phase: 3 of 3" .vbw-planning/STATE.md
  ! grep -q "## Activity Log" .vbw-planning/STATE.md
  ! grep -q "Phase 3 built" .vbw-planning/STATE.md
}

@test "preserves Codebase Profile section" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test Project"
  [ "$status" -eq 0 ]

  grep -q "## Codebase Profile" .vbw-planning/STATE.md
  grep -q "Brownfield: true" .vbw-planning/STATE.md
  grep -q "Primary languages: Swift" .vbw-planning/STATE.md
}

@test "preserves Skills subsection under Decisions" {
  cd "$TEST_TEMP_DIR"
  create_state_with_skills ".vbw-planning/STATE.md"

  mkdir -p .vbw-planning/milestones/default
  cp .vbw-planning/STATE.md .vbw-planning/milestones/default/STATE.md

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Skills Project"
  [ "$status" -eq 0 ]

  grep -q "### Skills" .vbw-planning/STATE.md
  grep -q "swiftui-expert-skill" .vbw-planning/STATE.md
}

@test "handles STATE.md with no todos (None. placeholder)" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/default
  cat > ".vbw-planning/milestones/default/STATE.md" <<'EOF'
# State

**Project:** Empty Project

## Current Phase
Phase: 1 of 1 (Setup)
Plans: 1/1
Progress: 100%
Status: complete

## Decisions
- Initial setup

## Todos
None.

## Blockers
None

## Activity Log
- 2026-02-18: Phase 1 built
EOF

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Empty Project"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "None." .vbw-planning/STATE.md
}

@test "fails gracefully when archived STATE.md does not exist" {
  cd "$TEST_TEMP_DIR"

  run bash "$SCRIPTS_DIR/persist-state-after-ship.sh" \
    .vbw-planning/milestones/default/STATE.md .vbw-planning/STATE.md "Test"
  [ "$status" -eq 1 ]
}

# --- Integration tests: session-start migration for brownfield ---

@test "session-start migration recovers root STATE.md from archived milestone" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/milestones/default/STATE.md"
  # No root STATE.md, no ACTIVE — simulates post-ship brownfield state

  # Run the migration script
  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  # Root STATE.md should now exist
  [ -f .vbw-planning/STATE.md ]

  # Should have project-level sections
  grep -q "## Todos" .vbw-planning/STATE.md
  grep -q "Fix auth module regression" .vbw-planning/STATE.md
}

@test "session-start migration is idempotent (skips if root STATE.md exists)" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/STATE.md"
  create_full_state ".vbw-planning/milestones/default/STATE.md"

  local before_hash
  before_hash=$(md5 -q .vbw-planning/STATE.md 2>/dev/null || md5sum .vbw-planning/STATE.md | cut -d' ' -f1)

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  local after_hash
  after_hash=$(md5 -q .vbw-planning/STATE.md 2>/dev/null || md5sum .vbw-planning/STATE.md | cut -d' ' -f1)

  [ "$before_hash" = "$after_hash" ]
}

@test "session-start migration skips when ACTIVE file exists" {
  cd "$TEST_TEMP_DIR"
  create_full_state ".vbw-planning/milestones/m1/STATE.md"
  echo "m1" > .vbw-planning/ACTIVE

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  # Should NOT create root STATE.md — ACTIVE means milestone is active, not archived
  [ ! -f .vbw-planning/STATE.md ]
}

@test "migration picks latest milestone when multiple exist" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones/alpha
  cat > ".vbw-planning/milestones/alpha/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- Old todo from alpha (added 2026-01-01)

## Blockers
None
EOF

  mkdir -p .vbw-planning/milestones/beta
  cat > ".vbw-planning/milestones/beta/STATE.md" <<'EOF'
# State

**Project:** Test

## Todos
- New todo from beta (added 2026-02-15)

## Blockers
None
EOF

  run bash "$SCRIPTS_DIR/migrate-orphaned-state.sh" .vbw-planning
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/STATE.md ]
  # Should use the latest milestone's STATE.md (by directory sort order)
  grep -q "## Todos" .vbw-planning/STATE.md
}
