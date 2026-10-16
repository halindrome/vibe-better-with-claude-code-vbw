#!/usr/bin/env bats
# R190, phase P147 (L1): the panel bench (tools/bench-panel.sh) measures a
# refresh that reads the step note and draws the step. Whether the cost stays
# within its budget is the benchmark's own verdict in the release run (bash
# tools/test.sh --release), never in vbw prove: here the limit is out of reach.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R190: the panel bench measures a refresh that reads the step note and draws the step" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel bench"; false; }
  VBW_PANEL_BUDGET_MS=100000 VBW_BENCH_RUNS=30 run bash "$REPO_ROOT/tools/bench-panel.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"refresh with a running step: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
}
