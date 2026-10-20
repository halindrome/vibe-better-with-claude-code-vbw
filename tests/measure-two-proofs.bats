#!/usr/bin/env bats
# R202 (tools/measure-proof-speed.sh --two, maintainers only): two proofs of
# the stand-in run at once (two copies of the generated project) while the
# slot store is sampled every second; the tool prints the machine limit and
# the most slots held at any sample, VBW's own bookkeeping entries included,
# and that maximum never exceeds the limit. L1: a small stand-in.

load helper

TOOL="$REPO_ROOT/tools/measure-proof-speed.sh"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

field() { printf '%s\n' "$output" | sed -n "s/^$1: //p" | head -n 1; }

@test "R202: --two runs two proofs at once and reports the most slots held against the machine limit" {
  VBW_MEASURE_DIR="$TEST_ROOT/measure" run bash "$TOOL" --two --files 120 --folders 24 --units 8 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f
  for f in 'machine limit' 'two proofs max held' 'two proofs wall seconds'; do
    [[ "$(field "$f")" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "field '$f' is not a number: '$(field "$f")'"; echo "$output"; false; }
  done
  [ "$(field 'two proofs max held')" -ge 1 ] || { echo "$output"; false; }
  [ "$(field 'two proofs max held')" -le "$(field 'machine limit')" ] || { echo "$output"; false; }
}
