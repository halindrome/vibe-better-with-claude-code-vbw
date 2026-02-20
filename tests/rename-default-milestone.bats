#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/milestones
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "renames milestones/default/ using bulleted phase names" {
  mkdir -p .vbw-planning/milestones/default/phases/01-setup/02-api-layer
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## Phases
- Phase 1: Setup
- Phase 2: API Layer
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # default/ should no longer exist
  [ ! -d ".vbw-planning/milestones/default" ]

  # Should be numbered with phase-derived slug
  [ -d ".vbw-planning/milestones/01-setup-api-layer" ]
}

@test "renames milestones/default/ using numbered bold phase names" {
  mkdir -p .vbw-planning/milestones/default/phases/{01-transfer,02-test-infra,03-service}
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## Phases
1. **Transfer Matching Bug Fix** — Fixed transfer matching bugs
2. **Test Infrastructure** — Built test suite
3. **Service Layer** — Added coverage
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]

  # Should extract first 2 numbered bold phase names, not "What Changed" prose
  [ -d ".vbw-planning/milestones/01-transfer-matching-bug-fix-test-infrastructure" ]
}

@test "uses SHIPPED.md title when not Default Milestone" {
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Sync Hardening

## Phases
- Setup
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]
  [ -d ".vbw-planning/milestones/01-sync-hardening" ]
}

@test "idempotent when no milestones/default/ exists" {
  # No default dir
  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
}

@test "handles SHIPPED.md with no phases section" {
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# Shipped
Date: 2026-02-15
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # default/ should be renamed to something
  [ ! -d ".vbw-planning/milestones/default" ]
}

@test "handles missing SHIPPED.md with phase dirs" {
  mkdir -p .vbw-planning/milestones/default/phases/01-setup
  mkdir -p .vbw-planning/milestones/default/phases/02-api
  # No SHIPPED.md — falls back to phase dir names

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]

  # Should derive slug from phase directory names
  [ -d ".vbw-planning/milestones/01-setup-api" ]
}

@test "handles collision when derived slug already exists" {
  mkdir -p .vbw-planning/milestones/default/phases/01-setup
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## Phases
- Phase 1: Setup
EOF

  # Create collision: numbering counts 1 non-default dir → 02, slug = setup → 02-setup
  # Pre-create 02-setup to force collision
  mkdir -p .vbw-planning/milestones/02-setup

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # default/ should be gone
  [ ! -d ".vbw-planning/milestones/default" ]

  # Original collision target should still be a directory (not overwritten)
  [ -d ".vbw-planning/milestones/02-setup" ]

  # A suffixed variant should exist (02-setup-1)
  [ -d ".vbw-planning/milestones/02-setup-1" ]
  [ -d ".vbw-planning/milestones/02-setup-1/phases/01-setup" ]
}

@test "numbers milestone based on existing milestone count" {
  # Create 2 existing (non-default) milestones
  mkdir -p .vbw-planning/milestones/01-first
  mkdir -p .vbw-planning/milestones/02-second
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## Phases
- Third Feature
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]

  # Should be numbered 03 (2 existing + 1)
  [ -d ".vbw-planning/milestones/03-third-feature" ]
}

@test "does not use What Changed prose for slug" {
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## What Changed
Three large god object services were decomposed into 11 focused single-responsibility services
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]

  # Should NOT contain prose from "What Changed" — should use timestamp fallback
  local renamed
  renamed=$(ls -d .vbw-planning/milestones/*/ 2>/dev/null | head -1)
  renamed=$(basename "$renamed")
  # Should be 01-milestone-YYYYMMDD, not prose
  [[ "$renamed" =~ ^01-milestone-[0-9]{8}$ ]]
}

@test "uses mixed-case Shipped title for slug derivation" {
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# Shipped: Custom Milestone

Date: 2026-02-15
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]
  [ -d ".vbw-planning/milestones/01-custom-milestone" ]
}

@test "parses mixed-case phases heading for slug derivation" {
  mkdir -p .vbw-planning/milestones/default
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# SHIPPED: Default Milestone

## phases
- Phase 1: Setup
- Phase 2: API Layer
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/milestones/default" ]
  [ -d ".vbw-planning/milestones/01-setup-api-layer" ]
}
