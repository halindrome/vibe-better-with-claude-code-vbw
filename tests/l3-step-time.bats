#!/usr/bin/env bats
# R190, phase P148: the steptime scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3) on a realistic project with a seeded step history,
# shows the same end time in VBW's chat message, the status line and Comms for
# a build; a background proof's 'N of M checks' counting up in the status line;
# and, on a project with no history, 'no end time yet'. As in
# tests/l3-panel-comms.bats these tests do not run Claude Code (L1): they hold
# the scenario's structure and the result it wrote under tools/l3-results/. The
# result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/steptime.json"

body() { sed -n '/^scenario_steptime()/,/^}/p' "$SUITE"; }

@test "R190: the suite has a steptime scenario that seeds a step history and records each fact" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_steptime"; false; }
  body | grep -q 'steps.json' || { echo "scenario_steptime does not seed the step history"; false; }
  for fact in chat_end statusline_end comms_end same_end proof_counts proof_counted_up no_history_no_end_time; do
    body | grep -q "$fact" || { echo "scenario_steptime does not record $fact"; false; }
  done
}

@test "R190: a committed result of the steptime scenario shows one end time in chat, status line and Comms, at L3" {
  [ -f "$RESULT" ] || { echo "the steptime scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "steptime" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-16")
    and (.fixture | type == "string" and length > 0)
    and (.facts.chat_end | test("^[0-9]{2}:[0-9]{2}$"))
    and .facts.statusline_end == .facts.chat_end and .facts.comms_end == .facts.chat_end
    and .facts.same_end == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R190: the committed result shows a background proof counting up and 'no end time yet' without history" {
  [ -f "$RESULT" ] || { echo "the steptime scenario has not been run: no result is committed"; false; }
  jq -e '.facts.proof_counted_up == true
    and (.facts.proof_counts | type == "array" and length >= 2)
    and (.facts.proof_counts as $c | all(range(1; $c | length); $c[.] >= $c[. - 1]) and ($c[-1] > $c[0]))
    and .facts.no_history_no_end_time == true' "$RESULT" || { cat "$RESULT"; false; }
}
