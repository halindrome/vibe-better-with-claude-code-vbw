#!/usr/bin/env bats
# R189, phase P145: the panel scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3), shows a needs-you line clearing once its gate is
# answered, a finished helper leaving Comms, and nothing drawn below the window
# in a short and in a narrow terminal. As in tests/l3-panel.bats these tests do
# not run Claude Code (L1): they hold the scenario's structure and the result
# it wrote under tools/l3-results/. The result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/panel.json"

body() { sed -n '/^scenario_panel()/,/^}/p' "$SUITE"; }

@test "R189: the panel scenario records the Comms facts and the short and narrow windows it used" {
  for fact in need_line_cleared helper_done_cleared no_spill_short no_spill_narrow short_rows narrow_columns; do
    body | grep -q "$fact" || { echo "scenario_panel does not record $fact"; false; }
  done
}

@test "R189: a committed result of the panel scenario shows Comms clearing and nothing spilling, at L3" {
  [ -f "$RESULT" ] || { echo "the panel scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "panel" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-15")
    and .facts.need_line_cleared == true and .facts.helper_done_cleared == true
    and .facts.no_spill_short == true and .facts.no_spill_narrow == true
    and (.facts.short_rows | type == "number" and . > 0 and . <= 30)
    and (.facts.narrow_columns | type == "number" and . > 0 and . <= 100)
    and (.not_tested | type == "array" and length > 0)' "$RESULT"
}

@test "R189: the scenario resizes to a short window of at most 30 rows and a narrow one of at most 100 columns" {
  local rows cols
  rows=$(body | grep -oE 'SHORT_ROWS=[0-9]+' | head -1 | cut -d= -f2)
  cols=$(body | grep -oE 'NARROW_COLUMNS=[0-9]+' | head -1 | cut -d= -f2)
  [ -n "$rows" ] && [ "$rows" -gt 0 ] && [ "$rows" -le 30 ]
  [ -n "$cols" ] && [ "$cols" -gt 0 ] && [ "$cols" -le 100 ]
}
