#!/usr/bin/env bats
# R203: the usage of vbw mutate names the rule form of --none (PLAN Rn.k --none
# REASON) wherever it lists the forms: vbw help, vbw mutate --help and the
# usage a wrong call prints. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "R203: vbw help, vbw mutate --help and a wrong call name PLAN Rn.k --none REASON" {
  vbw_run help
  [[ "$output" == *"PLAN Rn.k --none REASON"* ]] || { echo "$output" | grep mutate; false; }
  vbw_run mutate --help
  [[ "$output" == *"vbw mutate PLAN Rn.k --none REASON"* ]] || { echo "$output"; false; }
  vbw_run mutate P1.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN Rn.k --none REASON"* ]] || { echo "$output"; false; }
}
