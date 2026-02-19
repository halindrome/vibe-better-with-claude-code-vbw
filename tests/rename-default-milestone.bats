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

@test "renames milestones/default/ based on SHIPPED.md content" {
  mkdir -p .vbw-planning/milestones/default/phases/01-setup/02-api-layer
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# Shipped

## What Changed
Foundation setup and API layer implementation

## Phases
- Phase 1: Setup
- Phase 2: API Layer
EOF

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # default/ should no longer exist
  [ ! -d ".vbw-planning/milestones/default" ]

  # A renamed directory should exist (exact slug depends on implementation)
  local renamed_dirs
  renamed_dirs=$(ls -d .vbw-planning/milestones/*/ 2>/dev/null | grep -v default || true)
  [ -n "$renamed_dirs" ]
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

@test "handles missing SHIPPED.md in default milestone" {
  mkdir -p .vbw-planning/milestones/default
  # No SHIPPED.md

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # Should still rename (fallback slug)
  [ ! -d ".vbw-planning/milestones/default" ]
}

@test "handles collision when derived slug already exists" {
  mkdir -p .vbw-planning/milestones/default/phases/01-setup
  cat > .vbw-planning/milestones/default/SHIPPED.md <<'EOF'
# Shipped

## Phases
- Phase 1: Setup
EOF

  # Pre-create destination with same derived slug to force collision
  mkdir -p .vbw-planning/milestones/setup

  run bash "$SCRIPTS_DIR/rename-default-milestone.sh" ".vbw-planning"
  [ "$status" -eq 0 ]

  # default/ should be gone
  [ ! -d ".vbw-planning/milestones/default" ]

  # Original collision target should still be a directory (not overwritten)
  [ -d ".vbw-planning/milestones/setup" ]

  # A suffixed variant should exist (setup-1, setup-2, etc.)
  local suffixed
  suffixed=$(ls -d .vbw-planning/milestones/setup-* 2>/dev/null | head -1)
  [ -n "$suffixed" ]
  [ -d "$suffixed/phases/01-setup" ]
}
