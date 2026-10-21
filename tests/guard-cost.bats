#!/usr/bin/env bats
# R76 (hot path, CLAUDE.md): judging what a program writes during a run adds
# work to the guard, which runs before every tool call. The hook benchmark
# measures that case too (a build agent running Python on a build lease).
# Whether its cost is within the hook limit is the benchmark's own verdict in
# the release run (bash tools/test.sh --release, R152), never in vbw prove: here
# the limits are set out of reach, so only the measurement is checked.

load helper

@test "R76: the hook benchmark measures a program command during a run" {
  run env VBW_BENCH_ONLY='guard (interp)|guard (interp, large record)' VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 VBW_BENCH_RUNS=1 bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^guard \(interp\): -?[0-9.]+ ms own CPU per call' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^guard \(interp, large record\): -?[0-9.]+ ms own CPU per call' || { echo "$output"; false; }
}
