#!/usr/bin/env bats
# R202, phase P161: the greenfield scenario of tools/l3-suite.sh, run in the
# real Claude Code window (L3), records that the proof output of a real session
# carries the two report lines ("VBW's own work: X of Y min" and "ran again: N
# of M units; top reasons: ..."), read from the session transcripts (the
# tool results of the vbw prove calls), never from screen text. As in
# tests/l3-step-time.bats these tests do not run Claude Code (L1): they hold
# the scenario's structure and the result it wrote under tools/l3-results/.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/greenfield.json"

body() { sed -n '/^scenario_greenfield()/,/^}/p' "$SUITE"; }

@test "R202: the greenfield scenario records whether each report line appeared in the proof output" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_greenfield"; false; }
  body | grep -q 'report_own_work_line' || { echo "scenario_greenfield does not record report_own_work_line"; false; }
  body | grep -q 'report_ran_again_line' || { echo "scenario_greenfield does not record report_ran_again_line"; false; }
  body | grep -q 'result_write greenfield' || { echo "scenario_greenfield writes no result"; false; }
}

@test "R202: a committed greenfield result shows both report lines in a real session's proof output, at L3" {
  [ -f "$RESULT" ] || { echo "the greenfield scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "greenfield" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-20")
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and .facts.report_own_work_line == true and .facts.report_ran_again_line == true
    and (.not_tested | type == "array")' "$RESULT" || { cat "$RESULT"; false; }
}
