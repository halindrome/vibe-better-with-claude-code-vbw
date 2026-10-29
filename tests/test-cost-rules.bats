#!/usr/bin/env bats
# What keeps every project's tests cheap without making anyone wait. The Lead
# plans lean checks: one test file per requirement area (a new requirement adds
# cases there; its check runs them with the runner's case filter), an expensive
# fixture built once per file and copied or reset per case, a detail tested at
# the smallest function or command that decides it, no sleeps, no timing
# assertions in checks; its self-review refuses a case that repeats another
# check; a changed rule edits or deletes the cases it supersedes ("supersede,
# don't stack", named in choices). A Dev's and the Debugger's regression case
# goes into the existing check or test file; a new file only when none exists.
# QA keeps a test's own cost a note, never a finding. AGENTS.md carries the same
# rules for VBW's own tests. The docs name the unit-time report and
# check_budget, which reports and never enforces. L1: the text of the agents,
# the fixing workflow, AGENTS.md and the docs (one line holds each rule's facts;
# D400: no exact wording).

load helper

# has_line FILE WORD...: one line of FILE holds every WORD (case-insensitive).
has_line() {
  local f="$1" lines w
  shift
  lines=$(cat "$f")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of $f holds all of: $*"; return 1; }; done
}

LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "lean checks: the Lead puts a new requirement's cases in its area's test file and runs them with the case filter" {
  has_line "$LEAD" "one test file per requirement area" "adds its cases" "case filter"
}

@test "lean checks: the Lead builds an expensive fixture once per file, tests a detail at the smallest unit, and plans no sleep or timing assertion" {
  has_line "$LEAD" fixture "once per file" "per case" setup_file beforeAll TestMain
  has_line "$LEAD" "smallest function or command"
  has_line "$LEAD" "no sleeps" condition clock
  has_line "$LEAD" "no timing assertions"
}

@test "lean checks: the Lead's self-review refuses a case another check already pins; a changed rule supersedes its old cases" {
  sed -n '/^## Stage 3/,/^## Stage 4/p' "$LEAD" | grep -iF 'repeats' | grep -qiF 'another check' || { echo "Stage 3 does not check for repeated cases"; false; }
  has_line "$LEAD" supersede "edits or deletes" choices approval
  has_line "$LEAD" "check files of finished work" "add a new requirement" supersede
}

@test "lean checks (#722): the Lead proves each check fails today with that check's own argv, once, never with a whole-suite run" {
  has_line "$LEAD" "fails today" "own argv" once "whole suite"
}

@test "lean checks: a Dev's and the Debugger's regression case goes into the existing file; a new file only when none exists" {
  has_line "$PLUGIN_ROOT/agents/dev.md" "regression case" "existing check file" "new test file only when"
  has_line "$PLUGIN_ROOT/workflows/fixing.js" "existing check file of the finding" "only when it has none"
  has_line "$PLUGIN_ROOT/agents/debugger.md" regression "existing test file" "new file only when none exists"
}

@test "lean checks: QA keeps a test's own cost a note, never a finding" {
  has_line "$PLUGIN_ROOT/agents/qa.md" "fixture rebuilt per case" sleep "repeating" "never a finding"
}

@test "lean checks: AGENTS.md holds the same rules for VBW's own tests" {
  has_line "$REPO_ROOT/AGENTS.md" "lean tests" "one test file per requirement area" setup_file "smallest function or command" supersedes
  has_line "$REPO_ROOT/AGENTS.md" "no sleeps" "timing assertions"
}

@test "unit time: the docs describe the report and check_budget, which never fails a proof" {
  local proof="$REPO_ROOT/docs/proof.md"
  grep -q '^### Unit time and the budget per unit$' "$proof"
  has_line "$proof" "never fails" proof
  grep -qE '^slowest units: .+ \([0-9]+% of [0-9]+ s unit time\); over budget \(more than [0-9]+ s\): ' "$proof"
  grep -qF 'vbw config set check_budget 60' "$proof"
  grep -qF 'vbw config set check_budget default' "$proof"
  grep -qE '^  unit time: [0-9]+ s in [0-9]+ units, each as it last ran; the slowest:$' "$proof"
  grep -qE '^unit time: [0-9]+ s in [0-9]+ units, \+[0-9]+ s since M[0-9]+ started' "$proof"
  has_line "$proof" "units that no longer exist"
  has_line "$REPO_ROOT/docs/record.md" check_budget 86400 120 "over budget"
  has_line "$REPO_ROOT/README.md" '`check_budget`' 86400 120
  has_line "$PLUGIN_ROOT/skills/config/SKILL.md" '`check_budget`' 86400 120
  "$VBW" help | grep -F 'check_budget' | grep -qF 'default 120'
}
