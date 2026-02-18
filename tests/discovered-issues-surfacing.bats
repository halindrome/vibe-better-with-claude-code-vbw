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

@test "dev agent DEVN-05 uncertainty fallback disambiguates from table default" {
  # The DEVN-05 paragraph must clarify DEVN-03 fallback vs DEVN-04 table default
  sed -n '/Pre-existing failures (DEVN-05)/,/^$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'DEVN-04'
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

@test "debug command Path A dedup key includes file" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -qi 'test name and file'
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

@test "debugger agent mentions pre_existing_issues in blocker_report" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -q 'pre_existing_issues'
}

@test "debugger agent references blocker_report not debugger_report for schema" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep -q 'blocker_report'
}

@test "debugger agent Step 7 output includes pre-existing issues" {
  # Match the Investigation Protocol step 7 line specifically
  sed -n '/Investigation Protocol/,/^##/p' "$PROJECT_ROOT/agents/vbw-debugger.md" | grep '7\.' | grep -q 'pre-existing'
}

# =============================================================================
# Handoff schema: no debugger_report ghost type
# =============================================================================

@test "handoff schema blocker_report section does not invent debugger_report type" {
  # The blocker_report section must not use 'debugger_report' as if it were a schema type
  ! sed -n '/blocker_report.*Dev.Debugger/,/^## `/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '`debugger_report` variant'
}

@test "handoff schema blocker_report debugger paragraph references blocker_report type" {
  sed -n '/blocker_report.*Dev.Debugger/,/^## `/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q '"type": "blocker_report"'
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

@test "qa_verdict schema includes pre_existing_issues field" {
  sed -n '/qa_verdict/,/^##/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

@test "json schema blocker_report payload_optional includes pre_existing_issues" {
  jq -r '.schemas.blocker_report.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema qa_verdict payload_optional includes pre_existing_issues" {
  jq -r '.schemas.qa_verdict.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "json schema execution_update payload_optional includes pre_existing_issues" {
  jq -r '.schemas.execution_update.payload_optional[]' "$PROJECT_ROOT/config/schemas/message-schemas.json" | grep -q 'pre_existing_issues'
}

@test "handoff schema execution_update example includes pre_existing_issues" {
  sed -n '/execution_update/,/^##/p' "$PROJECT_ROOT/references/handoff-schemas.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Dev agent: structured protocol for pre_existing_issues
# =============================================================================

@test "dev agent Communication section references pre_existing_issues in execution_update" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'pre_existing_issues'
}

@test "dev agent Communication section references execution_update payload" {
  sed -n '/## Communication/,/^##/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'execution_update'
}

# =============================================================================
# Dev agent: DEVN-05 test vs build distinction
# =============================================================================

@test "dev agent DEVN-05 specifies test failures not build errors" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'test.*failure'
}

@test "dev agent DEVN-05 excludes compile/lint/build errors" {
  sed -n '/Pre-existing failures (DEVN-05)/,/^$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -qi 'compile.*lint.*build'
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

@test "qa agent mentions pre_existing_issues in qa_verdict payload" {
  sed -n '/Pre-Existing Failure Handling/,/^##/p' "$PROJECT_ROOT/agents/vbw-qa.md" | grep -q 'pre_existing_issues'
}

# =============================================================================
# Lead agent: pre-existing issue aggregation
# =============================================================================

@test "lead agent has pre-existing issue aggregation section" {
  grep -q 'Pre-Existing Issue Aggregation' "$PROJECT_ROOT/agents/vbw-lead.md"
}

@test "lead agent aggregation mentions execution_update" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'execution_update'
}

@test "lead agent aggregation mentions qa_verdict" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'qa_verdict'
}

@test "lead agent aggregation mentions de-duplicate" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -qi 'de-duplicate'
}

@test "lead agent aggregation mentions blocker_report" {
  sed -n '/Pre-Existing Issue Aggregation/,/^##/p' "$PROJECT_ROOT/agents/vbw-lead.md" | grep -q 'blocker_report'
}

