#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

create_archived_milestone() {
  local name="${1:-test-milestone}"
  local milestone_dir=".vbw-planning/milestones/$name"
  mkdir -p "$milestone_dir/phases/01-setup" "$milestone_dir/phases/02-build"
  touch "$milestone_dir/phases/01-setup/01-01-PLAN.md"
  touch "$milestone_dir/phases/01-setup/01-01-SUMMARY.md"
  touch "$milestone_dir/phases/02-build/02-01-PLAN.md"
  touch "$milestone_dir/phases/02-build/02-01-SUMMARY.md"

  cat > "$milestone_dir/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Setup
## Phase 2: Build
EOF

  cat > "$milestone_dir/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project
Phase: 2 of 2 (Build)
Status: complete

## Key Decisions
- Use REST API for backend
- PostgreSQL for data store

## Todos
- Upgrade deps after milestone
- [HIGH] Add monitoring dashboard
EOF

  cat > "$milestone_dir/SHIPPED.md" <<'EOF'
# Shipped
Date: 2026-02-15
Phases: 2
EOF
}

create_root_state() {
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project
Phase: -
Status: shipped

## Key Decisions
- Use REST API for backend

## Todos
- [HIGH] Add monitoring dashboard
- Write API docs
EOF
}

@test "merges todos with dedup (same item in both → one copy)" {
  create_archived_milestone "foundation"
  create_root_state

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Phases should be restored to root
  [ -d ".vbw-planning/phases/01-setup" ]
  [ -d ".vbw-planning/phases/02-build" ]

  # ROADMAP should be at root
  [ -f ".vbw-planning/ROADMAP.md" ]

  # STATE.md should exist with merged todos
  [ -f ".vbw-planning/STATE.md" ]

  # Deduplicated: "Add monitoring dashboard" appears in both → one copy
  local count
  count=$(grep -c 'Add monitoring dashboard' ".vbw-planning/STATE.md")
  [ "$count" -eq 1 ]

  # Items unique to each source should be present
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Write API docs' ".vbw-planning/STATE.md"
}

@test "merges todos with disjoint items (all preserved)" {
  create_archived_milestone "foundation"

  # Root state with completely different todos
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Todos
- New todo added post-archive
- Another new item
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # All items from both sources preserved
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Add monitoring dashboard' ".vbw-planning/STATE.md"
  grep -q 'New todo added post-archive' ".vbw-planning/STATE.md"
  grep -q 'Another new item' ".vbw-planning/STATE.md"
}

@test "merges decisions with dedup" {
  create_archived_milestone "foundation"
  create_root_state

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # "Use REST API for backend" is in both → one copy
  local count
  count=$(grep -c 'Use REST API for backend' ".vbw-planning/STATE.md")
  [ "$count" -eq 1 ]

  # "PostgreSQL for data store" only in archived → preserved
  grep -q 'PostgreSQL for data store' ".vbw-planning/STATE.md"
}

@test "handles empty root STATE.md (no post-archive additions)" {
  create_archived_milestone "foundation"

  # Root state with empty sections
  cat > ".vbw-planning/STATE.md" <<'EOF'
# VBW State

**Project:** Test Project

## Todos
None.

## Key Decisions
None.
EOF

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Archived todos should be restored
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
  grep -q 'Add monitoring dashboard' ".vbw-planning/STATE.md"
}

@test "handles missing root STATE.md (only archived copy)" {
  create_archived_milestone "foundation"
  # No root STATE.md at all

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Archived state becomes root
  [ -f ".vbw-planning/STATE.md" ]
  grep -q 'Upgrade deps after milestone' ".vbw-planning/STATE.md"
}

@test "cleans up milestone dir after unarchive" {
  create_archived_milestone "foundation"

  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/foundation" ".vbw-planning"
  [ "$status" -eq 0 ]

  # SHIPPED.md should be deleted
  [ ! -f ".vbw-planning/milestones/foundation/SHIPPED.md" ]

  # Milestone dir should be removed if empty
  [ ! -d ".vbw-planning/milestones/foundation" ]
}

@test "exits 1 on missing milestone dir" {
  run bash "$SCRIPTS_DIR/unarchive-milestone.sh" \
    ".vbw-planning/milestones/nonexistent" ".vbw-planning"
  [ "$status" -eq 1 ]
}
