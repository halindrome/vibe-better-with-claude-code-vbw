#!/usr/bin/env bats
# R194: the real-user scenario `fixchecks` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): QA fails a requirement whose approved check covers less
# than the requirement says; the fix's Dev adds the missing case to the
# requirement's own check file and commits it with `vbw commit --fix`, and the
# user approves once, by the choice VBW asks. Judged in git (the commit's
# trailers and the files it touches) and in the record (QA's verdict, the fix,
# the approval decisions), never on screen. As in tests/l3-smallchange.bats
# these tests do not run Claude Code (L1): they hold the scenario's structure,
# and its committed result once the release run wrote one, to facts from the
# record and git.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R194: the fixchecks scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_fixchecks()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw fixchecks
  sed -n '1,20p' "$SUITE" | grep -qw fixchecks
}

@test "R194: it seeds a check that covers less than the requirement, approves by the choice, and reads the commits' trailers and files in git" {
  [ -n "$(body fixchecks)" ]
  body fixchecks | grep -q 'result_write fixchecks '
  body fixchecks | grep -qi 'fixture='
  body fixchecks | grep -qF 'Approve contract'
  body fixchecks | grep -qF 'VBW-Fix:'
  body fixchecks | grep -qF 'VBW-Req:'
  body fixchecks | grep -qE 'git .*(show|diff-tree|log)'
  body fixchecks | grep -qE 'decisions'
  if body fixchecks | grep -qE 'screen \|.*grep.*(fix|commit)'; then false; fi
}

@test "R194: the result states each fact the scenario judged" {
  local k
  for k in first_qa_verdict fix_source fix_check_commits check_commit_only_check_files approvals questions regression_case_in_check; do
    body fixchecks | grep -qF "$k"
  done
}

@test "R194: a committed result of the fixchecks scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/fixchecks.json"
  [ -f "$f" ] || skip "no fixchecks result committed yet: the release run writes it"
  jq -e '.scenario == "fixchecks" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f"
}
