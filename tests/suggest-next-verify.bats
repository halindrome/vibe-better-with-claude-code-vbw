#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_phase_with_uat() {
  local phase="$1"
  local slug="$2"
  local severity="${3:-major}"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/${phase}-${slug}"
  local uat_file="$phase_dir/${phase}-UAT.md"

  mkdir -p "$phase_dir"

  cat > "$phase_dir/${phase}-01-PLAN.md" <<EOF
---
phase: $phase
plan: ${phase}-01
title: Sample plan
---
EOF

  cat > "$phase_dir/${phase}-01-SUMMARY.md" <<EOF
---
status: complete
deviations: 0
---
Done.
EOF

  cat > "$uat_file" <<EOF
---
phase: $phase
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample issue
EOF

  if [ "$severity" != "none" ]; then
    cat >> "$uat_file" <<EOF
  - Severity: $severity
EOF
  fi
}

@test "suggest-next verify issues_found escalates major issues to plain vibe remediation" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "08" "cost-basis-integrity-warnings" "major"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 08

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 8"* ]]
  [[ "$output" == *"/vbw:verify --resume -- Continue testing after changes"* ]]
  [[ "$output" != *"/vbw:fix -- Fix the issues found during UAT"* ]]
}

@test "suggest-next verify issues_found keeps quick-fix path for minor-only issues" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "03" "ui-polish" "minor"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 03

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" == *"/vbw:verify --resume -- Continue testing after fix"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation for Phase 3"* ]]
}

@test "suggest-next verify issues_found defaults to escalation when severity is absent" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "05" "legacy-format" "none"

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 05

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 5"* ]]
}

@test "suggest-next verify issues_found detects bold-markdown severity format" {
  cd "$TEST_TEMP_DIR"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/06-bold-fmt"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/06-01-PLAN.md" <<'EOF'
---
phase: 06
plan: 06-01
title: Sample plan
---
EOF
  cat > "$phase_dir/06-01-SUMMARY.md" <<'EOF'
---
status: complete
deviations: 0
---
Done.
EOF
  cat > "$phase_dir/06-UAT.md" <<'EOF'
---
phase: 06
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** sample issue
  - **Severity:** critical
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 06

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation for Phase 6"* ]]
  [[ "$output" != *"/vbw:fix"* ]]
}

@test "suggest-next verify issues_found detects bare-text minor severity" {
  cd "$TEST_TEMP_DIR"
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/07-bare-fmt"
  mkdir -p "$phase_dir"
  cat > "$phase_dir/07-01-PLAN.md" <<'EOF'
---
phase: 07
plan: 07-01
title: Sample plan
---
EOF
  cat > "$phase_dir/07-01-SUMMARY.md" <<'EOF'
---
status: complete
deviations: 0
---
Done.
EOF
  cat > "$phase_dir/07-UAT.md" <<'EOF'
---
phase: 07
status: issues_found
---

## Tests

### P01-T1: sample

- **Result:** issue
- **Issue:** typo in label
Severity: minor
EOF

  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 07

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation"* ]]
}

@test "suggest-next verify issues_found handles unpadded phase number" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "03" "ui-polish" "minor"

  # Pass unpadded "3" instead of "03"
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 3

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:fix -- Fix the issues found during UAT"* ]]
  [[ "$output" != *"/vbw:vibe -- Continue UAT remediation"* ]]
}

@test "suggest-next verify issues_found unpadded phase escalates major correctly" {
  cd "$TEST_TEMP_DIR"
  create_phase_with_uat "08" "api-layer" "major"

  # Pass unpadded "8" instead of "08"
  run bash "$SCRIPTS_DIR/suggest-next.sh" verify issues_found 8

  [ "$status" -eq 0 ]
  [[ "$output" == *"/vbw:vibe -- Continue UAT remediation"* ]]
  [[ "$output" != *"/vbw:fix"* ]]
}