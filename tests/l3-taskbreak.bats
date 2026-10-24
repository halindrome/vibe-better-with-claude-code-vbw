#!/usr/bin/env bats
# R193: the real-user scenario `taskbreak` in tools/l3-suite.sh (L3, the real
# Claude Code TUI, rigor deep): an approved plan P1.1 is the early plan of a
# requirement that P1.2 completes, and the check of P1.2's rule is red until
# P1.2 is built. The Dev's task break on P1.1 must run only the checks of the
# rules P1.1 owes. Judged in the record (the break's `checks` map) and in git
# (the commit order and the code at the break's commit), never on screen. As
# in tests/l3-smallchange.bats these tests do not run Claude Code (L1): they
# hold the scenario's structure, and its committed result once the release run
# wrote one, to facts from the record and git.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R193: the taskbreak scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_taskbreak()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw taskbreak
  sed -n '1,20p' "$SUITE" | grep -qw taskbreak
}

@test "R193: it seeds an approved two-plan requirement with the rules naming their plans, forces deep, and reads the record and git" {
  [ -n "$(body taskbreak)" ]
  body taskbreak | grep -q 'result_write taskbreak '
  body taskbreak | grep -qi 'fixture='
  body taskbreak | grep -qF 'config rigor deep'
  body taskbreak | grep -qF 'mutations'
  body taskbreak | grep -qE 'git .*(archive|log|show)'
  sed -n '/^taskbreak_seed()/,/^}/p' "$SUITE" | grep -qF '"plan": "P1.1"'
  sed -n '/^taskbreak_seed()/,/^}/p' "$SUITE" | grep -qF '"plan": "P1.2"'
  if body taskbreak | grep -qE 'screen \|.*grep.*(mutat|break)'; then false; fi
}

@test "R193: the result states each fact the scenario judged" {
  local k
  for k in task_break_recorded checks_run other_rule_check_red_at_break early_plan_built_first later_plan_completed; do
    body taskbreak | grep -qF "$k"
  done
}

@test "R193: a committed result of the taskbreak scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/taskbreak.json"
  [ -f "$f" ] || skip "no taskbreak result committed yet: the release run writes it"
  jq -e '.scenario == "taskbreak" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f"
}
