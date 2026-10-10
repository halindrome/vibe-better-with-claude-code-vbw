#!/usr/bin/env bats
# R150 (decision D226; CLAUDE.md hot paths): tools/bench-hooks.sh measures every
# guard input on schema-4 records of 51, 500 and 2,000 checks (the largest over
# 2 MB), each written by the kernel, and every one stays within the same hook
# budget: a guard's cost per call does not climb with the number of checks. L1.

load helper

@test "R150: the hook benchmark measures every guard input on records of 51, 500 and 2,000 checks, all within one budget" {
  run env VBW_BENCH_RUNS=20 bash "$REPO_ROOT/tools/bench-hooks.sh"
  local n line size budget first input
  for n in 51 500 2000; do
    line=$(printf '%s\n' "$output" | grep -E "^record \($n checks\): [0-9]+ bytes, schema [0-9]+$") \
      || { echo "no 'record ($n checks): N bytes, schema S' line"; echo "$output"; false; }
    [[ "$line" == *", schema 4" ]] || { echo "the $n-check record is not schema 4: $line"; false; }
    size=$(printf '%s\n' "$line" | sed -E 's/^.*: ([0-9]+) bytes.*$/\1/')
    [ "$n" != 2000 ] || [ "$size" -gt 2097152 ] || { echo "the 2,000-check record is not over 2 MB: $line"; false; }
    for input in git npm big interp read answer; do
      line=$(printf '%s\n' "$output" | grep -E "^guard \($input, $n checks\): [0-9.]+ ms own CPU per call") \
        || { echo "no line for $input on $n checks"; echo "$output"; false; }
      budget=${line##*; budget }
      [ -n "${first:-}" ] || first=$budget
      [ "$budget" = "$first" ] || { echo "the budget differs: '$budget' and '$first'"; false; }
    done
  done
  ! printf '%s\n' "$output" | grep -q OVER || { echo "$output"; false; }
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
