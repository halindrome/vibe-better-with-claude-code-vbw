#!/usr/bin/env bats
# R189, phase P145 (L1): the panel bench (tools/bench-panel.sh) measures what a
# redraw of Comms and Mission Control costs with a crew at work, beside the tick
# and the refresh, and its sound case raises the need the way the panel now
# hears it: through Claude Code's question menu. The budget itself is judged in
# the release run (R152), never in vbw prove, so a busy machine fails no proof.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"

@test "R189: the panel bench measures a redraw of Comms and Mission Control with a crew at work" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel bench"; false; }
  VBW_PANEL_BUDGET_MS=100000 VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"render, Comms and Mission Control: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"tick, nothing changed: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
}

@test "R189: the bench's sound case raises the need through Claude Code's question menu" {
  grep -q 'AskUserQuestion' "$REPO_ROOT/tools/bench-panel.mjs"
}

# The render case: a crew at work, and both Comms (AbovePrompt) and Mission
# Control (the Pane) drawn on each refresh; judged against the same budget.
render_block() { awk '/^const render = await measure/ { on = 1 } /^console\.log\(.tick/ { on = 0 } on' "$REPO_ROOT/tools/bench-panel.mjs"; }

@test "R189: the render case runs with a crew at work and draws both Comms and Mission Control each refresh" {
  block="$(render_block)"
  [[ "$block" == *"working("* ]] || { echo "$block"; false; }
  [[ "$block" == *"'AbovePrompt'"* ]] || { echo "$block"; false; }
  [[ "$block" == *"h.render()"* ]] || { echo "$block"; false; }
  [[ "$block" == *"h.advance(TICK)"* ]] || { echo "$block"; false; }
}

@test "R189: the render measure is judged against the same budget as the others" {
  VBW_PANEL_BUDGET_MS=0.000001 VBW_BENCH_RUNS=5 run bash "$BENCH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"over the budget"* ]]
  grep -Eq 'for v in .*"\$render"' "$REPO_ROOT/tools/bench-panel.sh"
}
