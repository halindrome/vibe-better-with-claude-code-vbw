#!/usr/bin/env bats
# R191, phase P151: the road scenario of tools/l3-suite.sh, run in the real Claude
# Code window (L3) on a project with a seeded tiered history (plans with their tier
# and tasks, proofs with their units, QA phases, fix rounds) and seeded phase
# outcomes, shows: the chat message with both sentences (the step's and the
# milestone's) at a build's start; the same milestone HH:MM in Mission Control; the
# status line showing the step's time only; and, on a project with no history, 'no
# end time yet' for both. As in tests/l3-step-time.bats these tests do not run
# Claude Code (L1): they hold the scenario's structure and the result it wrote under
# tools/l3-results/. The result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/road.json"

body() { sed -n '/^scenario_road()/,/^}/p' "$SUITE"; }

@test "R191: the suite has a road scenario, in its default list, that seeds a tiered history and phase outcomes and records each fact" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_road"; false; }
  grep -E '^ALL=' "$SUITE" | grep -qw road || { echo "road is not in the suite's default list"; false; }
  sed -n '1,20p' "$SUITE" | grep -qw road || { echo "the suite's header does not name road"; false; }
  body | grep -q 'steps.json' || { echo "scenario_road does not seed the step history"; false; }
  body | grep -q 'units' || { echo "scenario_road seeds no units (plans with tiers and tasks, proof units)"; false; }
  body | grep -q 'outcome' || { echo "scenario_road seeds no phase outcomes"; false; }
  body | grep -q 'result_write road ' || { echo "scenario_road writes no result"; false; }
  for fact in chat_step_end chat_road_end panel_road_end same_road_end statusline_has_road no_history_no_end_time; do
    body | grep -q "$fact" || { echo "scenario_road does not record $fact"; false; }
  done
}

@test "R191: a committed result of the road scenario shows both sentences in chat and the same milestone HH:MM in Mission Control, at L3" {
  [ -f "$RESULT" ] || { echo "the road scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "road" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-17")
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and (.facts.chat_step_end | test("^[0-9]{2}:[0-9]{2}$"))
    and (.facts.chat_road_end | test("^[0-9]{2}:[0-9]{2}$"))
    and (.facts.panel_road_end | test("^[0-9]{2}:[0-9]{2}$"))
    and .facts.same_road_end == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R191: the committed result shows the status line without the milestone time, and 'no end time yet' for both without history" {
  [ -f "$RESULT" ] || { echo "the road scenario has not been run: no result is committed"; false; }
  jq -e '.facts.statusline_has_road == false and .facts.no_history_no_end_time == true' "$RESULT" || { cat "$RESULT"; false; }
}
