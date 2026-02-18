#!/usr/bin/env bats

# Tests for discovered issues surfacing across commands and agents
# Issue #98: Pre-existing test failures silently dropped by /vbw:fix, /vbw:debug, /vbw:qa

load test_helper

# =============================================================================
# Dev agent: DEVN-05 Pre-existing deviation code
# =============================================================================

@test "dev agent has DEVN-05 Pre-existing deviation code" {
  grep -q 'DEVN-05' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent DEVN-05 action is note and do not fix" {
  grep 'DEVN-05' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'do not fix'
}

@test "dev agent has pre-existing failure guidance after Stage 2" {
  grep -q 'Pre-existing failures (DEVN-05)' "$PROJECT_ROOT/agents/vbw-dev.md"
}

@test "dev agent pre-existing guidance requires Pre-existing Issues heading" {
  # Find the DEVN-05 paragraph block and check for the heading reference
  sed -n '/Pre-existing failures (DEVN-05)/,/^$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'Pre-existing Issues'
}

@test "dev agent pre-existing guidance says never fix them" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'never.*fix pre-existing'
}

# =============================================================================
# Fix command: discovered issues output
# =============================================================================

@test "fix command prompt instructs Dev to report pre-existing failures" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command prompt mentions pre-existing failures in spawn block" {
  # The spawn prompt template must tell Dev about pre-existing reporting
  sed -n '/^3\./,/^4\./p' "$PROJECT_ROOT/commands/fix.md" | grep -q 'pre-existing'
}

@test "fix command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/fix.md"
}

@test "fix command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/fix.md"
}

# =============================================================================
# Debug command: discovered issues output
# =============================================================================

@test "debug command Path B prompt instructs reporting pre-existing failures" {
  # Path B spawn prompt must mention pre-existing
  sed -n '/Path B/,/^[0-9]\./p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command Path A prompt instructs reporting pre-existing failures" {
  # Path A task creation must mention pre-existing
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'Pre-existing Issues'
}

@test "debug command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/debug.md"
}

@test "debug command Path A has de-duplication instruction" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'de-duplicate'
}

# =============================================================================
# Debugger agent: pre-existing failure handling
# =============================================================================

@test "debugger agent has pre-existing failure handling section" {
  grep -q 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-debugger.md"
}

@test "debugger agent classifies unrelated failures as pre-existing" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -qi 'pre-existing'
}

@test "debugger agent does not fix pre-existing failures" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -qi 'do not.*fix pre-existing'
}

@test "debugger agent mentions pre_existing_issues in debugger_report" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Debugger report schema: pre_existing_issues field
# =============================================================================

@test "handoff schema documents pre_existing_issues field" {
  grep -q 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md"
}

@test "handoff schema pre_existing_issues has test/file/error structure" {
  grep -A2 'pre_existing_issues' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"test"'
}

# =============================================================================
# QA agent: pre-existing failure baseline awareness
# =============================================================================

@test "qa agent has pre-existing failure handling section" {
  grep -q 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "qa agent classifies unrelated failures as pre-existing" {
  grep -A5 'Pre-Existing Failure Handling' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -qi 'pre-existing'
}

@test "qa agent pre-existing failures do not influence verdict" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -qi 'NOT influence.*PASS.*FAIL.*PARTIAL'
}

@test "qa agent requires Pre-existing Issues heading in response" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -q 'Pre-existing Issues'
}

# =============================================================================
# QA command: discovered issues output
# =============================================================================

@test "qa command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/qa.md"
}

@test "qa command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/qa.md"
}

# =============================================================================
# Consistency: all discovered issues blocks use the same format
# =============================================================================

@test "execute-protocol still has discovered issues section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "all discovered issues sections use display-only constraint" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q 'display-only' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing display-only in:$failed"; return 1; }
}

@test "all discovered issues sections suggest /vbw:todo" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/qa.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q '/vbw:todo' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing /vbw:todo in:$failed"; return 1; }
}
