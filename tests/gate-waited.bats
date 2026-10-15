#!/usr/bin/env bats
# T149 (R181, docs/proof.md): a unit that waits at the project's gate (another
# vbw check of the same project holds the check_jobs places) counts that wait
# like a wait for a slot, so the command still ends with its waited line. Before,
# only slot waits were counted and vbw mutate worked around it by taking a slot
# first. L1: unit commands log their start and end (tests/machine-helper.bash).

load helper
load machine-helper

setup() { machine_setup; }
teardown() { machine_teardown; }

@test "T149: a check that waited at the gate for another check of its project says it waited" {
  cores 8
  machine_project "$PROJECT" A 2 3
  (cd "$PROJECT" && "$VBW" config set check_jobs 1 > /dev/null)
  bg "$PROJECT" "$TEST_ROOT/first.out" check C1
  wait_starts 1 A-C1
  run within 30 bash -c 'cd "$1" && exec "$2" check C2' _ "$PROJECT" "$VBW" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; show; false; }
  [[ "$output" == *"waited "* ]] || { echo "$output"; show; false; }
  wait "$BG_PID"
}

@test "T149: vbw mutate takes no slot of its own before its checks" {
  ! grep -qE '^ *slots_take mutate' "$PLUGIN_ROOT/lib/cmd-mutate.sh"
}