# =============================================================================
# Debug command: schema naming consistency
# =============================================================================

@test "debug command Path A uses blocker_report not debugger_report" {
  sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'blocker_report'
}

@test "debug command Path A does not reference debugger_report schema" {
  ! sed -n '/Path A/,/Path B/p' "$PROJECT_ROOT/commands/debug.md" | grep -q 'debugger_report'
}

# =============================================================================
# VERIFICATION.md format: pre-existing issues section
# =============================================================================

@test "qa agent VERIFICATION.md format includes Pre-existing Issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/agents/vbw-qa.md"
}

@test "verification template has Pre-existing Issues section" {
  grep -q 'Pre-existing Issues' "$PROJECT_ROOT/templates/VERIFICATION.md"
}

@test "verification template Pre-existing Issues has Test/File/Error columns" {
  sed -n '/Pre-existing Issues/,/^##/p' "$PROJECT_ROOT/templates/VERIFICATION.md" | grep -q 'Test.*File.*Error'
}

# =============================================================================
# QA command: discovered issues output + schema consistency
# =============================================================================

@test "qa command references qa_verdict schema not qa_result" {
  # qa_verdict is the canonical schema name; qa_result was a historical mismatch
  ! grep -q 'qa_result' "$PROJECT_ROOT/commands/qa.md"
  grep -q 'qa_verdict' "$PROJECT_ROOT/commands/qa.md"
}

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

@test "qa command spawn prompt reinforces pre-existing reporting" {
  sed -n '/Spawn QA/,/QA agent reads/p' "$PROJECT_ROOT/commands/qa.md" | grep -qi 'pre-existing'
}

# =============================================================================
# Dev agent: Circuit Breaker schema naming
# =============================================================================

@test "dev agent Circuit Breaker references blocker_report not dev_blocker" {
  sed -n '/Circuit Breaker/,/$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'blocker_report'
}

@test "dev agent Circuit Breaker does not reference non-existent dev_blocker schema" {
  ! sed -n '/Circuit Breaker/,/$/p' "$PROJECT_ROOT/agents/vbw-dev.md" | grep -q 'dev_blocker'
}

# =============================================================================
# Execute-protocol: de-duplication for Discovered Issues
# =============================================================================

@test "execute-protocol discovered issues has de-duplication instruction" {
  sed -n '/Discovered Issues/,/display-only/p' "$PROJECT_ROOT/references/execute-protocol.md" | grep -qi 'de-duplicate'
}

# =============================================================================
# Verify command: discovered issues scoped to user-reported
# =============================================================================

@test "verify command discovered issues scoped to user-reported issues" {
  grep -A2 'Discovered Issues' "$PROJECT_ROOT/commands/verify.md" | grep -qi 'user.*reported'
}

# =============================================================================
# Verify command: discovered issues output
# =============================================================================

@test "verify command has discovered issues output section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues uses warning bullet format" {
  grep -q '⚠' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues suggests /vbw:todo" {
  grep -q '/vbw:todo' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify command discovered issues is display-only" {
  grep -q 'display-only' "$PROJECT_ROOT/commands/verify.md"
}

# =============================================================================
# Consistency: all discovered issues blocks use the same format
# =============================================================================

@test "execute-protocol still has discovered issues section" {
  grep -q 'Discovered Issues' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "all discovered issues sections use display-only constraint" {
  local failed=""
  for file in commands/fix.md commands/debug.md commands/qa.md commands/verify.md references/execute-protocol.md; do
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
  for file in commands/fix.md commands/debug.md commands/qa.md commands/verify.md references/execute-protocol.md; do
    if grep -q 'Discovered Issues' "$PROJECT_ROOT/$file"; then
      if ! grep -q '/vbw:todo' "$PROJECT_ROOT/$file"; then
        failed="${failed} ${file}"
      fi
    fi
  done
  [ -z "$failed" ] || { echo "Missing /vbw:todo in:$failed"; return 1; }
}
