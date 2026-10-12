#!/usr/bin/env bats
# R173: the status line's 60 ms budget is measured with the cost write in place.
# tools/bench-hooks.sh feeds the status line the cost and token fields Claude
# Code sends and a safe session id, and fails when the side file was not written.
# The limits are set out of reach: only the write is judged here. L1.

load helper

setup() {
  vbw_setup
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  BENCH="$REPO_ROOT/tools/bench-hooks.sh"
}

teardown() { vbw_teardown; }

bench() {
  run env VBW_BENCH_PLUGIN_ROOT="$TEST_ROOT/plugin" VBW_BENCH_RUNS=1 VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 "$@" bash "$BENCH"
}

@test "R173: the bench's status line cases write the cost side file, and pass" {
  bench
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"side file was not written"* ]] || { echo "$output"; false; }
}

@test "R173: a status line that never writes the side file fails the bench, on both records" {
  sed -i.bak 's/mv -f "\$side.\$\$" "\$side"/true/' "$TEST_ROOT/plugin/scripts/vbw-statusline.sh"
  bench
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"status line: the cost side file was not written"* ]] || { echo "$output"; false; }
  [[ "$output" == *"status line (large record): the cost side file was not written"* ]] || { echo "$output"; false; }
}
