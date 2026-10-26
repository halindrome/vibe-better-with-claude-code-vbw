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

# R207: the same scenario, run again, records whether the Dev's vbw mutate calls
# ended with the breakdown (the own-work line and the steps line), read from the
# tool results in the session transcripts, never from screen text.

@test "R207: the taskbreak scenario reads the mutate breakdown from the transcripts' tool results and records it as a fact" {
  body taskbreak | grep -q 'mutate_breakdown_line' || { echo "scenario_taskbreak does not record mutate_breakdown_line"; false; }
  body taskbreak | grep -q 'mutate_steps_line' || { echo "scenario_taskbreak does not record mutate_steps_line"; false; }
  body taskbreak | grep -qE "transcript_tool_output .*vbw mutate.*VBW.s own work" || { echo "the own-work fact is not read from the mutate tool results"; false; }
  body taskbreak | grep -qE "transcript_tool_output .*vbw mutate.*steps of" || { echo "the steps fact is not read from the mutate tool results"; false; }
}

@test "R207: the committed taskbreak result from this code shows the breakdown line in a real session's vbw mutate output" {
  local f="$RESULTS/taskbreak.json"
  [ -f "$f" ] || { echo "the taskbreak scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "taskbreak" and .passed == true and .evidence_level == "L3"
    and (.at | type == "string" and . >= "2026-10-26")
    and .facts.mutate_breakdown_line == true and .facts.mutate_steps_line == true' "$f" || { cat "$f"; false; }
}

# R209: the same scenario, run again on the code that marks another plan's rules
# and checks in vbw show plan: the Dev of the early plan P1.1 sees R1.2 and C2
# marked as P1.2's, never blocks on C2, and P1.1 keeps its one file. Both facts
# are read from the transcripts' tool calls and results and from the record,
# never from the screen.

@test "R209: the taskbreak scenario reads vbw show plan's marks from the transcripts' tool results, as the fact show_plan_marked" {
  body taskbreak | grep -q 'show_plan_marked' || { echo "scenario_taskbreak does not record show_plan_marked"; false; }
  body taskbreak | grep -E "transcript_tool_output .*vbw show plan P1" | grep -qF "built after this plan" || { echo "the rule mark on R1.2 is not read from the show plan tool output"; false; }
  body taskbreak | grep -E "transcript_tool_output .*vbw show plan P1" | grep -qF "red until it is built" || { echo "the check mark on C2 is not read from the show plan tool output"; false; }
  if body taskbreak | grep -qE 'screen \|.*(show plan|marked|block)'; then false; fi
}

@test "R209: the scenario records early_plan_never_blocked: no vbw plan block P1.1 tool call, and P1.1's recorded files still exactly greet.sh" {
  body taskbreak | grep -q 'early_plan_never_blocked' || { echo "scenario_taskbreak does not record early_plan_never_blocked"; false; }
  body taskbreak | grep -qF 'plan block P1.1' || { echo "the scenario does not look for a vbw plan block P1.1 tool call"; false; }
  body taskbreak | grep -qF '["greet.sh"]' || { echo "the scenario does not hold P1.1's files to [\"greet.sh\"]"; false; }
  for k in task_break_recorded checks_run other_rule_check_red_at_break early_plan_built_first later_plan_completed mutate_breakdown_line mutate_steps_line; do
    body taskbreak | grep -qF "$k" || { echo "the earlier fact $k is gone"; false; }
  done
}

@test "R209: the committed taskbreak result from this code passed with show_plan_marked and early_plan_never_blocked true" {
  local f="$RESULTS/taskbreak.json"
  [ -f "$f" ] || { echo "the taskbreak scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "taskbreak" and .passed == true and .evidence_level == "L3"
    and (.at | type == "string" and . >= "2026-10-26")
    and .facts.show_plan_marked == true and .facts.early_plan_never_blocked == true
    and .facts.task_break_recorded == true and .facts.other_rule_check_red_at_break == true and .facts.early_plan_built_first == true' "$f" || { cat "$f"; false; }
}
