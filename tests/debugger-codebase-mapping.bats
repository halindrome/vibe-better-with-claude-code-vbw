#!/usr/bin/env bats

# Tests for issue #75: Debugger agent should reference codebase mapping before investigating

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# =============================================================================
# Agent definition: debugger references codebase mapping
# =============================================================================

@test "debugger agent references codebase mapping in investigation protocol" {
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent checks META.md for mapping existence" {
  grep -q 'META.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references ARCHITECTURE.md" {
  grep -q 'ARCHITECTURE.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references CONCERNS.md" {
  grep -q 'CONCERNS.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references PATTERNS.md" {
  grep -q 'PATTERNS.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent references DEPENDENCIES.md" {
  grep -q 'DEPENDENCIES.md' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

# =============================================================================
# Compiled context: codebase mapping hint in debugger context
# =============================================================================

# Helper: set up minimal .vbw-planning structure for compile-context.sh
setup_debugger_context() {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  create_test_config

  cat > "$TEST_TEMP_DIR/.vbw-planning/ROADMAP.md" <<'ROADMAP'
## Phases

## Phase 1: Debug Phase
**Goal:** Fix the broken widget
**Reqs:** REQ-01
**Success:** Widget renders correctly

---

## Phase 2: Future Phase
**Goal:** Placeholder
**Reqs:** REQ-02
**Success:** Placeholder
ROADMAP

  cat > "$TEST_TEMP_DIR/.vbw-planning/REQUIREMENTS.md" <<'REQS'
## Requirements
- [REQ-01] Widget must render correctly
REQS

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
## Status
Phase: 1 of 1 (Debug Phase)
Status: executing
Progress: 0%

## Activity
- Bug reported in widget rendering

## Decisions
- None
STATE
}

@test "compile-context.sh debugger context includes codebase mapping hint when mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create codebase mapping files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture overview" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Known concerns" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context lists available mapping files" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md
  echo "# Dependencies" > .vbw-planning/codebase/DEPENDENCIES.md
  echo "# Structure" > .vbw-planning/codebase/STRUCTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "PATTERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "DEPENDENCIES.md" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger context omits codebase mapping when no mapping exists" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # No codebase directory created
  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

@test "compile-context.sh debugger context omits codebase mapping when META.md missing" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Create directory but no META.md (incomplete mapping)
  mkdir -p .vbw-planning/codebase
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT contain codebase mapping section without META.md
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# QA finding: guidance text adapts to available files
# =============================================================================

@test "compile-context.sh debugger guidance mentions only files that exist" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Only META.md + ARCHITECTURE.md (no CONCERNS, PATTERNS, DEPENDENCIES)
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should mention ARCHITECTURE.md in guidance
  grep -q "Read ARCHITECTURE.md first" ".vbw-planning/phases/01-test/.context-debugger.md"
  # Should NOT mention CONCERNS.md in guidance
  run grep "CONCERNS.md first" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

@test "compile-context.sh debugger guidance mentions all four when all exist" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md
  echo "# Patterns" > .vbw-planning/codebase/PATTERNS.md
  echo "# Dependencies" > .vbw-planning/codebase/DEPENDENCIES.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  grep -q "ARCHITECTURE.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "CONCERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "PATTERNS.md" ".vbw-planning/phases/01-test/.context-debugger.md"
  grep -q "DEPENDENCIES.md" ".vbw-planning/phases/01-test/.context-debugger.md"
}

@test "compile-context.sh debugger omits map section when META.md exists but no key files" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  # Only META.md, none of the 5 key files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md

  run bash "$SCRIPTS_DIR/compile-context.sh" "01" "debugger" ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  # Should NOT show Codebase Map section when no key files exist
  run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-debugger.md"
  [ "$status" -eq 1 ]
}

# =============================================================================
# QA finding: cache invalidation when codebase mapping changes
# =============================================================================

@test "cache-context.sh debugger hash changes when codebase mapping files change" {
  cd "$TEST_TEMP_DIR"

  # Set up mapping files
  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture v1" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns v1" > .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  # Remove a mapping file
  rm .vbw-planning/codebase/CONCERNS.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 debugger "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  [ "$HASH1" != "$HASH2" ]
}

@test "cache-context.sh non-debugger hash unaffected by codebase mapping" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH1=$(echo "$output" | cut -d' ' -f2)

  # Remove mapping file
  rm .vbw-planning/codebase/ARCHITECTURE.md

  run bash "$SCRIPTS_DIR/cache-context.sh" 01 dev "$TEST_TEMP_DIR/.vbw-planning/config.json"
  HASH2=$(echo "$output" | cut -d' ' -f2)

  # Dev hash should be unchanged — codebase mapping only affects debugger
  [ "$HASH1" = "$HASH2" ]
}

# =============================================================================
# debug.md command: prompt includes codebase bootstrap instruction
# =============================================================================

@test "debug.md Path B prompt includes codebase bootstrap instruction" {
  # The Path B prompt template block must include codebase bootstrap
  grep -A20 'Path B.*Standard' "$PROJECT_ROOT/commands/debug.md" | grep -q '.vbw-planning/codebase/'
}

@test "debug.md Path B prompt mentions .vbw-planning/codebase/" {
  # The prompt template must tell the debugger to check for codebase mapping
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug.md Path A task prompt includes codebase bootstrap instruction" {
  # Path A creates 3 tasks — each task prompt should mention codebase bootstrap
  grep -q '.vbw-planning/codebase/' "$PROJECT_ROOT/commands/debug.md"
  # Both Path A and Path B sections should reference it
  grep -A20 'Create.*tasks via TaskCreate' "$PROJECT_ROOT/commands/debug.md" | grep -q '.vbw-planning/codebase/'
}

# =============================================================================
# Role isolation: other roles omit codebase mapping
# =============================================================================

@test "compile-context.sh other roles omit codebase mapping even when present" {
  setup_debugger_context
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/codebase
  echo "# Meta" > .vbw-planning/codebase/META.md
  echo "# Architecture" > .vbw-planning/codebase/ARCHITECTURE.md
  echo "# Concerns" > .vbw-planning/codebase/CONCERNS.md

  for role in lead dev qa scout architect; do
    run bash "$SCRIPTS_DIR/compile-context.sh" "01" "$role" ".vbw-planning/phases"
    [ "$status" -eq 0 ]
    run grep "Codebase Map" ".vbw-planning/phases/01-test/.context-${role}.md"
    [ "$status" -eq 1 ]
  done
}
