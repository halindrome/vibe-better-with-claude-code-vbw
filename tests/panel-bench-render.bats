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
